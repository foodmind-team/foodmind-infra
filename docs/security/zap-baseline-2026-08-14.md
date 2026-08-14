# Staging OWASP ZAP baseline — 2026-08-14

## Scope and method

- Target: FoodMind staging public HTTPS entry point (`https://13.229.2.154.sslip.io`).
- Tool: OWASP ZAP baseline scan using the immutable multi-architecture image digest recorded in `.github/workflows/security-dast.yml`.
- Test type: unauthenticated passive crawl; no destructive active attacks were enabled.
- Raw HTML, JSON, and Markdown reports were retained as local assessment evidence and are intentionally not committed because they contain the live endpoint and response details.

## Initial scan

| Risk | Alerts |
| --- | ---: |
| High | 0 |
| Medium | 2 |
| Low | 4 |
| Informational | 4 |

The two medium findings were a missing Content Security Policy and missing anti-clickjacking protection. The low findings covered missing Permissions Policy and cross-origin isolation headers.

## Remediation applied in source

- Added a restrictive CSP with `frame-ancestors 'none'` and no object embedding.
- Added `X-Frame-Options: DENY`, `Permissions-Policy`, COOP, and CORP.
- Added an executable header policy check to both deployment verification and the DAST workflow.
- Added a post-deployment ZAP baseline workflow. New, unreviewed ZAP alerts fail the job.

COEP is not enabled because the current client intentionally displays cross-origin HTTPS images and uses cross-origin object storage. Enforcing COEP without coordinated resource headers would break those product flows. ZAP rule `90004` is therefore reviewed and ignored, while the separate header check continues to enforce COOP and CORP so their regression cannot be hidden by that exception.

## Rescan status

Source remediation is complete. A production-like rescan remains pending until this revision is merged and deployed to staging. The successful `Staging DAST / staging-dast` run and its uploaded ZAP artifact are the acceptance evidence; this document must then be updated with the run URL and post-fix counts.
