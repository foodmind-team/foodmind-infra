#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${1:-${REPO_ROOT}/.env.aws}"
RELEASE_ENV_FILE="${2:-}"
COMPOSE_FILE="${REPO_ROOT}/compose.aws-demo.yaml"

if [[ -n "${RELEASE_ENV_FILE}" ]]; then
  [[ -f "${RELEASE_ENV_FILE}" ]] || {
    printf 'ERROR: release environment file not found: %s\n' "${RELEASE_ENV_FILE}" >&2
    exit 1
  }
  "${SCRIPT_DIR}/check-aws-env.sh" "${ENV_FILE}" runtime
  compose=(docker compose --env-file "${ENV_FILE}" --env-file "${RELEASE_ENV_FILE}" -f "${COMPOSE_FILE}")
else
  "${SCRIPT_DIR}/check-aws-env.sh" "${ENV_FILE}"
  compose=(docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
fi

expected_running=(inference recommendation cooking chatbot backend web caddy)
running_services="$("${compose[@]}" ps --status running --services)"

for service in "${expected_running[@]}"; do
  if ! grep -Fxq "${service}" <<<"${running_services}"; then
    printf 'ERROR: expected service is not running: %s\n' "${service}" >&2
    "${compose[@]}" ps >&2
    exit 1
  fi
done

model_container="$("${compose[@]}" ps --all --quiet model-package)"
if [[ -z "${model_container}" ]]; then
  printf 'ERROR: model-package container was not created.\n' >&2
  exit 1
fi
model_state="$(docker inspect --format '{{.State.Status}} {{.State.ExitCode}}' "${model_container}")"
if [[ "${model_state}" != "exited 0" ]]; then
  printf 'ERROR: model-package job did not complete successfully: %s\n' "${model_state}" >&2
  exit 1
fi

"${compose[@]}" exec -T backend curl --fail --silent http://127.0.0.1:8080/actuator/health/readiness >/dev/null
"${compose[@]}" exec -T inference python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8002/health/ready', timeout=2).read()"
"${compose[@]}" exec -T recommendation python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8004/health/ready', timeout=2).read()"
"${compose[@]}" exec -T cooking /app/.venv/bin/python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8003/health/ready', timeout=2).read()"
"${compose[@]}" exec -T chatbot python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8001/health/ready', timeout=2).read()"
"${compose[@]}" exec -T web wget --quiet --output-document=/dev/null http://127.0.0.1:8080/healthz

domain="$(sed -n 's/^FOODMIND_DOMAIN=//p' "${ENV_FILE}" | tail -n 1)"
domain="${domain%$'\r'}"
domain="${domain%\"}"
domain="${domain#\"}"
domain="${domain%\'}"
domain="${domain#\'}"
if [[ "${SKIP_PUBLIC_CHECK:-false}" != "true" ]]; then
  curl --fail --silent --show-error \
    --retry 6 --retry-delay 5 --retry-all-errors \
    "https://${domain}/healthz" >/dev/null
fi

printf 'PASS: containers, private readiness endpoints, Web health, and public HTTPS passed.\n'
