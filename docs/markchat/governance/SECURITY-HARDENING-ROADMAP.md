# MarkChat — Security Hardening Roadmap

- **Project:** MarkChat
- **Upstream foundation:** Chatwoot Community Edition
- **Evidence baseline:** `f230f4ffb5`
- **Review date:** 2026-11-10
- **Status:** Proposed remediation roadmap; implementation not authorized.

## 1. Purpose

This roadmap translates the current security audit findings into a dependency-aware remediation plan for MarkChat.

It is a planning document. It does not authorize changes to the Chatwoot source code.

The roadmap distinguishes upstream weaknesses that require hardening from MarkChat-specific SaaS controls and deployment requirements.

## 2. Remediation principles

1. Preserve upstream functionality where it is safe and appropriate.
2. Avoid copying Enterprise implementation code.
3. Prefer modular MarkChat-specific services and interfaces over invasive upstream modifications.
4. Make security-sensitive configuration explicit and centrally governed.
5. Enforce least privilege and deny-by-default authorization.
6. Use secure defaults for new installations.
7. Treat tenant isolation as a system-wide invariant, not merely a controller concern.
8. Add regression tests before considering a security finding resolved.
9. Avoid storing, logging, serializing or transmitting secrets unnecessarily.
10. Document all external data flows and third-party dependencies.

## 3. Proposed remediation phases

### Phase 0 — Audit baseline and governance

**Related records:** LIC-001, SEC-001 through SEC-008.

**Objectives**

- Preserve the upstream commit and licensing baseline.
- Maintain the cumulative audit register.
- Maintain an architecture and hardening roadmap.
- Identify outstanding evidence and environmental limitations.
- Establish an approved security decision process.

**Acceptance criteria**

- Audit records have unique identifiers.
- Findings distinguish confirmed facts from hypotheses.
- Each finding has remediation and validation requirements.
- No source code is changed during discovery without explicit approval.

**Status:** Documentation in progress.

### Phase 1 — Secret management and encryption

**Related records:** SEC-001, SEC-003, SEC-004.

**Objectives**

- Classify all configuration values.
- Separate secrets from ordinary configuration.
- Define encrypted persistence and cache protection.
- Establish encryption key management and rotation.
- Migrate existing plaintext secrets safely.

**Work packages**

1. Inventory all secret-bearing configuration keys and their consumers.
2. Identify all models and services that persist credentials.
3. Design a dedicated secret-storage interface.
4. Define encryption-at-rest and cache protection requirements.
5. Define startup validation for required encryption keys.
6. Define backward-compatible migration and rollback procedures.
7. Define secret rotation and backup recovery.

**Dependencies**

- Complete configuration caller inventory.
- Approved secret classification model.
- Approved encryption and key-management design.

**Acceptance criteria**

- Sensitive values are encrypted at rest using the approved mechanism.
- Secrets are not returned by generic configuration serializers.
- Redis does not expose secret values through unprotected cache entries.
- Encryption configuration failures are detected before production operation.
- Existing values can be migrated without loss.
- Rotation and recovery tests pass.

### Phase 2 — Administrative secret handling and configuration boundaries

**Related records:** SEC-002, SEC-003, SEC-007.

**Objectives**

- Stop returning existing secrets to administrator browsers.
- Establish distinct public, tenant-private, platform-private and secret configuration boundaries.
- Restrict configuration access by role and purpose.

**Work packages**

1. Replace prefilled password inputs with configured/unconfigured indicators.
2. Implement explicit secret replacement and removal semantics.
3. Audit Super Admin configuration permissions.
4. Introduce safe configuration serialization.
5. Inventory public dashboard configuration keys.
6. Review administrator-configurable scripts and their execution context.
7. Ensure secret changes are audited without recording secret values.

**Dependencies**

- Approved configuration classification model.
- Secret-management design from Phase 1.
- Platform and tenant administration model.

**Acceptance criteria**

- Existing secret values never appear in HTML responses.
- Omitted replacement fields preserve existing secrets.
- Secret changes require authorized actions.
- Public configuration contains only intentionally public values.
- JavaScript values are serialized using context-safe mechanisms.
- Configuration changes produce auditable events.

### Phase 3 — Browser input and output hardening

**Related records:** SEC-007.

**Objectives**

- Validate untrusted browser and mobile metadata.
- Ensure all output sinks use context-appropriate encoding.
- Prevent untrusted metadata from being interpreted as HTML or executable JavaScript.

**Work packages**

1. Review User-Agent parsing and Browser gem normalization.
2. Validate and constrain mobile client headers.
3. Review profile-session API serialization.
4. Review Vue session metadata rendering.
5. Review every inline JavaScript interpolation in the dashboard layout.
6. Review public configuration and dashboard script injection surfaces.
7. Add hostile-input regression tests.

**Dependencies**

- Completion of the SEC-007 evidence investigation.
- Suitable runtime test environment.

**Acceptance criteria**

- Client-supplied metadata has defined validation rules and length limits.
- JavaScript values use safe serialization.
- Vue displays untrusted metadata as text.
- No unsafe HTML interpretation is introduced.
- Regression tests cover hostile User-Agent and mobile-header inputs.

### Phase 4 — Third-party data flow and privacy controls

**Related records:** SEC-006, SEC-008.

**Objectives**

- Minimize external disclosure.
- Give MarkChat operators control over optional third-party services.
- Establish a documented data-processing and retention model.

**Work packages**

1. Map push notification payloads and external recipients.
2. Review Chatwoot Hub dependency and alternatives.
3. Define push notification content minimization.
4. Define analytics defaults and configuration controls.
5. Review Amplitude identity and event payloads.
6. Assess self-hosted or tenant-controlled analytics.
7. Document data retention and deletion requirements.
8. Assess cross-border processing and applicable Kenyan privacy obligations.

**Dependencies**

- Complete third-party integration inventory.
- Product decisions on analytics and push notification delivery.
- Legal and privacy review.

**Acceptance criteria**

- Each third-party data flow has a documented purpose and data inventory.
- Optional analytics is disabled by default unless explicitly approved.
- Unnecessary personal data is not transmitted.
- Push notification payloads follow approved minimization rules.
- Privacy notices and contractual requirements are reviewed before launch.

### Phase 5 — Redis and infrastructure security

**Related records:** SEC-005, SEC-001.

**Objectives**

- Ensure deployment examples and production configuration follow secure defaults.
- Protect cache, queues and internal service communication.

**Work packages**

1. Define authenticated Redis configuration.
2. Define TLS requirements based on network topology.
3. Restrict Redis network access.
4. Review database and object-storage security.
5. Define secrets injection and environment management.
6. Define backup encryption and recovery.
7. Establish monitoring and security alerting.

**Dependencies**

- Approved hosting and deployment architecture.
- Secret-management design.
- Infrastructure threat model.

**Acceptance criteria**

- Redis is not publicly exposed.
- Authentication and network restrictions are validated.
- TLS is used where required by the approved deployment topology.
- Secrets are not embedded in source control or container images.
- Backup and recovery procedures are tested.

### Phase 6 — Tenant isolation and RBAC

**Related future audit area:** Tenant isolation and authorization.

**Objectives**

- Establish tenant boundaries across the complete application.
- Define platform-level and tenant-level administration.
- Prevent cross-tenant data access.

**Work packages**

1. Inventory account, user, inbox, conversation, contact and attachment ownership relationships.
2. Trace tenant scoping through controllers, models, policies, services, jobs and APIs.
3. Inspect storage and attachment authorization.
4. Inspect search, exports, reports, analytics and background jobs.
5. Define platform Super Admin, tenant Admin, branch Admin and agent roles.
6. Establish deny-by-default authorization.
7. Test cross-tenant access attempts systematically.

**Dependencies**

- Complete the current configuration and secrets documentation.
- Approved MarkChat tenancy and organizational model.

**Acceptance criteria**

- Every tenant-owned resource has enforceable ownership boundaries.
- Authorization is enforced server-side.
- Background jobs preserve tenant context.
- Cross-tenant access regression tests pass.
- Platform administration is separated from tenant administration.

### Phase 7 — SaaS billing and entitlement enforcement

**Related future audit area:** Commercial SaaS architecture.

**Objectives**

- Establish MarkChat's own subscription and entitlement system.
- Separate MarkChat billing from payments collected by MarkChat customers.

**Work packages**

1. Define plans, limits, entitlements and trial rules.
2. Define subscription lifecycle and grace periods.
3. Define payment provider abstraction.
4. Evaluate Paystack and other relevant payment methods.
5. Define webhook authentication and idempotency.
6. Enforce entitlements server-side.
7. Audit subscription changes and billing events.

**Dependencies**

- Approved tenancy model.
- Approved pricing and commercial policy.
- Payment provider and legal review.

**Acceptance criteria**

- Subscription state is maintained by the MarkChat backend.
- Entitlements cannot be bypassed through frontend changes.
- Webhooks are authenticated and idempotent.
- Billing events are auditable.
- Payment provider failures do not corrupt subscription state.

## 4. Proposed priority order

| Priority | Phase | Rationale |
|---|---|---|
| P0 | Phase 0 — Governance | Establishes evidence and decision control |
| P1 | Phase 1 — Secret management | Protects credentials and private keys |
| P1 | Phase 2 — Configuration boundaries | Prevents unnecessary secret exposure |
| P1 | Phase 3 — Browser input/output | Hardens untrusted data handling |
| P1 | Phase 6 — Tenant isolation and RBAC | Fundamental SaaS security boundary |
| P2 | Phase 4 — Third-party privacy | Controls external data disclosure |
| P2 | Phase 5 — Infrastructure security | Secures deployment and service boundaries |
| P2 | Phase 7 — Billing and entitlements | Establishes commercial enforcement |

This ordering is provisional. The detailed tenant-isolation audit may reveal risks that require reprioritization.

## 5. Mandatory verification workflow

Every remediation must follow:

1. **VERIFY** — inspect current implementation and establish a reproducible baseline.
2. **IMPLEMENT** — make only the explicitly approved change.
3. **TEST** — run targeted unit, integration, authorization and security tests.
4. **REGRESSION CHECK** — verify existing upstream functionality and affected workflows.
5. **REPORT** — record files changed, tests executed, results, residual risks and updated finding status.

No finding should be closed merely because code has been changed. Closure requires evidence that its acceptance criteria and regression tests pass.

## 6. Release security gates

Before commercial production release:

- Licensing and third-party notices are reviewed.
- Enterprise source and unauthorized Enterprise implementation code are excluded.
- Secrets are protected at rest and in transit as required.
- Public configuration is reviewed and minimized.
- Platform and tenant permissions are tested.
- Cross-tenant isolation tests pass.
- External data flows are documented.
- Privacy and data-processing obligations are reviewed.
- Backups, monitoring and incident response are operational.
- Subscription and entitlement enforcement is tested.
- Security regression tests pass against the release candidate.

## 7. Current authorization boundary

This roadmap records proposed work only.

**No application source-code modifications, dependency changes, migrations, infrastructure changes, commits or pushes are authorized by this document.**

Implementation requires explicit user approval after the relevant discovery and architecture decisions are complete.
