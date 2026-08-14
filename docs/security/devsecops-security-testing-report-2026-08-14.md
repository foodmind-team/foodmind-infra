# FoodMind DevSecOps security testing report

**Assessment date:** 2026-08-14

**Environment:** GitHub repositories and AWS staging (`ap-southeast-1`)

**Scope:** source, dependencies, secrets, container images, delivery controls, public HTTP response policy, and baseline runtime configuration.

## Executive result

Existing application and container gates are healthy, and the initial unauthenticated DAST scan found no High-risk alert. The assessment identified nine delivery or runtime-control gaps. The public-header fixes were deployed through SSM and rescanned on 2026-08-14; the original missing-CSP and anti-clickjacking alerts are closed. Five existing default branches are protected, RDS now retains seven days of backups with deletion protection, and all five remediation pull requests passed CI. CloudWatch deployment and the two new gate-name protections remain open dependencies.

## Test evidence

| Test | Evidence | Result |
| --- | --- | --- |
| Recommendation quality, tests, contracts, dependency audit, licenses, Gitleaks, SBOM, Trivy, container hardening | [GitHub Actions run 31703078433](https://github.com/foodmind-team/foodmind-intelligence/actions/runs/31703078433) | Passed |
| Agent component gates including Cooking security tests | [GitHub Actions run 31791644188](https://github.com/foodmind-team/foodmind-intelligence/actions/runs/31791644188) | Passed |
| Staging Compose integration | [GitHub Actions run 31792208800](https://github.com/foodmind-team/foodmind-infra/actions/runs/31792208800) | Passed |
| Immutable image publication | [GitHub Actions run 31792354785](https://github.com/foodmind-team/foodmind-infra/actions/runs/31792354785) | Passed |
| Digest-pinned staging deployment through OIDC and SSM | [GitHub Actions run 31792666758](https://github.com/foodmind-team/foodmind-infra/actions/runs/31792666758) | Passed |
| ML format, lint, 12 tests, dependency consistency, `pip-audit`, licenses, Gitleaks | [GitHub Actions run 31796389723](https://github.com/foodmind-team/foodmind-ml/actions/runs/31796389723) | Passed |
| OWASP ZAP passive baseline | Immutable ZAP image; unauthenticated HTTPS target | 0 High, 2 Medium, 4 Low, 4 Informational |
| Post-fix OWASP ZAP passive baseline | Same immutable ZAP image and HTTPS target | Original two Medium alerts closed; raw result 0 High, 1 accepted Medium, 1 accepted Low, 9 Informational |

## Findings and remediation status

| ID | Severity | Finding | Remediation | Current evidence/status |
| --- | --- | --- | --- | --- |
| SEC-001 | Medium | Content Security Policy missing at the public entry point | Restrictive CSP added to Caddy and enforced by a header-check script | **Closed:** deployed by SSM command `f7b54efd-c41b-4d9b-a98f-3bcf217f5be6`; ZAP rule 10038 passes |
| SEC-002 | Medium | Anti-clickjacking protection missing | `frame-ancestors 'none'` and `X-Frame-Options: DENY` added | **Closed:** ZAP rule 10020 passes |
| SEC-003 | Low | Permissions Policy and cross-origin browser policy incomplete | Permissions Policy, COOP, and CORP added; COEP formally excepted because current cross-origin images/object storage are incompatible | Deployed; accepted COEP exception remains documented |
| SEC-004 | High process risk | All seven default branches accepted direct, unprotected changes | Exact required checks and one-reviewer policy applied to Backend, Web, Android, Infra, and Docs | Five protected; ML and Intelligence wait for new gates on their default branches |
| SEC-005 | High process risk | ML repository had no CI or locked dependency definition | Python package metadata, lockfile, format/lint/tests, `pip-audit`, license and Gitleaks gates added | **Closed in PR:** remote `ML gate` passed |
| SEC-006 | Medium process risk | Intelligence exposed two indistinguishable `merge-gate` contexts | Unique `Agent components gate` and `Recommendation Agent gate` names added | PR checks passed; default-branch merge/run pending |
| SEC-007 | Medium | RDS retained backups for one day and allowed deletion without protection | Seven-day retention, deletion protection, and snapshot retention on replacement/deletion added | Runtime shows seven-day retention and deletion protection; final-snapshot policy waits for template merge |
| SEC-008 | Medium | Container logs were host-local and no baseline EC2/RDS alarms existed | Optional retained CloudWatch log group, least-privilege writer policy, non-blocking Docker delivery, SNS, and four alarms added | Template validated in AWS; deployment waits only for the SNS alert mailbox |
| SEC-009 | Low supply-chain risk | Android and Docs workflows referenced third-party actions by mutable major tags | Every action reference in all seven repositories is pinned to a full commit SHA with a human-readable release comment | Remote Android and Docs workflows passed |
| SEC-010 | Medium accepted risk | CSP permits arbitrary HTTPS image origins for user-entered recipe and discovery images | Scripts remain self-only; broad inline styles are rejected; `unsafe-inline` is scoped to style attributes used by progress indicators | Accepted product trade-off; ZAP 10055 is explicitly documented and ignored by policy |

The Single-AZ RDS design remains an explicitly accepted demo limitation until Multi-AZ cost is approved. It must not be described as highly available.

## Initial DAST details

| Risk | Alerts |
| --- | ---: |
| High | 0 |
| Medium | 2 |
| Low | 4 |
| Informational | 4 |

The committed ZAP rules ignore only reviewed behavior. COEP is excepted because it would break current cross-origin image flows; an independent shell gate still verifies COOP and CORP. CSP wildcard rule 10055 is an accepted product trade-off for user-entered HTTPS images. The shell gate independently requires self-only scripts, self-only style elements, narrowly scoped inline style attributes, and rejects the broader `style-src 'self' 'unsafe-inline'` form.

## Post-fix DAST details

| Risk | Raw alert types | Disposition |
| --- | ---: | --- |
| High | 0 | None |
| Medium | 1 | Accepted CSP wildcard for arbitrary HTTPS recipe images |
| Low | 1 | Accepted COEP exception; COOP and CORP remain enforced |
| Informational | 9 | Reviewed scanner/static-client behavior |

The deployment/header gate passed against the real HTTPS endpoint. ZAP reports `PASS` for missing CSP, anti-clickjacking, HSTS, nosniff, Permissions Policy and all other baseline active policy rules. After the reviewed exceptions are applied, the automated baseline has no unreviewed failure or warning.

## Required final rescan

The report becomes final only after all of the following evidence exists:

1. All remediation pull requests are merged with successful required checks.
2. The staging environment is deployed from the tested Infra revision.
3. `Staging DAST / staging-dast` passes with 0 unaccepted High or Medium alerts; accepted exceptions remain named in `.zap/rules.tsv` and this report.
4. The live header gate passes against the staging HTTPS endpoint.
5. GitHub branch protection is shown blocking an unapproved or failing PR in each policy class.
6. If observability is approved, current CloudWatch streams, four non-`INSUFFICIENT_DATA` alarms, and a confirmed SNS test notification are captured.
7. RDS shows seven-day backup retention and deletion protection enabled after the CloudFormation update.

Record the final run URLs, alert counts, screenshots, and date below without including credentials, tokens, cookies, presigned URLs, personal data, or user-generated content.

## Final rescan record

- Deployment evidence: SSM command `f7b54efd-c41b-4d9b-a98f-3bcf217f5be6` succeeded for Infra revision `a06348356a26e9fc5cd6492a47624570dd684473`
- ZAP artifact: `docs/security/zap-rescan-2026-08-14.md` (immutable image digest recorded in the workflow)
- Post-fix raw ZAP counts: **0 High, 1 accepted Medium, 1 accepted Low, 9 Informational**
- Branch-protection evidence: Backend, Web, Android, Infra, and Docs enabled; ML and Intelligence pending their default-branch gate runs
- CloudWatch/RDS evidence: RDS is at seven-day retention with deletion protection; CloudWatch waits for the SNS mailbox and subscription confirmation
