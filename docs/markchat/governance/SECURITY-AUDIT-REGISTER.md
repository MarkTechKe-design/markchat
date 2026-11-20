# MarkChat — Security Audit Register

- **Project:** MarkChat
- **Upstream foundation:** Chatwoot Community Edition
- **Evidence baseline:** `f230f4ffb5`
- **Review date:** 2026-11-10
- **Audit mode:** Read-only discovery
- **Status:** Configuration and secrets investigation substantially complete; consolidated findings require further verification before remediation.

## 1. Purpose and classification

This register records security and privacy findings identified while evaluating Chatwoot as the technical foundation for MarkChat.

Findings are classified as:

- **Confirmed design weakness:** The inspected implementation demonstrably has the stated limitation.
- **Confirmed data flow:** The inspected implementation demonstrably sends, stores or exposes the stated data.
- **Potential vulnerability:** A plausible exposure path exists, but exploitability has not been demonstrated.
- **Deployment hardening concern:** Security depends on deployment configuration; the repository evidence does not prove a production deployment is vulnerable.
- **Product requirement:** A control MarkChat must independently establish.

Severity ratings are preliminary engineering priorities. They are not proof of exploitation or a substitute for a threat model.

## 2. Findings summary

| ID | Finding | Classification | Preliminary severity | Status |
|---|---|---|---|---|
| SEC-001 | Installation configuration secrets lack model-level encryption | Confirmed design weakness | High | Open |
| SEC-002 | Super Admin secret values are rendered into authenticated browser sessions | Confirmed exposure to privileged sessions | Medium | Open |
| SEC-003 | Global configuration has no built-in secret redaction | Confirmed design limitation | Medium | Open |
| SEC-004 | Active Record encryption is optional and legacy plaintext is supported | Confirmed design characteristic | Medium | Open |
| SEC-005 | Example Redis configuration uses plaintext transport and an empty password | Deployment hardening concern | Medium | Open |
| SEC-006 | Push notification data can pass through Chatwoot Hub | Confirmed third-party disclosure path | Medium | Open |
| SEC-007 | Public configuration and JavaScript serialization require hardening | Confirmed design concerns; exploitability unproven | Medium | Open |
| SEC-008 | Analytics transmits user and account identifying information to Amplitude | Confirmed data flow; privacy assessment pending | Medium | Open |

## 3. Detailed findings

### SEC-001 — Installation configuration secrets lack model-level encryption

- **Classification:** Confirmed design weakness.
- **Preliminary severity:** High.
- **Affected areas:** `app/models/installation_config.rb`, `lib/global_config.rb`, `lib/global_config_service.rb`, `lib/vapid_service.rb`.

**Evidence**

- `InstallationConfig` stores values in a JSONB `serialized_value` column.
- The inspected model does not declare Active Record encryption for that serialized value.
- Configuration loading and persistence do not apply a general secret-encryption layer.
- `GlobalConfig` caches configuration values in Redis using JSON serialization.
- `VapidService` stores a public and private VAPID key together in an InstallationConfig value.
- The private key is retrieved for WebPush signing.

**Impact**

Sensitive configuration values may be stored in the database and application-level Redis cache without application-level encryption. A database or Redis compromise could therefore expose credentials and private keys, subject to the access controls and any infrastructure-level encryption in place.

This does not establish that a production database or Redis instance has been compromised.

**Recommended remediation**

1. Inventory all configuration keys containing credentials, tokens, private keys or other sensitive values.
2. Introduce a dedicated encrypted secret-storage mechanism.
3. Separate secret values from ordinary configuration and public configuration.
4. Ensure cache entries containing secrets receive appropriate protection and expiry.
5. Define key rotation, backup recovery and migration procedures.
6. Avoid breaking compatibility with existing installations during migration.

**Outstanding verification**

- Inspect production deployment encryption and Redis controls.
- Inventory every secret-bearing configuration key and its consumers.
- Establish migration requirements for existing plaintext values.

### SEC-002 — Super Admin secret values are rendered into authenticated browser sessions

- **Classification:** Confirmed exposure to authenticated Super Admin sessions.
- **Preliminary severity:** Medium.
- **Affected areas:** `app/controllers/super_admin/app_configs_controller.rb`, `app/views/super_admin/app_configs/show.html.erb`, `app/controllers/super_admin/application_controller.rb`.

**Evidence**

- The Super Admin application controller enforces `authenticate_super_admin!`.
- The app configuration controller retrieves allowlisted configuration values.
- The view renders secret fields using password inputs populated with existing configuration values.
- A password input masks visual presentation but does not remove the value from the HTML document or browser DOM.

**Impact**

An authenticated Super Admin browser session receives existing secret values. Those values may be accessible through browser developer tools, page inspection, extensions or a compromised administrator session.

This is not evidence of unauthenticated public exposure.

**Recommended remediation**

1. Never populate secret inputs with existing secret values.
2. Display only whether a secret is configured.
3. Require an explicit replacement value to rotate a secret.
4. Preserve the existing value when a replacement is omitted.
5. Provide deliberate secret rotation and removal workflows.
6. Audit privileged secret access and changes.

**Outstanding verification**

- Inspect form submission behavior and determine whether existing values can be accidentally resubmitted or overwritten.
- Review all Super Admin secret fields and associated update flows.

### SEC-003 — Global configuration has no built-in secret redaction

- **Classification:** Confirmed design limitation.
- **Preliminary severity:** Medium.
- **Affected areas:** `lib/global_config.rb`, `lib/global_config_service.rb`, `app/models/installation_config.rb`.

**Evidence**

- `GlobalConfig.get` retrieves configuration values without a general secret-redaction policy.
- The generic configuration cache serializes retrieved values into Redis.
- Configuration metadata such as `type: secret` is not itself an encryption or redaction mechanism.
- The actual exposure depends on which callers retrieve a value and whether their responses or rendered pages are accessible.

**Impact**

A future or existing caller can unintentionally expose a sensitive configuration value if it uses generic configuration retrieval without an explicit public/private boundary.

**Recommended remediation**

1. Introduce explicit public, internal and secret configuration classifications.
2. Require secret access through dedicated interfaces.
3. Redact secret values in generic serializers and administrative responses.
4. Audit every endpoint, job and view that retrieves global configuration.
5. Prevent accidental serialization of secret-bearing configuration objects.

**Outstanding verification**

Complete a caller inventory and trace sensitive keys to their actual response and logging destinations.

### SEC-004 — Active Record encryption is optional and legacy plaintext is supported

- **Classification:** Confirmed design characteristic.
- **Preliminary severity:** Medium.
- **Affected areas:** `config/application.rb`, `app/models/installation_config.rb`, models declaring `encrypts`.

**Evidence**

- Encryption configuration is conditionally loaded based on environment variables.
- `Chatwoot.encryption_configured?` checks for all three Active Record encryption keys.
- Some model attributes declare encryption conditionally.
- The application enables `support_unencrypted_data` as a compatibility measure while legacy plaintext data remains.
- Other inspected model encryption declarations are unconditional.

**Impact**

The encryption posture depends on deployment configuration and on the particular model attribute. A deployment that omits encryption keys may not receive the intended protection for conditionally encrypted attributes.

**Recommended remediation**

1. Define mandatory encryption requirements for MarkChat deployments.
2. Validate encryption key configuration during startup.
3. Identify all conditionally encrypted attributes.
4. Plan migration of legacy plaintext values.
5. Define key backup, rotation and disaster-recovery procedures.
6. Test encrypted data migration and backward compatibility.

**Outstanding verification**

Test boot behavior with missing, partial and complete encryption key configuration. Confirm behavior for each affected model.

### SEC-005 — Example Redis configuration uses plaintext transport and an empty password

- **Classification:** Deployment hardening concern.
- **Preliminary severity:** Medium.
- **Affected areas:** Redis deployment examples and environment configuration.

**Evidence**

The inspected Redis example uses a `redis://` connection and an empty password.

**Impact**

If a production deployment copies this example without adapting it, Redis traffic may lack transport encryption and Redis may lack authentication. The repository example alone does not prove that any production instance is exposed.

**Recommended remediation**

1. Require authenticated Redis access.
2. Use TLS where Redis traffic crosses an untrusted network.
3. Restrict Redis network access to authorized application and worker services.
4. Avoid exposing Redis publicly.
5. Document secure production configuration and validate it during deployment.

**Outstanding verification**

Inspect the actual MarkChat deployment topology and production Redis configuration before assigning a production vulnerability status.

### SEC-006 — Push notification data can pass through Chatwoot Hub

- **Classification:** Confirmed third-party disclosure path.
- **Preliminary severity:** Medium.
- **Affected areas:** Push notification service and Chatwoot Hub integration.

**Evidence**

The inspected notification flow can relay device tokens and message previews through Chatwoot Hub.

**Impact**

Device identifiers and potentially sensitive message content may be disclosed to an external service as part of notification delivery.

The actual data disclosed, retention, access controls and applicable contractual terms require separate assessment.

**Recommended remediation**

1. Document the data flow and third-party recipient.
2. Minimize message content in push notification payloads.
3. Provide a configuration option to disable external relay.
4. Consider a MarkChat-controlled notification delivery architecture.
5. Document retention, access and data-processing arrangements.
6. Include this flow in privacy notices and the data-processing assessment.

**Outstanding verification**

Inspect the complete notification payload, recipient, transport, retention and configuration controls.

### SEC-007 — Public configuration and JavaScript serialization require hardening

- **Classification:** Confirmed design concerns; exploitability not demonstrated.
- **Preliminary severity:** Medium.
- **Affected areas:** `app/controllers/dashboard_controller.rb`, `app/views/layouts/vueapp.html.erb`, `app/services/request_device_info.rb`, profile session API and Vue session components.

**Evidence**

1. `DashboardController` inherits directly from `ActionController::Base` and has no authentication callback in the inspected controller.
2. Its public configuration allowlist is merged into `@global_config`.
3. The dashboard layout serializes configuration into browser-accessible JavaScript.
4. The public configuration includes values such as branding, public application identifiers, feature flags, the Amplitude project token and the VAPID public key.
5. `CHATWOOT_INBOX_HMAC_KEY` was not found in the inspected public dashboard allowlist or frontend global configuration map.
6. The user HMAC identifier is calculated server-side and may be returned through a user API response when the HMAC key is configured.
7. `vueapp.html.erb` interpolates `browser.name` into a JavaScript string.
8. The same template directly interpolates several configuration values into JavaScript string literals.
9. `RequestDeviceInfo` copies `X-Chatwoot-Client-Name` into session metadata without normalization.
10. The profile session API returns stored browser metadata.
11. The Active Sessions Vue component uses ordinary text interpolation for session labels; no HTML interpretation sink was identified in the inspected component.

**Impact**

Public configuration must be deliberately restricted to values intended for browser access. Direct interpolation into JavaScript string contexts creates an output-encoding concern. Untrusted session metadata also requires safe handling at every output sink.

The mobile header-to-session path has been confirmed, but stored XSS has not been demonstrated. The mobile header path is not proven to feed the separate `window.browserConfig` assignment.

**Recommended remediation**

1. Separate public browser configuration from internal and secret configuration.
2. Use context-appropriate JSON serialization and JavaScript escaping.
3. Avoid manual interpolation of untrusted or configurable values into JavaScript strings.
4. Normalize and validate client-supplied device metadata.
5. Preserve safe text rendering in Vue and avoid HTML interpretation of untrusted metadata.
6. Review all public dashboard configuration keys individually.
7. Review administrator-configurable dashboard scripts as a separate execution surface.

**Outstanding verification**

- Verify Rails 7.2.3.1 escaping behavior in the relevant template contexts.
- Inspect the exact Browser gem behavior for hostile User-Agent values.
- Inspect all session metadata display sinks.
- Establish the actual permissions and scope of the Contact Support inbox token.
- Verify the Amplitude project key's intended browser exposure and ingestion restrictions.
- Review `DASHBOARD_SCRIPTS` handling and sensitive-path restrictions.
- Run runtime tests when a suitable Ruby/Bundler environment is available.

No XSS vulnerability is confirmed by the current evidence.

### SEC-008 — Analytics transmits user and account identifying information to Amplitude

- **Classification:** Confirmed data flow; privacy assessment pending.
- **Preliminary severity:** Medium.
- **Affected areas:** `app/javascript/dashboard/helper/AnalyticsHelper`, `app/javascript/dashboard/store/utils/api.js`, `app/views/layouts/vueapp.html.erb`.

**Evidence**

- Analytics initialization is invoked by both dashboard application entry points inspected.
- The browser AnalyticsHelper initializes Amplitude when an analytics token is present.
- The helper explicitly disables SDK default tracking.
- On identity events, it sends user ID, email, name and avatar URL.
- It associates users with account groups and sends account identifiers and account names.
- Explicit event and page tracking remain available.
- The Amplitude token is supplied to browser JavaScript through dashboard configuration.

**Impact**

User and account identifying information is transmitted to a third-party analytics provider. This creates privacy, data minimization, retention, transparency and international data-transfer considerations.

This is a confirmed data flow, not proof of unlawful processing.

**Recommended remediation**

1. Disable third-party analytics by default for MarkChat unless explicitly approved.
2. Provide an administrator-controlled analytics policy.
3. Minimize or pseudonymize identity attributes.
4. Avoid sending email, avatar URLs and unnecessary account details.
5. Define consent, notice and retention requirements.
6. Assess third-party processing and international data transfers.
7. Evaluate self-hosted or tenant-controlled analytics options.

**Outstanding verification**

- Determine whether analytics is enabled by default in the relevant deployment.
- Inspect all event names and event properties sent to Amplitude.
- Review provider retention, access and processing terms.
- Complete a Kenya Data Protection Act and cross-border transfer assessment with appropriate legal advice.

## 4. Cross-cutting requirements for MarkChat

The following requirements apply beyond the individual findings:

1. Establish a central secret-management boundary.
2. Define public, tenant-private, platform-private and secret configuration classifications.
3. Enforce least privilege for platform administrators, tenant administrators and ordinary users.
4. Log privileged configuration and secret changes without logging secret values.
5. Establish encryption, key rotation, backup and recovery procedures.
6. Document all third-party data flows.
7. Maintain security regression tests for every remediated finding.
8. Require tenant isolation and authorization testing before production.
9. Establish secure defaults for new installations.
10. Maintain a release security checklist.

## 5. Audit limitations

- This register is based on inspected repository source and user-provided PowerShell evidence.
- No production environment or live deployment was assessed.
- Runtime Rails tests were not executed because Ruby, Bundler, Docker and WSL were unavailable in the inspected Windows environment.
- No exploitation was demonstrated for SEC-007.
- No legal determination was made for SEC-008.
- Severity ratings are preliminary and should be reassessed after threat modeling and deployment review.

## 6. Current closure criteria

The configuration and secrets audit can move to implementation planning when:

- Each finding has a sufficiently traced data flow and affected component.
- Remaining unknowns are explicitly recorded.
- MarkChat security requirements are approved.
- Remediation dependencies and acceptance tests are defined.
- The user explicitly approves the architecture and implementation phase.

**Current decision:** Discovery findings recorded; no source-code remediation authorized.
