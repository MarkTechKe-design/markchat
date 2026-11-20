# LIC-001 — Upstream Commercial Licensing Boundary

- **Record ID:** LIC-001
- **Category:** Licensing and intellectual property
- **Project:** MarkChat
- **Upstream project:** Chatwoot
- **Status:** Approved working engineering direction; formal legal review pending
- **Evidence baseline:** Chatwoot upstream commit `f230f4ffb5`
- **Last reviewed:** 2026-11-10

## 1. Decision

MarkChat will use the MIT-licensed Chatwoot Community Edition (CE) codebase as its initial technical foundation.

MarkChat may be developed and commercialized using code covered by the applicable MIT licence, provided the project preserves required copyright and permission notices and complies with all applicable third-party licences.

MarkChat will not incorporate Chatwoot Enterprise source code or Enterprise-only implementation code unless the appropriate commercial licensing permission has been obtained.

## 2. Verified upstream licensing boundaries

### 2.1 Community Edition

The upstream root `LICENSE` identifies the MIT licence as applicable outside the Enterprise directory and other expressly excluded components.

The MIT licence permits commercial use, modification, distribution, sublicensing and sale, subject to its conditions, including preservation of the copyright and permission notice.

### 2.2 Enterprise Edition

The upstream `enterprise/LICENSE` establishes separate commercial licensing conditions for Enterprise software.

The Enterprise licence requires an applicable Chatwoot agreement and valid Enterprise subscription for production use. It also restricts copying, modifying, distributing, sublicensing and commercial exploitation of Enterprise software without the required permission.

The Enterprise directory contains substantive functionality and extension mechanisms. It must not be treated as an ordinary MIT-licensed extension of the Community Edition.

### 2.3 Official Community Edition packaging

The upstream FOSS Docker publishing workflow removes:

- `enterprise/`
- `spec/enterprise/`

It then builds the Community Edition image with `CW_EDITION="ce"`.

This is the packaging approach MarkChat should use as a reference when validating its own CE-derived distribution.

## 3. MarkChat engineering requirements

1. Use only appropriately licensed Community Edition code as the upstream foundation.
2. Exclude Enterprise source and Enterprise-only implementation code from MarkChat's distributable product.
3. Do not copy Enterprise implementation code into new MarkChat modules.
4. Preserve upstream MIT copyright and permission notices.
5. Maintain an inventory of third-party dependencies, assets and licences.
6. Verify that the production build and distribution do not contain excluded Enterprise material.
7. Keep MarkChat-specific SaaS functionality independently implemented and documented.
8. Reassess licensing before introducing any additional upstream components or externally sourced code.

## 4. Initial product scope implications

The initial MarkChat product direction is text-focused customer communications and support.

Voice calling and other Enterprise-only capabilities are excluded from the initial scope unless independently implemented using appropriately licensed components or separately authorized.

This is a product-scope decision, not a statement that every such capability is necessarily Enterprise-only under every Chatwoot release.

## 5. Required future verification

The following work remains outstanding:

- [ ] Complete third-party dependency and asset licence inventory.
- [ ] Verify the exact Community Edition build and packaging process.
- [ ] Confirm Enterprise directories and implementation code are excluded from distributable artifacts.
- [ ] Review all newly introduced dependencies and copied code for licence compatibility.
- [ ] Obtain formal legal review before commercial distribution.
- [ ] Reassess licensing if the product scope or upstream licensing changes.

## 6. Acceptance criteria

LIC-001 can be marked fully verified for engineering release purposes when:

- The applicable upstream MIT notices are preserved.
- Enterprise source and Enterprise-only implementation code are excluded.
- Third-party licence obligations have been inventoried and reviewed.
- The release pipeline produces and verifies the intended Community Edition-derived distribution.
- Formal legal review has addressed the intended commercial distribution model.

## 7. Evidence references

Repository evidence reviewed:

- `LICENSE`
- `enterprise/LICENSE`
- `.github/workflows/publish_foss_docker.yml`
- `.github/workflows/publish_ee_docker.yml`
- `.github/workflows/run_foss_spec.yml`
- `.github/workflows/size-limit.yml`
- `config/application.rb`
- Enterprise extension and loading mechanisms

## 8. Important qualification

This record documents the engineering and product direction based on the repository evidence reviewed. It is not a legal opinion, legal clearance, or confirmation that every dependency and asset is commercially compatible.

Formal legal review remains necessary before commercial release.
