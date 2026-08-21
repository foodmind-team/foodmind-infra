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

## Local deployment (recommended full stack)

Use this repository when a complete local product journey is needed. It is the
only one-command runtime for the Backend, PostgreSQL, MinIO, Intelligence
services, and the ML model-package job. Web and Android are deliberately kept
outside this Compose project and connect only to the Backend.

On Windows PowerShell, clone with the pinned component sources, create a local
environment file, validate it, and start the health-gated stack:

```powershell
git clone --recurse-submodules https://github.com/foodmind-team/foodmind-infra.git
Set-Location foodmind-infra
git submodule update --init --recursive
Copy-Item .env.example .env
docker compose config --quiet
docker compose up --build -d --wait
Invoke-RestMethod http://localhost:8080/actuator/health/readiness
docker compose ps
```

`./scripts/bootstrap.ps1` performs the submodule, `.env`, and startup steps;
`./scripts/verify.ps1` additionally waits for Backend readiness. The equivalent
shell setup is `cp .env.example .env` followed by the same `docker compose`
commands. Keep the default `FOODMIND_LLM_ENABLED=false` unless an optional
provider key has been placed only in the ignored `.env` file.

The normal local addresses are Backend `http://localhost:8080`, PostgreSQL
`localhost:15432`, and MinIO `http://localhost:9000` (console `9001`). Agent
and inference containers are private to the `foodmind-runtime` network. If a
host port is occupied, change the corresponding public port in `.env` and run
the Compose commands again; do not change container-to-container addresses.

To inspect a failed startup, use `docker compose logs -f backend postgres
inference recommendation cooking chatbot`. `docker compose down` stops the
stack while retaining local data. `docker compose down --volumes` also deletes
the local PostgreSQL, MinIO, and model-package volumes, so use it only when the
loss of local development data is intended.

## Configuration

Copy [.env.example](.env.example) to .env. Its values are local placeholders, not production secrets.

- POSTGRES_*, MINIO_*, and *_PORT configure local dependencies and host ports.
- JWT_SECRET and the internal service tokens must be changed before sharing a local environment.
- FOODMIND_LLM_ENABLED=false is a fully supported deterministic fallback mode. Add a provider key only to the ignored .env.

## API keys and service tokens

The integrated stack reads secrets and optional provider settings from the
ignored root `.env`; copy `.env.example` first and edit only that copy. Do not
put a real value in Compose files, a README, a client `.env`, or a Git commit.

```dotenv
# Use unique local values; replace these placeholders before sharing an environment.
JWT_SECRET=<random-local-secret-at-least-32-characters>
INTERNAL_SERVICE_TOKEN=<backend-internal-tools-token>
RECOMMENDATION_AGENT_SERVICE_TOKEN=<recommendation-service-token>
INFERENCE_INTERNAL_SERVICE_TOKEN=<inference-service-token>
COOKING_AGENT_SERVICE_TOKEN=<cooking-service-token>
CHAT_AGENT_SERVICE_TOKEN=<chat-service-token>

# Optional OneMap walking routes
ONEMAP_ROUTES_ENABLED=true
ONEMAP_API_TOKEN=<onemap-access-token>

# Optional provider-backed Agent enhancements
FOODMIND_LLM_ENABLED=true
DEEPSEEK_API_KEY=<provider-api-key>
```

Leave both optional features disabled and their keys blank when they are not
needed: the stack remains usable with deterministic fallbacks. OneMap and LLM
keys belong only in Infra because the Backend and private services consume them
inside Docker; Web and Android never receive them. Compose injects the five
service-token values into their matching Backend/Agent boundaries. When running
a component outside Infra, configure the same corresponding pair on both sides
of that private boundary rather than inventing a client token.

For local MinIO, `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, and the `MEDIA_*`
values remain in this `.env`. Keep `MEDIA_ENABLED=false` unless the configured
S3 endpoint is browser-reachable; a private Docker hostname cannot be used by
a browser for presigned uploads.
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
