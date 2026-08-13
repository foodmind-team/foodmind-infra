#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${1:-${REPO_ROOT}/.env.aws}"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

if [[ ! -f "${ENV_FILE}" ]]; then
  fail "environment file not found: ${ENV_FILE}"
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  FILE_MODE="$(stat -f '%Lp' "${ENV_FILE}")"
else
  FILE_MODE="$(stat -c '%a' "${ENV_FILE}")"
fi
case "${FILE_MODE}" in
  400|600) ;;
  *) fail "${ENV_FILE} must have mode 600 or 400; current mode is ${FILE_MODE}" ;;
esac

env_value() {
  local key="$1"
  local value
  value="$(sed -n "s/^${key}=//p" "${ENV_FILE}" | tail -n 1)"
  value="${value%$'\r'}"
  if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "${value}"
}

required_keys=(
  FOODMIND_DOMAIN
  FOODMIND_ACME_EMAIL
  FOODMIND_WEB_CONTEXT
  FOODMIND_IMAGE_TAG
  CADDY_IMAGE
  AWS_REGION
  DB_HOST
  DB_PORT
  DB_NAME
  DB_USERNAME
  DB_PASSWORD
  JWT_SECRET
  INTERNAL_SERVICE_TOKEN
  RECOMMENDATION_AGENT_SERVICE_TOKEN
  INFERENCE_INTERNAL_SERVICE_TOKEN
  COOKING_AGENT_SERVICE_TOKEN
  CHAT_AGENT_SERVICE_TOKEN
)

for key in "${required_keys[@]}"; do
  value="$(env_value "${key}")"
  if [[ -z "${value}" ]]; then
    fail "${key} is required"
  fi
  if [[ "${value}" == *CHANGE_ME* || "${value}" == *replace-with* || "${value}" == replace.* ]]; then
    fail "${key} still contains an example placeholder"
  fi
done

image_tag="$(env_value FOODMIND_IMAGE_TAG)"
if [[ "${image_tag}" == "dev" || "${image_tag}" == "latest" ]]; then
  fail "FOODMIND_IMAGE_TAG must identify an explicit release or Git SHA"
fi

caddy_image="$(env_value CADDY_IMAGE)"
if [[ "${caddy_image}" != *@sha256:* ]]; then
  fail "CADDY_IMAGE must be pinned by sha256 digest"
fi

aws_region="$(env_value AWS_REGION)"
if [[ ! "${aws_region}" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]]; then
  fail "AWS_REGION is not a valid Region identifier"
fi

db_host="$(env_value DB_HOST)"
if [[ "${db_host}" == "localhost" || "${db_host}" == "127.0.0.1" || "${db_host}" == "postgres" ]]; then
  fail "DB_HOST must be a private RDS endpoint, not a local Compose database"
fi

if [[ "$(env_value DB_SSL_MODE)" != "require" ]]; then
  fail "DB_SSL_MODE must be require for the AWS demo"
fi

domain="$(env_value FOODMIND_DOMAIN)"
if [[ "${domain}" == *://* || "${domain}" == */* || "${domain}" == *.example.com || "${domain}" == example.com ]]; then
  fail "FOODMIND_DOMAIN must be a real hostname without a scheme or path"
fi

email="$(env_value FOODMIND_ACME_EMAIL)"
if [[ "${email}" != *@*.* || "${email}" == *@example.com ]]; then
  fail "FOODMIND_ACME_EMAIL must be a real operational email address"
fi

secret_keys=(
  INTERNAL_SERVICE_TOKEN
  RECOMMENDATION_AGENT_SERVICE_TOKEN
  INFERENCE_INTERNAL_SERVICE_TOKEN
  COOKING_AGENT_SERVICE_TOKEN
  CHAT_AGENT_SERVICE_TOKEN
)
for key in "${secret_keys[@]}"; do
  value="$(env_value "${key}")"
  if (( ${#value} < 24 )); then
    fail "${key} must be at least 24 characters"
  fi
done

jwt_secret="$(env_value JWT_SECRET)"
if (( ${#jwt_secret} < 32 )); then
  fail "JWT_SECRET must be at least 32 characters"
fi

db_password="$(env_value DB_PASSWORD)"
if (( ${#db_password} < 16 )); then
  fail "DB_PASSWORD must be at least 16 characters"
fi

media_enabled="$(env_value MEDIA_ENABLED)"
case "${media_enabled:-false}" in
  true|false) ;;
  *) fail "MEDIA_ENABLED must be true or false" ;;
esac
if [[ "${media_enabled:-false}" == "true" && -z "$(env_value MEDIA_S3_BUCKET)" ]]; then
  fail "MEDIA_S3_BUCKET is required when MEDIA_ENABLED=true"
fi

llm_enabled="$(env_value FOODMIND_LLM_ENABLED)"
case "${llm_enabled:-false}" in
  true|false) ;;
  *) fail "FOODMIND_LLM_ENABLED must be true or false" ;;
esac
if [[ "${llm_enabled:-false}" == "true" && -z "$(env_value DEEPSEEK_API_KEY)" ]]; then
  fail "DEEPSEEK_API_KEY is required when FOODMIND_LLM_ENABLED=true"
fi

web_context="$(env_value FOODMIND_WEB_CONTEXT)"
if [[ "${web_context}" == /* ]]; then
  web_path="${web_context}"
else
  web_path="${REPO_ROOT}/${web_context}"
fi
if [[ ! -f "${web_path}/Dockerfile" || ! -f "${web_path}/package-lock.json" ]]; then
  fail "FOODMIND_WEB_CONTEXT does not point to a complete foodmind-web checkout: ${web_path}"
fi

required_source_files=(
  services/backend/Dockerfile
  services/intelligence/inference-service/Dockerfile
  services/intelligence/agent-service/app/agents/chatbot/Dockerfile
  services/intelligence/agent-service/app/agents/cooking/Dockerfile
  services/intelligence/agent-service/app/agents/recommendation/Dockerfile
  services/ml/scripts/build_runtime_package.py
  services/ml/artifacts/candidate/hybrid_lr_model.npz
)
for path in "${required_source_files[@]}"; do
  if [[ ! -f "${REPO_ROOT}/${path}" ]]; then
    fail "required submodule file is missing: ${path}; run git submodule update --init --recursive"
  fi
done

printf 'PASS: AWS demo environment and source checkout passed static validation.\n'
