# Architectural Blocker Report — SEC-011: Account Suspension Lifecycle

- **Finding ID:** SEC-011
- **Severity:** High (CVSS 7.2)
- **Status:** Architectural Blocker (Upstream Code Modification Prohibited)
- **Affected Upstream Components:**
  - `app/controllers/concerns/ensure_current_account_helper.rb` (Line 11)
  - `app/controllers/api/v1/accounts/base_controller.rb` (Lines 5–15)
  - `app/controllers/api/v1/accounts_controller.rb` (Line 112)
  - `app/channels/room_channel.rb` (Lines 60–66)
- **Upstream Git Baseline:** `af2a870c6d` (Introduced upstream in commit `7b6a56714f`)

---

## 1. Technical Root Cause Analysis

In upstream Chatwoot Community Edition:

1. **Unhandled `NoMethodError` on Suspended API Access:**
   In `ensure_current_account_helper.rb`:
   ```ruby
   def ensure_current_account
     account = Account.find(params[:account_id])
     render_unauthorized('Account is suspended') and return unless account.active?
     ...
   ```
   When `account.active?` is false (`status: :suspended`), `render_unauthorized` returns `nil` from `ensure_current_account`.
   In `Api::V1::Accounts::BaseController`:
   ```ruby
   before_action :current_account
   before_action :validate_token_api_access, if: :authenticate_by_access_token?
   ```
   `validate_token_api_access` invokes `Current.account.api_and_webhooks_enabled?`. Because `Current.account` is `nil`, this triggers a `NoMethodError: undefined method on nil:NilClass` (HTTP 500), rather than a clean HTTP 401/403.
2. **Account Metadata Unchecked:**
   In `Api::V1::AccountsController#fetch_account`, `@account = current_user.accounts.find(params[:id])` lacks `@account.active?` validation. Suspended account owners retain read/write access to basic account settings via `/api/v1/accounts/:id`.
3. **ActionCable Streaming Continues:**
   In `RoomChannel#current_account`, ActionCable checks user account membership but never checks `account.active?`. Established WebSocket connections remain open and stream live account events.

---

## 2. Why Upstream Modification Was Not Performed

Under Section 2 of the MarkChat Engineering Contract:
> "Under no circumstances may you directly modify upstream-origin Chatwoot files... Do not monkey-patch upstream classes or methods as an alternative to editing them... If a required fix cannot be implemented safely without changing upstream-origin code, stop that particular remediation and report the architectural blocker."

Modifying `ensure_current_account_helper.rb`, `room_channel.rb`, or `accounts_controller.rb` would fork core upstream authentication and authorization behavior, causing future merge conflicts and breaking automated upstream sync.

---

## 3. Evaluation of Proposed Rack Middleware Alternative

A proposed MarkChat-owned Rack middleware (`MarkchatSuspensionGuard`) was evaluated as an alternative. However, security analysis proved it cannot provide complete lifecycle enforcement:

1. **Account Enumeration Vulnerability:**
   Checking `Account.find_by(id: ...).suspended?` before authentication causes unauthenticated requests to receive `403 Account is suspended` instead of `401 Unauthorized`, leaking tenant status and account existence to external scanners.
2. **ActionCable Blindspot:**
   Rack middleware only inspects initial HTTP requests. It cannot retroactively terminate active ActionCable WebSocket connections established prior to suspension.
3. **Background Worker Blindspot:**
   Sidekiq background jobs run out-of-process and bypass Rack middleware entirely.

---

## 4. Implemented MarkChat-Owned Interim Mitigation

Under MarkChat ownership boundaries, interim defense-in-depth has been implemented at the **SMS Bridge Boundary** (`C:\Development\markchat-sms-bridge\server.js`):

- **Outbound Telephony Guard:**
  Before dispatching SMS or initiating M-Pesa STK pushes, the bridge verifies `tenant.subscription_status === 'active'`. Suspended accounts are immediately rejected with message status `failed` and private warning notes posted.
- **Inbound SMS Guard:**
  Incoming SMS messages directed to suspended tenants are rejected at the edge with HTTP 403, preventing conversation creation for inactive accounts.

---

## 5. Recommended Resolution (Upstream Pull Request Specification)

To achieve 100% upstream-clean resolution across all layers, the following patch should be submitted to `chatwoot/chatwoot`:

1. **`ensure_current_account_helper.rb`:**
   ```ruby
   def ensure_current_account
     account = Account.find(params[:account_id])
     if account.suspended?
       render json: { error: 'Account is suspended' }, status: :forbidden
       return
     end
     ...
   ```
2. **`room_channel.rb`:**
   Add guard in `subscribed`:
   `reject if @current_account&.suspended?`
3. **`accounts_controller.rb`:**
   Add `@account.active?` check in `fetch_account`.
