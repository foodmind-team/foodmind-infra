# FoodMind DevSecOps security testing report

**Assessment date:** 2026-08-14  
**Environment:** GitHub repositories and AWS staging (`ap-southeast-1`)  
**Scope:** source, dependencies, secrets, container images, delivery controls, public HTTP response policy, and baseline runtime configuration.

## Executive result

Existing application and container gates are healthy, and the initial unauthenticated DAST scan found no High-risk alert. The assessment identified nine delivery or runtime-control gaps. Source remediations have been prepared for all non-Multi-AZ gaps, but several are not operational until their pull requests are merged and the AWS/GitHub changes are deployed. This report therefore remains **pre-rescan / not final**.

## Test evidence

| Test | Evidence | Result |
| --- | --- | --- |
| Recommendation quality, tests, contracts, dependency audit, licenses, Gitleaks, SBOM, Trivy, container hardening | [GitHub Actions run 31703078433](https://github.com/foodmind-team/foodmind-intelligence/actions/runs/31703078433) | Passed |
| Agent component gates including Cooking security tests | [GitHub Actions run 31791644188](https://github.com/foodmind-team/foodmind-intelligence/actions/runs/31791644188) | Passed |
| Staging Compose integration | [GitHub Actions run 31792208800](https://github.com/foodmind-team/foodmind-infra/actions/runs/31792208800) | Passed |
| Immutable image publication | [GitHub Actions run 31792354785](https://github.com/foodmind-team/foodmind-infra/actions/runs/31792354785) | Passed |
| Digest-pinned staging deployment through OIDC and SSM | [GitHub Actions run 31792666758](https://github.com/foodmind-team/foodmind-infra/actions/runs/31792666758) | Passed |
| ML format, lint, 12 tests, dependency consistency, `pip-audit`, licenses, Gitleaks | Local isolated worktree, locked Python 3.13 environment | Passed; remote CI run pending |
| OWASP ZAP passive baseline | Immutable ZAP image; unauthenticated HTTPS target | 0 High, 2 Medium, 4 Low, 4 Informational |

## Findings and remediation status

| ID | Severity | Finding | Remediation | Current evidence/status |
| --- | --- | --- | --- | --- |
| SEC-001 | Medium | Content Security Policy missing at the public entry point | Restrictive CSP added to Caddy and enforced by a header-check script | Source fixed; staging rescan pending |
| SEC-002 | Medium | Anti-clickjacking protection missing | `frame-ancestors 'none'` and `X-Frame-Options: DENY` added | Source fixed; staging rescan pending |
| SEC-003 | Low | Permissions Policy and cross-origin browser policy incomplete | Permissions Policy, COOP, and CORP added; COEP formally excepted because current cross-origin images/object storage are incompatible | Source fixed; staging rescan pending |
| SEC-004 | High process risk | All seven default branches accept direct, unprotected changes | Exact required checks and one-reviewer rollout policy documented | Remote repository rules pending |
| SEC-005 | High process risk | ML repository had no CI or locked dependency definition | Python package metadata, lockfile, format/lint/tests, `pip-audit`, license and Gitleaks gates added | Local rescan passed; remote CI pending |
| SEC-006 | Medium process risk | Intelligence exposed two indistinguishable `merge-gate` contexts | Unique `Agent components gate` and `Recommendation Agent gate` names added | Source fixed; default-branch runs pending |
| SEC-007 | Medium | RDS retained backups for one day and allowed deletion without protection | Seven-day retention, deletion protection, and snapshot retention on replacement/deletion added | Template validated; CloudFormation update pending |
| SEC-008 | Medium | Container logs were host-local and no baseline EC2/RDS alarms existed | Optional retained CloudWatch log group, least-privilege writer policy, non-blocking Docker delivery, SNS, and four alarms added | Templates validated; cost-bearing deployment pending |
| SEC-009 | Low supply-chain risk | Android and Docs workflows referenced third-party actions by mutable major tags | Every action reference in all seven repositories is pinned to a full commit SHA with a human-readable release comment | Source fixed; remote workflow runs pending |

The Single-AZ RDS design remains an explicitly accepted demo limitation until Multi-AZ cost is approved. It must not be described as highly available.

## Initial DAST details

| Risk | Alerts |
| --- | ---: |
| High | 0 |
| Medium | 2 |
| Low | 4 |
| Informational | 4 |

The committed ZAP rules ignore only reviewed behavior. The combined COEP/COOP/CORP rule is ignored because COEP would break current product flows; an independent shell gate still verifies COOP and CORP so their regression cannot be hidden by that exception. Medium alerts are not ignored.

## Required final rescan

The report becomes final only after all of the following evidence exists:

1. All remediation pull requests are merged with successful required checks.
2. The staging environment is deployed from the tested Infra revision.
3. `Staging DAST / staging-dast` passes and its ZAP artifact reports 0 High and 0 Medium alerts.
4. The live header gate passes against the staging HTTPS endpoint.
5. GitHub branch protection is shown blocking an unapproved or failing PR in each policy class.
6. If observability is approved, current CloudWatch streams, four non-`INSUFFICIENT_DATA` alarms, and a confirmed SNS test notification are captured.
7. RDS shows seven-day backup retention and deletion protection enabled after the CloudFormation update.

Record the final run URLs, alert counts, screenshots, and date below without including credentials, tokens, cookies, presigned URLs, personal data, or user-generated content.

## Final rescan record

- Deployment run: **pending**
- ZAP run and artifact: **pending**
- Post-fix ZAP counts: **pending**
- Branch-protection evidence: **pending**
- CloudWatch/RDS evidence: **pending approval and deployment**
