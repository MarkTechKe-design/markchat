# frozen_string_literal: true

# MarkChat Community Edition Tenant Lockdown & White-Label Initializer
# - Locks all client/tenant workspaces to Community Edition features (zero Enterprise upsells or leaks)
# - Preserves full Enterprise visibility & upgrade controls exclusively inside /super_admin
# - White-labels server-side I18n strings (Chatwoot -> MarkChat, Captain -> MarkCopilot) in memory
# - Zero modifications to upstream Chatwoot files (100% merge-safe)

module MarkChatBrandI18nTransform
  def self.scrub(val)
    case val
    when String
      val
        .gsub(/\bChatwoot\b/, 'MarkChat')
        .gsub(/\bchatwoot\b/, 'markchat')
        .gsub(/\bCaptain\b/, 'MarkCopilot')
    when Hash
      val.transform_values { |v| scrub(v) }
    when Array
      val.map { |v| scrub(v) }
    else
      val
    end
  end
end

Rails.application.config.after_initialize do
  # 1. Context-aware ChatwootApp.enterprise?:
  #    True ONLY inside SuperAdmin::* controllers; False for all client/tenant workspaces & APIs.
  if defined?(ChatwootApp)
    ChatwootApp.singleton_class.class_eval do
      alias_method :upstream_enterprise?, :enterprise? unless method_defined?(:upstream_enterprise?)

      define_method(:enterprise?) do
        return false if ENV.fetch('DISABLE_ENTERPRISE', false)

        if Thread.current[:markchat_super_admin_context]
          upstream_enterprise?
        else
          false
        end
      end
    end
  end

  # 2. Mark SuperAdmin controller requests so only you see Enterprise controls in /super_admin
  if defined?(SuperAdmin::ApplicationController)
    SuperAdmin::ApplicationController.class_eval do
      around_action :with_markchat_super_admin_context

      private

      def with_markchat_super_admin_context
        prev = Thread.current[:markchat_super_admin_context]
        Thread.current[:markchat_super_admin_context] = true
        yield
      ensure
        Thread.current[:markchat_super_admin_context] = prev
      end
    end
  end

  # 3. Enforce Community-only feature flags on tenant accounts (strip premium: true flags from tenant checks)
  premium_flags = begin
    YAML.safe_load(Rails.root.join('config/features.yml').read, aliases: true)
        .select { |f| f['premium'] == true }
        .map { |f| f['name'].to_sym }
  rescue StandardError
    %i[
      disable_branding audit_logs custom_tools sla help_center_embedding_search
      captain_integration custom_roles captain_v1_action_classifier channel_voice
      captain_integration_v2 captain_document_auto_sync advanced_search saml
      advanced_search_indexing csat_review_notes conversation_required_attributes
      advanced_assignment audit_log_ip_address conversation_monitors
      campaign_analytics company_enrichment auto_translate copilot_workflows
      captain_mcp_servers
    ]
  end

  if defined?(Account)
    Account.class_eval do
      alias_method :upstream_feature_enabled?, :feature_enabled? unless method_defined?(:upstream_feature_enabled?)

      define_method(:feature_enabled?) do |name|
        return false if !Thread.current[:markchat_super_admin_context] && premium_flags.include?(name.to_sym)

        upstream_feature_enabled?(name)
      end
    end
  end

  # 4. In-memory I18n white-labeling (Chatwoot -> MarkChat, Captain -> MarkCopilot) without touching locale files
  begin
    I18n.backend.eager_load! if I18n.backend.respond_to?(:eager_load!)
    translations = I18n.backend.send(:translations)
    if translations.is_a?(Hash)
      translations.each do |locale, data|
        translations[locale] = MarkChatBrandI18nTransform.scrub(data)
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[MarkChat I18n] Non-fatal translation transform notice: #{e.message}")
  end
end