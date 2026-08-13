# FoodMind Staging Continuous Delivery

- Status: Ready for infrastructure provisioning and CI handoff
- Owner: Deployment owner
- Last updated: 2026-08-13
- Target: Existing single-EC2 staging environment in `ap-southeast-1`

## Delivery contract

CD never builds application images on EC2. CI publishes the seven images below
to the matching private ECR repositories and passes their resolved digests to a
release pull request:

| Component | ECR repository |
| --- | --- |
| Model package | `foodmind/model-package` |
| Inference | `foodmind/inference` |
| Recommendation | `foodmind/recommendation` |
| Cooking | `foodmind/cooking` |
| Chatbot | `foodmind/chatbot` |
| Backend | `foodmind/backend` |
| Web | `foodmind/web` |

The reviewed input is `releases/staging-source.json`. It pins the Web revision
and declares whether the release contains database migrations; Infra pins ML,
Intelligence, and Backend through submodules. After Compose integration passes,
`Publish staging images` builds and pushes all seven images and queries ECR for
their real digests. It uploads the generated `release-manifest.json` as a
30-day workflow artifact instead of committing generated data back to the
repository. `releases/staging.example.json` documents that artifact schema.

Every deployed image uses the full account registry, repository, and immutable
`@sha256:...` digest. The manifest records the exact Infra, ML, Intelligence,
Backend, and Web source revisions. Mutable tags such as `latest` are rejected,
and each workflow attempt receives a unique release ID and immutable build tag.

CI remains responsible for:

1. Building and testing each image from the recorded source revision.
2. Pushing each image once to its matching ECR repository.
3. Resolving the pushed manifest digest from ECR rather than calculating a
   local image ID.
4. Opening or updating a release pull request that changes only the intended
   source pins and `releases/staging-source.json`.

CD remains responsible for validating the manifest, creating a pre-migration
snapshot when requested, pulling the exact digests, deploying, verifying health,
and rolling back application images on failure.

## Promotion flow

1. Review and merge a release pull request to `master`.
2. `Compose integration` validates policy, scans tracked files for common
   credentials, renders both Compose profiles, and runs the offline stack smoke
   test for that exact Infra commit.
3. `Publish staging images` starts only after the successful `master` push run.
   It assumes the publisher role through OIDC, checks out the pinned Web and
   submodule revisions, pushes seven unique image tags, resolves their ECR
   digests, and uploads the release manifest artifact.
4. `Deploy staging` starts only after publication succeeds. It downloads that
   run's manifest, validates every digest and source SHA, and assumes the
   separate deployment role through OIDC.
5. Systems Manager creates an immutable Git worktree for the tested Infra SHA on
   EC2 and runs `scripts/cd/deploy-staging.sh`.
6. The deploy script serialises deployments, pulls the seven digests, starts the
   Compose project without building, and runs private plus public readiness
   checks.
7. A failed start or readiness check restores the previously captured image set.

## One-time AWS setup

Deploy `cloudformation.github-actions-cd.yaml` in the same account and Region as
the existing EC2 instance. This creates the seven immutable ECR repositories,
the GitHub OIDC provider when needed, a staging deployment role, and an ECR pull
policy on the existing EC2 role.

```bash
aws cloudformation deploy \
  --stack-name foodmind-staging-cd \
  --template-file cloudformation.github-actions-cd.yaml \
  --region ap-southeast-1 \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    InstanceId=i-0c0dc30e61a854e98 \
    InstanceRoleName=foodmind-demo-ec2-role \
    DatabaseInstanceIdentifier=foodmind-demo-db \
    GitHubOrganization=foodmind-team \
    GitHubRepository=foodmind-infra \
    EnvironmentName=staging
```

If the account gains a shared GitHub OIDC provider before this stack is created,
pass its ARN through `ExistingGitHubOidcProviderArn` to avoid creating a
duplicate provider.

The stack intentionally separates publication and deployment. The publisher
role can push and resolve images only in the seven FoodMind repositories. The
deployment role has no ECR push, secrets, S3, or database-data permission; it
can send a command only to the configured EC2 instance, read that result, and
create/inspect the configured RDS safety snapshot. The EC2 role can pull only
the seven FoodMind repositories.

## GitHub staging environment

Create a protected GitHub environment named `staging`. Restrict deployments to
`master`; add required reviewers if staging changes need a human promotion gate.
Store these non-secret environment variables:

| Variable | Value/source |
| --- | --- |
| `AWS_ACCOUNT_ID` | `076648863731` |
| `AWS_REGION` | `ap-southeast-1` |
| `AWS_INSTANCE_ID` | `i-0c0dc30e61a854e98` |
| `AWS_DB_INSTANCE_ID` | `foodmind-demo-db` |
| `AWS_PUBLISH_ROLE_ARN` | `PublishRoleArn` CloudFormation output |
| `AWS_DEPLOY_ROLE_ARN` | `DeployRoleArn` CloudFormation output |

No long-lived AWS credential belongs in repository secrets or environment
secrets. Application credentials remain in the mode-`600` EC2 file
`/opt/foodmind/foodmind-infra/.env.aws`; the workflow does not read or print it.

## Migration and rollback rules

Set `database_migrations` to `true` only when the release contains a schema
migration. CD waits for a new RDS snapshot to become available before touching
containers. A snapshot protects recovery but does not make a breaking migration
backward-compatible; expand/contract migrations are still required.

On the first digest-based deployment, the script captures the image references
currently running on EC2. On later deployments it keeps the last successful
manifest. Container rollback is automatic, but database rollback is never
automatic. A failed rollback or a database restore requires operator review.

Because this environment has one EC2 instance, a deployment that recreates
Backend or Web can cause a short staging interruption. The deployment lock
prevents two releases from changing the host concurrently, but this topology is
not zero-downtime or highly available.

## Operator checks

After provisioning, confirm the instance is online in Systems Manager and run a
manual deployment only after a real digest manifest has been reviewed. On EC2,
the successful state is stored under `/opt/foodmind/cd-state` with mode-restricted
manifest and environment files.

Useful read-only checks:

```bash
docker compose \
  --env-file /opt/foodmind/foodmind-infra/.env.aws \
  --env-file /opt/foodmind/cd-state/release.env \
  -f /opt/foodmind/cd-runtime/REPLACE_INFRA_SHA/compose.aws-demo.yaml ps

jq '{release_id, source_revisions}' /opt/foodmind/cd-state/current-manifest.json
```

Do not print the application environment file, run `docker compose down
--volumes`, or restore RDS as part of a routine application rollback.
