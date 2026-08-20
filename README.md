# FoodMind Infrastructure

FoodMind Infrastructure is the integration and release authority for FoodMind. It pins the Backend, Intelligence, ML, and Docs repositories as submodules and starts the complete local backend stack with Docker Compose. Web remains a separate repository and is run independently against the Backend.

An isolated single-EC2 AWS demonstration topology is available through
`compose.aws-demo.yaml`. It adds the sibling Web checkout and Caddy, uses
private RDS PostgreSQL and optional S3 instead of the local PostgreSQL/MinIO
services, and publishes only ports 80/443. It is intentionally not the
production ECS architecture. See [AWS demo deployment](docs/aws-demo-deployment.md).

## Live deployment

The current AWS demonstration environment is available at [https://13.229.2.154.sslip.io/](https://13.229.2.154.sslip.io/). Caddy terminates HTTPS, serves the Web client at `/`, and routes `/api/v1` to the Backend; private runtime services and the database are not publicly exposed.

## What starts locally

| Service | Host address | Role |
| --- | --- | --- |
| Backend | http://localhost:8080 | Public API, authentication, persistence, final validation |
| PostgreSQL | localhost:15432 by default | Persistent relational database |
| MinIO | localhost:9000 / 9001 | Local S3-compatible storage and console |
| Chatbot, Inference, Cooking, Recommendation | Internal only | Private runtime services |
| Model-package job | No port | Builds a shared runtime model package |

Only the Backend is a public integration boundary. Local service ports and tokens are development-only; agents are intentionally not published by the integrated Compose stack.

## Prerequisites

- Docker Desktop or Docker Engine with Compose
- Git with submodule support
- Optional: PowerShell 7 for the supplied verification scripts

## Quick start

~~~bash
git clone --recurse-submodules https://github.com/foodmind-team/foodmind-infra.git
cd foodmind-infra
cp .env.example .env
docker compose config --quiet
docker compose up --build -d --wait
curl -fsS http://localhost:8080/actuator/health/readiness
~~~

For an existing clone, run git submodule update --init --recursive before the first Compose command. On Windows, use Copy-Item .env.example .env; ./scripts/bootstrap.ps1 performs the submodule/bootstrap flow.

Run FoodMind Web separately from its repository with FOODMIND_BACKEND_ORIGIN=http://localhost:8080.

## Configuration

Copy [.env.example](.env.example) to .env. Its values are local placeholders, not production secrets.

- POSTGRES_*, MINIO_*, and *_PORT configure local dependencies and host ports.
- JWT_SECRET and the internal service tokens must be changed before sharing a local environment.
- FOODMIND_LLM_ENABLED=false is a fully supported deterministic fallback mode. Add a provider key only to the ignored .env.
- MEDIA_ENABLED=false is the safe default: browser-accessible uploads require a deliberate, reachable S3 configuration.
- FOODMIND_COLLABORATIVE_INDEX_PATH is optional and must refer to a verified, HMAC-pseudonymised index; never create it from menu seed data.

## Operations

~~~bash
docker compose ps
docker compose logs -f backend postgres inference recommendation cooking chatbot
docker compose down                 # retains local volumes
docker compose down --volumes       # deletes all local FoodMind data
~~~

The last command is destructive. Use ./scripts/verify.ps1 on PowerShell to render Compose, start the stack, and check Backend readiness. ./scripts/verify-recommendation-diversity.ps1 runs the dedicated recommendation acceptance flow.

## Staging and release

The AWS demonstration/staging deployment is defined by compose.aws-demo.yaml, Caddyfile, CloudFormation templates, and the immutable revisions in releases/staging-source.json. Its current external path is Internet -> EC2 Elastic IP -> Caddy -> Web or Backend; it is not an ALB/ECS/Fargate deployment.

A component's local or CI success does not deploy it. A staging release requires an approved immutable source manifest, Infra validation, digest-pinned image build, approved deployment workflow, readiness/security checks, and real authenticated journey evidence. See [staging continuous delivery](docs/staging-continuous-delivery.md).

## Repository layout

~~~text
compose.yaml                 Integrated local development stack
compose.aws-demo.yaml        EC2/Caddy demonstration and staging stack
releases/                    Immutable release source manifests
scripts/                     Compose, policy, deployment, and verification utilities
docs/                        Local, cloud, security, and CD runbooks
cloudformation.*.yaml        Reviewed cloud infrastructure templates
services/                    Pinned component submodules
~~~

## Contributing

Treat each submodule as an independent repository. Advance a submodule pointer only in a dedicated Infra change after validating the integrated stack. Do not put production secrets in Compose files or .env, do not expose private services, and do not deploy without explicit approval.

## License

No open-source license is currently included in this repository. Obtain permission from the maintainers before redistributing or reusing the code.
