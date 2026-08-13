# FoodMind Infrastructure

This repository is the local development control plane for FoodMind. It pins
the Backend, Intelligence, ML, and Docs repositories as Git submodules and
starts the complete backend stack with one Compose project. The Web repository
is deliberately **not** included or built here; run it from `foodmind-web` and
point it at `http://localhost:8080`.

An isolated single-EC2 AWS demonstration topology is also available through
`compose.aws-demo.yaml`. It adds the sibling Web checkout and Caddy, uses
private RDS PostgreSQL and optional S3 instead of the local PostgreSQL/MinIO
services, and publishes only ports 80/443. It is intentionally not the
production ECS architecture. See [AWS demo deployment](docs/aws-demo-deployment.md).
The digest-pinned staging release path is documented in
[staging continuous delivery](docs/staging-continuous-delivery.md).

## Quick start

Clone with the pinned source repositories, then create your local environment:

```powershell
git clone --recurse-submodules git@github.com:foodmind-team/foodmind-infra.git
cd foodmind-infra
Copy-Item .env.example .env
docker compose up --build -d --wait
```

On an existing clone, run `git submodule update --init --recursive` once before
the first `docker compose` command. Windows users can run
`./scripts/bootstrap.ps1` instead; it performs both steps and starts the stack.

The normal local stack needs no external key. To use DeepSeek enhancements,
set both values in `.env` and recreate the three Agent containers:

```dotenv
FOODMIND_LLM_ENABLED=true
DEEPSEEK_API_KEY=your-key
```

Chatbot defaults to `deepseek-v4-pro` in non-thinking mode with temperature
`1.0` and an 800-token output cap, allowing varied conversational answers
without long-form drift while Backend-authorised facts remain fixed grounding
constraints. These Chatbot-specific values can be overridden with
`CHAT_AGENT_LLM_MODEL`, `CHAT_AGENT_LLM_TEMPERATURE`,
`CHAT_AGENT_LLM_MAX_OUTPUT_TOKENS`, and `CHAT_AGENT_LLM_THINKING_ENABLED`.

```powershell
docker compose up -d --force-recreate recommendation cooking chatbot
```

Without a key, Chatbot, Cooking, and Recommendation start normally and return
their deterministic controlled path; a missing key never blocks Compose.

## What starts

| Service | Host address | Responsibility |
| --- | --- | --- |
| Backend | `http://localhost:8080` | Public API, authentication, persistence, final validation |
| PostgreSQL 18.4 | `localhost:15432` by default | Persistent relational data |
| MinIO API / console | `localhost:9000` / `localhost:9001` | S3-compatible local object storage |
| Chatbot | internal `:8001` | Read-only authorised platform exploration |
| Inference | internal `:8002` | ML scoring only |
| Cooking Agent | internal `:8003` | Cooking-plan workflow |
| Recommendation Agent | internal `:8004` | ML-result validation and explanation |
| Model Package job | no port | Builds the checked-in ML artifact into a shared runtime volume |

Agents are intentionally not published to the host. Backend is their only
public integration boundary. Use `docker compose exec <service> ...` for
diagnostics rather than exposing internal endpoints.

## Environment contract

`.env.example` lists every variable used by Compose. The important groups are:

- `POSTGRES_*`, `MINIO_*`, and `*_PORT`: local infrastructure and host ports.
- `JWT_SECRET`: local Backend signing secret; change it before sharing a stack.
- `INTERNAL_SERVICE_TOKEN`, `*_AGENT_SERVICE_TOKEN`, and
  `INFERENCE_INTERNAL_SERVICE_TOKEN`: matched private service boundaries. Keep
  the supplied local values consistent; do not put production secrets here.
- `FOODMIND_LLM_ENABLED` and `DEEPSEEK_API_KEY`: optional DeepSeek enhancement.
  A blank key with LLM disabled is a supported offline development mode.
- `CHAT_AGENT_LLM_*`: Chatbot model and sampling controls. The defaults favour
  natural, non-template conversation; readiness reports the active safe
  metadata without exposing the key.
- `MEDIA_ENABLED`: defaults to `false`. MinIO and its bucket still start, but
  browser-accessible presigned uploads require a browser-reachable S3 endpoint
  and are intentionally not enabled by this internal-only default.

Never commit `.env`. It is ignored by Git.

## Lifecycle and diagnostics

```powershell
# Verify rendered configuration, build, health dependencies, and Backend readiness.
./scripts/verify.ps1

# Watch the full dependency chain.
docker compose logs -f postgres model-package inference recommendation cooking chatbot backend

# Stop containers while retaining database, object, and model volumes.
docker compose down

# Remove all local FoodMind data as well (destructive).
docker compose down --volumes
```

`docker compose up --build -d --wait` waits for PostgreSQL, MinIO, Inference,
the three Agents, and Backend readiness. `model-package` and `minio-init` are
one-shot jobs: they must complete successfully before their consumers start.

## Source pinning and updates

Submodules make a stack reproducible: the parent commit records every exact
child commit. They are not advanced automatically. Update a submodule only in
a dedicated Infra pull request, validate the whole Compose stack, and review
the resulting pointer change.

The Docs submodule is included as the verified full-stack reference, but is
not part of the runtime image build. The Web submodule is intentionally absent
because frontend packaging remains owned by `foodmind-web`.

## CI policy

GitHub Actions validates Compose rendering on every pull request that changes
infrastructure or a submodule pointer. A manual or scheduled integration job
builds the local images, starts the stack with LLM disabled, waits for health,
and checks Backend readiness. Child repositories should not push mutable image
tags into this development workflow: an Infra PR advances the pinned source
commit only after the integrated build passes.
