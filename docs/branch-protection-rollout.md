# Default-branch protection rollout

As of 2026-08-14, all seven FoodMind repositories have no classic branch protection and no repository ruleset. Apply protection only after the named check has completed successfully on the default branch; requiring a context that has never reported can lock every pull request.

| Repository | Default branch | Required status check |
| --- | --- | --- |
| `foodmind-backend` | `master` | `verify` |
| `foodmind-web` | `master` | `validate` |
| `foodmind-android` | `master` | `verify` |
| `foodmind-infra` | `master` | `compose-gate` |
| `foodmind-intelligence` | `main` | `Agent components gate`, `Recommendation Agent gate` |
| `foodmind-ml` | `main` | `ML gate` |
| `foodmind-docs` | `main` | `parity` |

`browser-e2e` and `Staging DAST / staging-dast` are not pull-request checks, so they must not be required merge contexts. Browser E2E remains post-merge evidence and staging DAST remains a post-deployment gate.

## Policy to apply

- Require a pull request before merging.
- Require one approving review and dismiss stale approvals.
- Require approval of the most recent push by someone other than its author.
- Require all review conversations to be resolved.
- Require the named status checks and require the branch to be up to date.
- Enforce the policy for repository administrators.
- Block force pushes and branch deletion.

Do not enable signed-commit or linear-history requirements until every contributor's signing and merge workflow has been tested. Those controls are valuable but can interrupt the current course workflow if enabled without preparation.

## Safe order

1. Merge the ML and Intelligence gate-name changes.
2. Confirm the exact check names from successful default-branch runs.
3. Apply protection one repository at a time.
4. Open a harmless draft pull request or use an existing PR to confirm the merge button is blocked when a required check fails or an approval is absent.
5. Record a screenshot of the rule and blocked/allowed PR state for presentation evidence.

Rollback is a deliberate repository-admin operation: restore the previous protection JSON or remove only the newly added required context. Do not disable all review requirements to recover from one misspelled check name.
