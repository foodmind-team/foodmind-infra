#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${1:-${REPO_ROOT}/.env.aws}"
COMPOSE_FILE="${REPO_ROOT}/compose.aws-demo.yaml"
CLOUDWATCH_COMPOSE_FILE="${REPO_ROOT}/compose.aws-cloudwatch-logs.yaml"

if [[ -f "${ENV_FILE}" && "${ENV_FILE}" != /* ]]; then
  ENV_FILE="$(cd -- "$(dirname -- "${ENV_FILE}")" && pwd)/$(basename -- "${ENV_FILE}")"
fi

for command_name in git docker curl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'ERROR: required command is unavailable: %s\n' "${command_name}" >&2
    exit 1
  fi
done

if ! docker compose version >/dev/null 2>&1; then
  printf 'ERROR: the Docker Compose plugin is unavailable.\n' >&2
  exit 1
fi

cd "${REPO_ROOT}"
git submodule update --init --recursive

"${SCRIPT_DIR}/check-aws-env.sh" "${ENV_FILE}"

cloudwatch_logs_enabled="$(sed -n 's/^FOODMIND_CLOUDWATCH_LOGS_ENABLED=//p' "${ENV_FILE}" | tail -n 1)"
cloudwatch_logs_enabled="${cloudwatch_logs_enabled%$'\r'}"
cloudwatch_logs_enabled="${cloudwatch_logs_enabled%\"}"
cloudwatch_logs_enabled="${cloudwatch_logs_enabled#\"}"
cloudwatch_logs_enabled="${cloudwatch_logs_enabled%\'}"
cloudwatch_logs_enabled="${cloudwatch_logs_enabled#\'}"

compose_files=(-f "${COMPOSE_FILE}")
if [[ "${cloudwatch_logs_enabled:-false}" == "true" ]]; then
  compose_files+=(-f "${CLOUDWATCH_COMPOSE_FILE}")
  printf 'CloudWatch container logging is enabled.\n'
fi
compose=(docker compose --env-file "${ENV_FILE}" "${compose_files[@]}")

printf 'Validating rendered Compose configuration...\n'
"${compose[@]}" config --quiet

printf 'Pulling base images and building release images...\n'
"${compose[@]}" build --pull

printf 'Validating Caddy configuration...\n'
"${compose[@]}" run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

printf 'Starting FoodMind AWS demo stack...\n'
"${compose[@]}" up -d --wait --remove-orphans

"${SCRIPT_DIR}/verify-aws-demo.sh" "${ENV_FILE}"

printf 'Deployment completed. Use the verify script after DNS, IAM, RDS, or S3 changes.\n'
