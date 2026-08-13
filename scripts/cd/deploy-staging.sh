#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
MANIFEST_FILE="${1:-}"
ENV_FILE="${2:-/opt/foodmind/foodmind-infra/.env.aws}"
STATE_DIR="${FOODMIND_CD_STATE_DIR:-/opt/foodmind/cd-state}"
COMPOSE_FILE="${REPO_ROOT}/compose.aws-demo.yaml"
LOCK_FILE="${STATE_DIR}/deploy.lock"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

for command_name in aws docker flock jq curl; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "required command is unavailable: ${command_name}"
done
docker compose version >/dev/null 2>&1 || fail "the Docker Compose plugin is unavailable"
[[ -f "${MANIFEST_FILE}" ]] || fail "release manifest not found: ${MANIFEST_FILE}"

install -d -m 700 "${STATE_DIR}"
exec 9>"${LOCK_FILE}"
flock -n 9 || fail "another staging deployment is already running"

docker_config_dir="$(mktemp -d "${STATE_DIR}/docker-config.XXXXXX")"
chmod 700 "${docker_config_dir}"
export DOCKER_CONFIG="${docker_config_dir}"
cleanup() {
  rm -rf -- "${docker_config_dir}"
}
trap cleanup EXIT

"${REPO_ROOT}/scripts/check-aws-env.sh" "${ENV_FILE}" runtime

env_value() {
  local key="$1"
  local value
  value="$(sed -n "s/^${key}=//p" "${ENV_FILE}" | tail -n 1)"
  value="${value%$'\r'}"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "${value}"
}

aws_region="$(env_value AWS_REGION)"
account_id="$(aws sts get-caller-identity --query Account --output text --region "${aws_region}" --no-cli-pager)"
"${SCRIPT_DIR}/validate-release-manifest.sh" "${MANIFEST_FILE}" "${account_id}" "${aws_region}"

release_id="$(jq -r '.release_id' "${MANIFEST_FILE}")"
current_manifest="${STATE_DIR}/current-manifest.json"
previous_manifest="${STATE_DIR}/previous-manifest.json"
release_env="${STATE_DIR}/release.env"
rollback_env="${STATE_DIR}/rollback.env"

if [[ -f "${current_manifest}" ]] && cmp -s "${MANIFEST_FILE}" "${current_manifest}"; then
  printf 'Release %s is already deployed; verifying current health.\n' "${release_id}"
  "${REPO_ROOT}/scripts/verify-aws-demo.sh" "${ENV_FILE}" "${release_env}"
  exit 0
fi
if [[ -f "${current_manifest}" ]] && \
   [[ "$(jq -r '.release_id' "${current_manifest}")" == "${release_id}" ]]; then
  fail "release ID ${release_id} is already associated with different content"
fi

registry="${account_id}.dkr.ecr.${aws_region}.amazonaws.com"
aws ecr get-login-password --region "${aws_region}" --no-cli-pager | \
  docker login --username AWS --password-stdin "${registry}" >/dev/null

if [[ -f "${current_manifest}" ]]; then
  cp -f "${current_manifest}" "${previous_manifest}"
  "${SCRIPT_DIR}/render-release-env.sh" "${previous_manifest}" "${rollback_env}"
elif [[ ! -f "${rollback_env}" ]]; then
  umask 077
  : >"${rollback_env}"
  baseline_compose=(docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
  for service in model-package inference recommendation cooking chatbot backend web; do
    container_id="$("${baseline_compose[@]}" ps --all --quiet "${service}")"
    [[ -n "${container_id}" ]] || fail "cannot capture first-deploy rollback image for ${service}"
    image_ref="$(docker inspect --format '{{.Config.Image}}' "${container_id}")"
    [[ -n "${image_ref}" ]] || fail "cannot inspect first-deploy rollback image for ${service}"
    case "${service}" in
      model-package) image_key=FOODMIND_MODEL_PACKAGE_IMAGE ;;
      inference) image_key=FOODMIND_INFERENCE_IMAGE ;;
      recommendation) image_key=FOODMIND_RECOMMENDATION_IMAGE ;;
      cooking) image_key=FOODMIND_COOKING_IMAGE ;;
      chatbot) image_key=FOODMIND_CHATBOT_IMAGE ;;
      backend) image_key=FOODMIND_BACKEND_IMAGE ;;
      web) image_key=FOODMIND_WEB_IMAGE ;;
    esac
    printf '%s=%s\n' "${image_key}" "${image_ref}" >>"${rollback_env}"
  done
  chmod 600 "${rollback_env}"
fi

"${SCRIPT_DIR}/render-release-env.sh" "${MANIFEST_FILE}" "${release_env}.candidate"
candidate_compose=(docker compose --env-file "${ENV_FILE}" --env-file "${release_env}.candidate" -f "${COMPOSE_FILE}")

printf 'Pulling immutable images for release %s...\n' "${release_id}"
"${candidate_compose[@]}" pull model-package inference recommendation cooking chatbot backend web
"${candidate_compose[@]}" config --quiet

rollback() {
  printf 'Deployment failed; restoring the captured previous image set.\n' >&2
  rollback_compose=(docker compose --env-file "${ENV_FILE}" --env-file "${rollback_env}" -f "${COMPOSE_FILE}")
  "${rollback_compose[@]}" up -d --wait --wait-timeout 300 --remove-orphans --no-build
  "${REPO_ROOT}/scripts/verify-aws-demo.sh" "${ENV_FILE}" "${rollback_env}"
  rm -f "${release_env}.candidate"
  printf 'Rollback completed; release %s was not promoted.\n' "${release_id}" >&2
}

printf 'Deploying release %s to the single-EC2 staging environment...\n' "${release_id}"
if ! "${candidate_compose[@]}" up -d --wait --wait-timeout 300 --remove-orphans --no-build; then
  rollback
  exit 1
fi
if ! "${REPO_ROOT}/scripts/verify-aws-demo.sh" "${ENV_FILE}" "${release_env}.candidate"; then
  rollback
  exit 1
fi

mv -f "${release_env}.candidate" "${release_env}"
cp -f "${MANIFEST_FILE}" "${current_manifest}"
chmod 600 "${release_env}" "${current_manifest}"
printf 'PASS: release %s is deployed and healthy.\n' "${release_id}"
