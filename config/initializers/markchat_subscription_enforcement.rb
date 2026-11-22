# frozen_string_literal: true

# MarkChat Subscription Access Enforcement Initializer
# Enforces subscription status across ActionCable, Public Inboxes, Direct SMS Webhooks,
# Account APIs, and Agent/Inbox seat quotas.
# Owns: ADR-004 Enforcement Architecture. Zero modifications to upstream Chatwoot files.

Rails.application.config.after_initialize do
  # ==============================================================================
  # 1. ACTIONCABLE (RoomChannel): Fail-closed Authorization & Active Severance
  # ==============================================================================
  RoomChannel.class_eval do
    before_subscribe :validate_markchat_account_active
    after_subscribe :ensure_markchat_severance_stream

    private

    def validate_markchat_account_active
      # 1. Resolve user from pubsub token or parameters
      user = current_user
      if user.blank?
        reject
        return false
      end

      # 2. Resolve target account based on user type and parameters
      account = if user.is_a?(Contact)
                  user.account
                elsif params[:account_id].present?
                  # User must be an authentic member of the target account
                  user.accounts.find_by(id: params[:account_id])
                end

      # Fail closed if account cannot be authenticated, resolved, or membership is absent
      if account.blank?
        reject
        return false
      end

      # 3. Fail closed if the account is suspended
      unless account.active?
        reject
        return false
      end

      true
    rescue StandardError => e
      Rails.logger.error("[MarkChat ActionCable Enforcement] Authorization failed closed: #{e.message}")
      reject
      false
    end

    def ensure_markchat_severance_stream
      account = @current_account
      return if account.blank?

      # Listen to an account-specific severance control stream
      stream_from "account_control_#{account.id}" do |raw_message|
        payload = begin
          ActiveSupport::JSON.decode(raw_message)
        rescue StandardError
          {}
        end

        if payload['action'] == 'disconnect'
          Rails.logger.info("[MarkChat ActionCable] Terminating active WebSocket for suspended account ##{account.id}")
          transmit({ event: 'account.suspended', message: 'Account is suspended' })
          stop_all_streams
          reject
        end
      end
    end
  end

  # ==============================================================================
  # 2. ACCOUNT MODEL: WebSocket Severance & Dynamic Usage Limits
  # ==============================================================================
  Account.class_eval do
    after_update_commit :broadcast_markchat_suspension_severance, if: :markchat_status_suspended?

    def markchat_status_suspended?
      saved_change_to_status? && suspended?
    end

    def broadcast_markchat_suspension_severance
      Rails.logger.info("[MarkChat Account] Broadcasting disconnect severance for suspended account ##{id}")
      ActionCable.server.broadcast("account_control_#{id}", { action: 'disconnect', account_id: id })
    end

    # Dynamic plan usage limits aligned with MarkChat commercial policy
    def usage_limits
      plan_id = custom_attributes&.dig('plan_id') || limits&.dig('plan_id') || 'starter'
      plan_str = plan_id.to_s.downcase

      max_agents = case plan_str
                   when 'growth' then 10
                   when 'scale' then 25
                   when 'enterprise' then 999_999
                   else 3 # Starter default
                   end

      max_inboxes = case plan_str
                    when 'growth' then 5
                    when 'scale', 'enterprise' then 999_999 # Unlimited
                    else 2 # Starter default
                    end

      configured_agents = limits&.dig('agents') || custom_attributes&.dig('max_agents') || custom_attributes&.dig('subscribed_quantity')
      configured_inboxes = limits&.dig('inboxes') || custom_attributes&.dig('max_inboxes')

      {
        agents: (configured_agents.presence || max_agents).to_i,
        inboxes: (configured_inboxes.presence || max_inboxes).to_i
      }
    end
  end

  # ==============================================================================
  # 3. ACCOUNT_USER MODEL: Agent Seat Quota Enforcement
  # ==============================================================================
  AccountUser.class_eval do
    validate :validate_markchat_agent_seat_quota, on: :create

    private

    def validate_markchat_agent_seat_quota
      return if account.blank?

      limit = account.usage_limits[:agents].to_i
      return if limit >= 999_999 || limit.zero?

      if account.account_users.count >= limit
        errors.add(:base, "Agent seat limit of #{limit} reached for your subscription plan. Please upgrade to add more agents.")
      end
    end
  end

  # ==============================================================================
  # 4. INBOX MODEL: Inbox Quota Enforcement
  # ==============================================================================
  Inbox.class_eval do
    validate :validate_markchat_inbox_quota, on: :create

    private

    def validate_markchat_inbox_quota
      return if account.blank?

      limit = account.usage_limits[:inboxes].to_i
      return if limit >= 999_999 || limit.zero?

      if account.inboxes.count >= limit
        errors.add(:base, "Inbox limit of #{limit} reached for your subscription plan. Please upgrade to add more inboxes.")
      end
    end
  end

  # ==============================================================================
  # 5. ACCOUNT API CONTROLLERS: Fail-closed Suspended Account Guard
  # ==============================================================================
  if defined?(Api::V1::Accounts::BaseController)
    Api::V1::Accounts::BaseController.class_eval do
      before_action :validate_markchat_account_not_suspended

      private

      def validate_markchat_account_not_suspended
        return if Current.account.blank? || Current.account.active?

        render json: { error: 'Account is suspended due to billing or administrative policy. Please contact support@markchat.co.ke' }, status: :forbidden
      end
    end
  end

  # ==============================================================================
  # 6. PUBLIC API INBOXES: Fail-closed Account Verification
  # ==============================================================================
  Public::Api::V1::InboxesController.class_eval do
    before_action :validate_markchat_public_inbox_account_active

    private

    def validate_markchat_public_inbox_account_active
      # Resolve the target API channel from params[:inbox_id] or params[:id] (for show)
      channel = @inbox_channel || (params[:id].present? ? ::Channel::Api.find_by(identifier: params[:id]) : nil)
      return if channel.blank? # Let native find_by! handle missing inbox (proper 404)

      inbox = channel.inbox
      if inbox.blank? || inbox.account.blank? || !inbox.account.active?
        render json: { error: 'Account is suspended' }, status: :unauthorized and return
      end
    end
  end

  # ==============================================================================
  # 7. DIRECT SMS WEBHOOKS: Prevent Unauthenticated Direct Injection
  # ==============================================================================
  if defined?(Webhooks::SmsController)
    Webhooks::SmsController.class_eval do
      before_action :validate_markchat_sms_account_active

      private

      def validate_markchat_sms_account_active
        return if params[:phone_number].blank?

        # Find the SMS channel for the target phone number
        channel = ::Channel::Sms.find_by(phone_number: params[:phone_number])
        if channel.present? && !channel.account.active?
          render json: { error: 'Account is suspended' }, status: :unauthorized and return
        end
      end
    end
  end
  # ==============================================================================
  # 8. INTERNAL WEBHOOK SSRF ALLOWLIST: Permit local SMS Reseller Gateway (port 5100)
  # ==============================================================================
  if defined?(SsrfFilter)
    SsrfFilter.singleton_class.class_eval do
      %i[get post put patch delete].each do |verb|
        next unless method_defined?(verb)

        orig = :"upstream_#{verb}"
        alias_method orig, verb unless method_defined?(orig)

        define_method(verb) do |url, options = {}, &block|
          uri = URI.parse(url.to_s)
          if %w[host.docker.internal localhost 127.0.0.1].include?(uri.host.to_s.downcase)
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = options[:open_timeout] || 5
            http.read_timeout = options[:read_timeout] || 10
            klass = Net::HTTP.const_get(verb.to_s.capitalize)
            req = klass.new(uri.request_uri)
            (options[:headers] || {}).each { |k, v| req[k.to_s] = v.to_s }
            req.body = options[:body] if options[:body]
            res = http.request(req)
            block&.call(res)
            res
          else
            send(orig, url, options, &block)
          end
        end
      end
    end
  end
end