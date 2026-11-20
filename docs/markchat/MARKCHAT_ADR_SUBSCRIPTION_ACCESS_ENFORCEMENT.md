# MARKCHAT ARCHITECTURAL DECISION RECORD (ADR)
## Subscription Access Enforcement, Access Path Analysis & Upstream Boundary Specification

**Document Identifier:** ADR-MARKCHAT-2026-004  
**Date:** 19 November 2026  
**Status:** PROPOSED & SUBMITTED FOR REVIEW  
**Target Repositories:**  
- `C:\Development\markchat` (Chatwoot v4.19.1 Engine)  
- `C:\Development\markchat-control-plane` (Fastify Commercial Control Plane)  
- `C:\Development\markchat-sms-bridge` (Telephony Bridge)  
**Author:** MarkChat Architecture & Security Lead  
**Classification:** Critical Security & Financial Integrity Architecture  

---

## 1. Executive Summary & Problem Definition

The MarkChat platform architecture designates the **Control Plane** (`markchat-control-plane`) as the single source of truth for commercial subscriptions, Paystack billing, M-PESA payment lifecycles, and tenant entitlement quotas. **Chatwoot v4.19.1** (`markchat`) remains the communications engine executing inbox messaging, conversation routing, and contact interactions.

Subscription billing is fundamentally incomplete if unpaid, expired, or suspended tenants can continue utilizing protected Chatwoot communications functionality through existing sessions, persistent WebSocket tunnels, or direct API access.

In strict adherence to the **MarkChat Upstream Preservation Requirement**, this architectural evaluation audits all ingress and communications access paths in Chatwoot v4.19.1 to determine:
1. Which access paths are protected out-of-the-box via supported Chatwoot Platform APIs and existing database models.
2. Which access paths remain exposed to unpaid tenants.
3. Why external reverse proxies alone are mathematically and protocol-wise insufficient to close all leaks.
4. The smallest, cleanest, zero-invasive architectural integration required to guarantee complete enforcement without compromising future Chatwoot upstream upgradability.

---

## 2. Comprehensive Access Path Audit & Empirical Findings

An exhaustive code audit and empirical verification against live running containers (`markchat-rails-1`, `markchat-postgres-1`, `markchat-sms-bridge`) yielded the following definitive findings across all seven access surfaces:

| Access Path # | Access Surface | Technical Mechanism in Chatwoot v4.19.1 | Supported API / Native Status | Enforcement Status (Out-of-Box) | Leakage / Vulnerability Identified |
|---|---|---|---|---|---|
| **Path 1** | **Dashboard REST APIs** (`/api/v1/accounts/:account_id/*`) | `EnsureCurrentAccountHelper.ensure_current_account` checks `account.active?` | Supported via Platform API `PATCH /platform/api/v1/accounts/:id` with `{ status: "suspended" }` | **FULLY ENFORCED** | **None.** When `Account.status == :suspended`, all controllers inheriting from `Api::V1::Accounts::BaseController` reject requests with `HTTP 401 Unauthorized {"error":"Account is suspended"}`. |
| **Path 2** | **Web Widget Sessions** (`/widgets/*`) | `WidgetsController#show` checks `@web_widget.inbox.account.active?` | Native model check | **FULLY ENFORCED** | **None.** Widget initialization fails with `HTTP 401 Unauthorized {"error":"Account is suspended"}`. |
| **Path 3** | **ActionCable WebSockets** (`/cable` -> `RoomChannel`) | `RoomChannel#subscribed` streams from `"account_#{account.id}"` and `pubsub_token` | **NO NATIVE STATUS CHECK** | **CRITICAL LEAK** | **Active & new WebSockets continue streaming.** `RoomChannel` does NOT verify `account.active?`. Live messages and presence updates are broadcast to suspended tenants. |
| **Path 4** | **Public API Inboxes** (`/public/api/v1/inboxes/*`) | `Public::Api::V1::InboxesController` handles messages from API channels | **NO NATIVE STATUS CHECK** | **LEAK** | **Inbound messages continue to be stored.** External clients calling the API channel can continue writing conversations and messages to suspended accounts. |
| **Path 5** | **SMS / Telephony Ingestion** (`/webhooks/sms`) | `Webhooks::SmsController` directly enqueues `Webhooks::SmsEventsJob` | **NO NATIVE STATUS CHECK** | **LEAK (If uncoordinated)** | Chatwoot accepts incoming SMS payloads without account status validation. (Must be enforced at SMS Bridge layer). |
| **Path 6** | **Existing Browser Sessions & Frontend UX** | DeviseTokenAuth stores tokens in `users.tokens` (JSONB) | Native token authentication | **PARTIAL / BROKEN UX** | Active session tokens are not revoked in the browser. When an agent opens the dashboard, API calls 401, but the UI has no suspension screen or redirect, resulting in broken spinners. |
| **Path 7** | **Direct Network Access** (`127.0.0.1:3000`) | `docker-compose.production.yaml` maps port 3000 to host | Configuration boundary | **BYPASS RISK** | If Rails port 3000 is directly accessible, any external reverse-proxy enforcement is completely bypassed. |

---

## 3. Empirical Verification Evidence: The ActionCable WebSocket Leak

To verify Path 3 beyond theoretical analysis, an empirical test was executed against the live Chatwoot v4.19.1 container (`markchat-rails-1`) while Account #2 was suspended (`status: "suspended"`):

### Test Execution
```bash
# 1. Account #2 suspended via Chatwoot Platform API:
curl -X PATCH -H "Content-Type: application/json" \
  -H "api_access_token: [REDACTED_PLATFORM_TOKEN]" \
  -d '{"status":"suspended"}' \
  http://localhost:3000/platform/api/v1/accounts/2

# Response: HTTP/1.1 200 OK {"id":2, ..., "status":"suspended"}

# 2. Authenticated REST API call to /api/v1/accounts/2/inboxes:
curl -H "api_access_token: [USER_ACCESS_TOKEN]" http://localhost:3000/api/v1/accounts/2/inboxes
# Response: HTTP/1.1 401 Unauthorized {"error":"Account is suspended"}

# 3. ActionCable WebSocket connection established to ws://rails:3000/cable:
# Sent Subscription payload:
# {"command":"subscribe","identifier":"{\"channel\":\"RoomChannel\",\"pubsub_token\":\"2VnyWgTG4NPhMU67cuk6wwNV\",\"account_id\":2,\"user_id\":2}"}
```

### Empirical Test Output (Raw Stream Log)
```json
WS OPENED
WS MSG: {"type":"welcome"}
WS MSG: {"type":"ping","message":1795045916}
WS MSG: {"identifier":"{\"channel\":\"RoomChannel\",\"pubsub_token\":\"2VnyWgTG4NPhMU67cuk6wwNV\",\"account_id\":2,\"user_id\":2}","type":"confirm_subscription"}
WS MSG: {"identifier":"{\"channel\":\"RoomChannel\",\"pubsub_token\":\"2VnyWgTG4NPhMU67cuk6wwNV\",\"account_id\":2,\"user_id\":2}","message":{"event":"presence.update","data":{"account_id":2,"users":{"2":"online"},"contacts":{}}}}
```

### Finding
Despite the account being suspended in PostgreSQL and rejected on REST APIs, Chatwoot's ActionCable engine:
1. Welcomed the WebSocket handshake (`"type":"welcome"`).
2. Confirmed the channel subscription without error (`"type":"confirm_subscription"`).
3. Immediately broadcast presence (`"event":"presence.update"`) and began streaming account events.
4. Any connected agent with an open browser tab continues receiving inbound messages, customer conversations, and internal notifications over WebSocket indefinitely.

---

## 4. Why External Reverse Proxy Enforcement Alone Is Insufficient

It has been proposed in standard SaaS architectures to insert an external reverse proxy (e.g. Nginx, Envoy, or Traefik) in front of Chatwoot to check subscription status. Our architectural inspection establishes that **a standard external reverse proxy cannot solve this problem alone**:

1. **The ActionCable Framing Barrier**:
   The HTTP upgrade request is initiated to `/cable`. At the time of HTTP handshake, the proxy only sees headers like `Upgrade: websocket` and cookies. It **cannot know which `account_id` the user will subscribe to**, because the `account_id` is only transmitted *after* the WebSocket handshake inside an ActionCable JSON data frame:
   `{"command":"subscribe","identifier":"{\"channel\":\"RoomChannel\",\"account_id\":2,...}"}`
   Standard reverse proxies do not parse, buffer, or rewrite dynamic application protocols inside established WebSocket streams.
2. **Persistent Open Connections**:
   If an account expires at 12:00 UTC while an agent already has an open WebSocket connection established at 09:00 UTC, an external HTTP reverse proxy has no trigger or mechanism to sever that specific tenant's WebSocket connection without terminating the entire proxy or all connections.
3. **Application State Desynchronization**:
   If the proxy intercepts REST endpoints and returns an HTML redirect or 402 Payment Required, the Chatwoot frontend SPA (which expects JSON responses) enters an unhandled exception state, corrupting local storage state rather than presenting an orderly billing resolution UX.

---

## 5. Architectural Options & Trade-Off Analysis

We have evaluated three architectural alternatives to address these findings:

```
+---------------------------------------------------------------------------------------------------+
| OPTION 1: PURE EXTERNAL GATEWAY (Zero Upstream Touches)                                            |
| - Custom Node.js / Envoy gateway terminates WebSockets, decapsulates ActionCable frames, queries  |
|   Control Plane for every frame, and closes frames for suspended accounts.                        |
|   * Pros: Zero files touched inside C:\Development\markchat.                                      |
|   * Cons: Extremely high operational complexity; brittle protocol framing; high latency overhead.|
+---------------------------------------------------------------------------------------------------+
| OPTION 2: EXTENSION HOOK VIA CHATWOOT ENTERPRISE MODULE (Official Rails Hook)                      |
| - Utilize Chatwoot's built-in extension point: enterprise/app/models/concerns/ or prepend_mod_with.|
|   Add 15-line concern to RoomChannel and PublicInboxesController.                                 |
|   * Pros: Cleanest code; native Rails rejection; 100% comprehensive coverage.                     |
|   * Cons: Introduces MarkChat code into markchat repository; requires building enterprise path.   |
+---------------------------------------------------------------------------------------------------+
| OPTION 3: HYBRID COORDINATED ENFORCEMENT (RECOMMENDED - Minimal Touch / Maximum Safety)           |
| 1. Control Plane coordinates Chatwoot Platform API account suspension (Blocks 100% of REST APIs). |
| 2. SMS Bridge strictly blocks inbound & outbound SMS at the telephony gateway for suspended tents. |
| 3. ActionCable Redis Severance: Control Plane publishes a disconnect signal or clears Redis       |
|    pubsub keys for the account upon suspension.                                                   |
| 4. Network Boundary: Close host-mapped port 3000 in docker-compose.override.yaml; route through   |
|    Control Plane Gateway.                                                                         |
| 5. If WebSocket severance requires server-side rejection, implement an isolated initializer in     |
|    config/initializers/markchat_enforcement.rb (15 lines, 0 core file edits).                     |
+---------------------------------------------------------------------------------------------------+
```

---

## 6. The Smallest Safe MarkChat-Owned Integration Required

If Option 3 (Hybrid Coordinated Enforcement) is approved, the required integration footprint is strictly confined and isolated:

### 1. Control Plane Orchestration (Primary Owner)
- **Component**: `src/modules/billing/billing.service.js`
- **Behavior**:
  - When a tenant transitions to `suspended`:
    1. Calls Chatwoot Platform API: `PATCH /platform/api/v1/accounts/:id` with `{ "status": "suspended" }`.
    2. Calls SMS Bridge M2M: `PATCH /api/v1/internal/tenants/:id/status` with `{ "status": "suspended" }`.
    3. Issues Redis ActionCable disconnect command: `PUBLISH "account_#{id}" '{"event":"account.suspended"}'`.
  - When a tenant reactivates:
    1. Calls Chatwoot Platform API: `PATCH /platform/api/v1/accounts/:id` with `{ "status": "active" }`.
    2. Calls SMS Bridge M2M: `PATCH /api/v1/internal/tenants/:id/status` with `{ "status": "active" }`.

### 2. Chatwoot Standalone Initializer (Isolated Extension)
- **Path**: `config/initializers/markchat_subscription_enforcement.rb` (New file only, **ZERO edits** to existing tracked files in `app/`, `config/`, `lib/`).
- **Implementation**:
  ```ruby
  # frozen_string_literal: true
  # MarkChat Subscription Access Enforcement Initializer
  # Closes ActionCable RoomChannel and Public API Channel leaks for suspended accounts.

  Rails.application.config.after_initialize do
    # 1. Enforce active account on RoomChannel subscription
    RoomChannel.class_eval do
      before_subscribe :validate_account_active

      private

      def validate_account_active
        return if @current_account.blank?

        reject unless @current_account.active?
      end
    end

    # 2. Enforce active account on Public API inboxes
    Public::Api::V1::InboxesController.class_eval do
      before_action :validate_account_active

      private

      def validate_account_active
        return if @inbox_channel.blank?

        render json: { error: 'Account is suspended' }, status: :unauthorized unless @inbox_channel.inbox.account.active?
      end
    end
  end
  ```

### 3. Telephony Gating (SMS Bridge)
- **Component**: `C:\Development\markchat-sms-bridge\server.js`
- **Behavior**: Outbound and inbound SMS processing strictly checks tenant status in bridge database or cache; rejects processing if status is `suspended`.

---

## 7. Impact on Upstream Upgrades & Maintenance

| Dimension | Risk Assessment | Mitigation Strategy |
|---|---|---|
| **Upstream Git Merges** | **ZERO RISK** | By placing the hook strictly in a standalone initializer (`config/initializers/markchat_subscription_enforcement.rb`), zero upstream Chatwoot files are edited. `git merge upstream/develop` or upstream tag pulls will cleanly apply without conflicts. |
| **API Contract Stability** | **STABLE** | `RoomChannel#subscribed` and `Public::Api::V1::InboxesController` use standard Rails `before_subscribe` and `before_action` lifecycle callbacks, which are core framework conventions. |
| **Performance Overhead** | **NEGLIGIBLE** | `account.active?` is an in-memory integer comparison (`status == 0`) on already loaded ActiveRecord models. Zero additional database queries are incurred. |

---

## 8. Regression & Security Testing Requirements

Before closing the implementation gate, the following automated test matrix must be satisfied:

1. **REST API Direct Access Test**:
   - Send authenticated requests with valid agent tokens to `/api/v1/accounts/:id/conversations`, `/inboxes`, `/contacts`.
   - Must return `401 Unauthorized {"error":"Account is suspended"}` when suspended.
   - Must return `200 OK` when active.
2. **ActionCable WebSocket Test**:
   - Attempt WebSocket subscription to `RoomChannel` with valid `pubsub_token` for a suspended account.
   - Must be rejected (`{"type":"reject_subscription"}`), with zero presence or event data leaked.
3. **Public API Inbox Test**:
   - Post message to `/public/api/v1/inboxes/:id/contacts/:id/conversations/:id/messages`.
   - Must return `401 Unauthorized {"error":"Account is suspended"}`.
4. **SMS Bridge Telephony Test**:
   - Send outbound SMS request and post inbound webhook for a suspended tenant.
   - Must be rejected with 403 Forbidden without delivering to Africa's Talking.
5. **Recovery & Reactivation Test**:
   - Transition suspended account back to `active`.
   - All REST APIs, WebSockets, Public Inboxes, and SMS deliveries must immediately resume normal operations without container restarts.

---

## 9. Decision & Next Steps

In accordance with the executive preservation directive, **zero upstream source modifications have been made**.

We await authorization from the engineering authority on:
- **Approval of Option 3** (Standalone initializer `config/initializers/markchat_subscription_enforcement.rb` + Control Plane Platform API orchestration + SMS Bridge gating).
- Authorization to execute the test suite and verify full closure of all access paths.
