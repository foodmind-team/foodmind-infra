# FoodMind AWS Demo Deployment

- Status: Implemented demo runbook
- Owner: Deployment owner
- Last updated: 2026-08-13
- Related repositories: `foodmind-infra`, `foodmind-backend`, `foodmind-web`, `foodmind-intelligence`, `foodmind-ml`

## Scope

This runbook deploys an internet-accessible FoodMind demonstration environment
to one EC2 instance while using private RDS PostgreSQL and optional private S3
media storage. It is not the production ECS architecture and must not be used
for regulated, sensitive, or high-availability workloads.

The public path is:

```text
Route 53 -> Elastic IP -> EC2 :80/:443 -> Caddy
                                      |-> Web :8080
                                      `-> Backend :8080 (/api/v1 only)

Backend -> private RDS PostgreSQL
Backend -> private S3 bucket through the AWS SDK default credential chain
Backend -> private Docker network -> Chatbot / Cooking / Recommendation / Inference
```

No Backend, database, MinIO, Agent, or Inference port is published by
`compose.aws-demo.yaml`.

## Known demo-only boundaries

- Backend retains the `docker` Spring profile because the repository's
  documented production profile contract is not aligned with the implemented
  `application-prod.properties` contract.
- Recommendation and Inference retain `local` environment labels. The checked-in
  model manifest is approved only for local use, and Recommendation production
  mode requires a private HTTPS Inference origin.
- The manual bootstrap path builds the model package from the pinned ML
  submodule. Continuous delivery instead consumes a reviewed immutable ECR
  digest; see `staging-continuous-delivery.md`.
- Cooking task execution is single-instance and uses container-local state for
  in-flight tasks. Restarting the container may lose an unfinished task.
- The manual bootstrap path builds images on EC2. The continuous-delivery path
  pulls immutable images but still cannot provide zero-downtime deployment on a
  single EC2 instance.
- RDS automated backups are retained for seven days and deletion protection is
  enabled. The demo remains Single-AZ, so it does not provide an automatic
  standby failover or a production availability commitment.

These boundaries must remain visible in demo evidence. They are not production
approvals.

## Required AWS resources

Use one Region for EC2, RDS, S3, and Route 53 integration. For a Singapore-based
demo, `ap-southeast-1` is the default in `.env.aws.example`.

### Network and security groups

Create an EC2 security group:

| Direction | Protocol/port | Source/destination |
| --- | --- | --- |
| Inbound | TCP 80 | `0.0.0.0/0`, and `::/0` only when IPv6 is configured |
| Inbound | TCP 443 | `0.0.0.0/0`, and `::/0` only when IPv6 is configured |
| Inbound | TCP 22 | No rule; use Systems Manager Session Manager |
| Outbound | HTTPS 443 | AWS APIs, image/package registries, and optional DeepSeek |
| Outbound | PostgreSQL 5432 | RDS security group |

Create an RDS security group with inbound TCP 5432 from the EC2 security group
only. RDS must not be publicly accessible. The checked-in stack retains
automated backups for seven days, enables deletion protection, and creates a
final snapshot if CloudFormation replaces or removes the database resource.

### EC2

- Use an instance with at least 8 GiB RAM; image builds and Cooking are the peak
  consumers. Increase capacity if builds or UAT show memory pressure.
- Use an encrypted gp3 EBS volume with enough space for Docker images and logs.
- Allocate an Elastic IP and point the FoodMind Route 53 record to it.
- Attach an IAM instance profile containing `AmazonSSMManagedInstanceCore` plus
  the narrow S3 permissions below.
- Require IMDSv2. Because the Backend AWS SDK runs inside Docker, set the metadata
  response hop limit to `2`; a hop limit of `1` can prevent containers from
  receiving IMDS responses.
- Enable detailed monitoring or install the CloudWatch agent for memory and disk
  alarms. Standard EC2 metrics alone do not include filesystem utilisation.

Install Git, Docker Engine, the Docker Compose plugin, AWS CLI v2, and curl using
their official repositories. Do not expose the Docker daemon over TCP.

### RDS PostgreSQL

Create a private RDS PostgreSQL instance and an application database/user. Put
the endpoint, port, database, user, and generated password in the deployment
secret. `DB_SSL_MODE=require` encrypts the demo connection. A production design
must install the RDS CA bundle and move to certificate-verifying TLS.

Flyway runs during Backend startup. Take an RDS snapshot before deploying a
release containing new migrations. Never use Flyway clean against this database.
Deleting the demo stack requires an explicit, reviewed step to disable RDS
deletion protection first; preserve the final snapshot until its retention owner
approves removal.

### S3 media

Keep S3 Block Public Access enabled. The EC2 role needs only these object actions
for the configured prefix:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::REPLACE_BUCKET/media/*"
    }
  ]
}
```

Configure bucket CORS for direct browser uploads, replacing the origin:

```json
[
  {
    "AllowedOrigins": ["https://foodmind.example.com"],
    "AllowedMethods": ["PUT"],
    "AllowedHeaders": ["Content-Type", "x-amz-checksum-sha256"],
    "ExposeHeaders": ["ETag", "x-amz-checksum-sha256"],
    "MaxAgeSeconds": 300
  }
]
```

Create an S3 gateway VPC endpoint when the network topology supports it. Do not
place AWS access keys in `.env.aws`; the Backend uses the EC2 role through the
AWS SDK default credential chain.

Set `MEDIA_ENABLED=true` and `MEDIA_S3_BUCKET` to the stack output only after the
IAM and CORS change set has been reviewed. The bucket is private, retained on
stack deletion/replacement, and direct uploads accept only the deployed sslip.io
origin. Complete the upload/finalise and private-read acceptance test immediately
after deployment; disable media again if it fails.

## Secrets

Store one JSON secret in AWS Secrets Manager with values matching the sensitive
keys in `.env.aws.example`. Grant `secretsmanager:GetSecretValue` only to the EC2
deployment role and the specific secret ARN.

Create a separate `foodmind/staging/onemap` JSON secret containing only `email`
and `password`. Pass its exact ARN to the stack parameter and
`ONEMAP_CREDENTIALS_SECRET_ARN`; do not store the 72-hour access token. When
`ONEMAP_ROUTES_ENABLED=true`, the Backend caches the token, refreshes it before
expiry, and retries one unauthorised route request. AWS runtime validation rejects
`ONEMAP_API_TOKEN`; that variable is retained only for local compatibility.

On the instance, render `/opt/foodmind/foodmind-infra/.env.aws` without printing
values to the terminal or logs, then run:

```bash
chmod 600 /opt/foodmind/foodmind-infra/.env.aws
```

Use independent generated values for the database password, JWT secret, and
every service token. Do not reuse local defaults. The environment checker rejects
placeholders, weak lengths, permissive file modes, and incomplete optional
configuration.

## Source checkout

Use read-only GitHub deploy keys for the private repositories:

```bash
sudo install -d -o ubuntu -g ubuntu /opt/foodmind
cd /opt/foodmind
git clone --recurse-submodules git@github.com:foodmind-team/foodmind-infra.git
git clone git@github.com:foodmind-team/foodmind-web.git
```

The Infra commit pins Backend, Intelligence, ML, and Docs. Record the separate
Web commit in release evidence. Do not deploy arbitrary working-tree changes.

## DNS and first deployment

Before starting Caddy:

1. Associate the Elastic IP with EC2.
2. Create the Route 53 A record for `FOODMIND_DOMAIN`.
3. Confirm public DNS resolves to that Elastic IP.
4. Confirm inbound TCP 80 and 443 are allowed.
5. Confirm no other process owns ports 80 or 443.

Then deploy:

```bash
cd /opt/foodmind/foodmind-infra
cp .env.aws.example .env.aws
chmod 600 .env.aws
# Populate .env.aws from Secrets Manager and non-secret deployment values.
./scripts/deploy-aws-demo.sh .env.aws
```

The script initialises pinned submodules, validates the environment, renders the
Compose model, builds images, validates Caddy, waits for health checks, and runs
private plus public readiness checks.

If DNS is intentionally not live during a private dry run:

```bash
SKIP_PUBLIC_CHECK=true ./scripts/verify-aws-demo.sh .env.aws
```

This skips only the public HTTPS check; it is not acceptable as final release
evidence.

## Acceptance checks

Capture redacted results for:

```bash
docker compose --env-file .env.aws -f compose.aws-demo.yaml ps
./scripts/verify-aws-demo.sh .env.aws
```

Then complete user-visible UAT:

1. Register, login, refresh, logout, and login again over HTTPS.
2. Create and update food/drink records.
3. Exercise group visibility with an authorised and unauthorised user.
4. Generate Recommendation, Cooking, and Chatbot responses.
5. When media is enabled, upload a supported image and finalise it; verify a
   disallowed origin and foreign owner cannot access it.
6. Grant browser location permission on a controlled place and verify the OneMap
   attribution, walking-route summary, and route polyline.
7. Restart the EC2 instance and confirm Caddy and long-running services recover.
8. Confirm RDS automated backup status and perform a documented restore drill to
   a separate database before claiming recoverability.

Never include cookies, bearer tokens, presigned URLs, object keys, database
credentials, DeepSeek keys, or user content in evidence.

## Operations

For automated digest-based releases, follow
[`staging-continuous-delivery.md`](staging-continuous-delivery.md). The commands
below describe the manual source-build fallback and must not be mixed into an
active automated deployment.

View status and bounded logs:

```bash
docker compose --env-file .env.aws -f compose.aws-demo.yaml ps
docker compose --env-file .env.aws -f compose.aws-demo.yaml logs --tail=200 backend recommendation inference
```

Redeploy the pinned release:

```bash
git pull --ff-only
git submodule update --init --recursive
./scripts/deploy-aws-demo.sh .env.aws
```

Before a database migration, create and verify an RDS snapshot. To roll back
application code, return Infra and Web to the recorded commits and redeploy.
Database rollback is a separate, explicitly reviewed operation; do not delete or
replace the current RDS instance automatically.

Stopping application containers does not delete Caddy certificate or model
volumes:

```bash
docker compose --env-file .env.aws -f compose.aws-demo.yaml down
```

Do not add `--volumes` unless the exact deletion scope has been reviewed and the
data is confirmed disposable.

## Production migration

Before real production traffic, retain immutable ECR images but replace this
topology with ALB/ACM, ECS services, Service Connect TLS, private RDS Multi-AZ,
S3, Secrets Manager injection, CloudWatch alarms, an immutable model registry,
durable Cooking task state, IaC, staged rollout, and tested rollback. Remove
every demo-only environment exception rather than relabelling the EC2 stack as
production.
