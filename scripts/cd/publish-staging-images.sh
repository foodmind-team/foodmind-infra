#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
SOURCE_FILE="${1:-${REPO_ROOT}/releases/staging-source.json}"
WEB_CHECKOUT="${2:-${REPO_ROOT}/../foodmind-web}"
OUTPUT_FILE="${3:-${REPO_ROOT}/release-manifest.json}"
SECURITY_EVIDENCE_DIR="${4:-${REPO_ROOT}/release-security-evidence}"
TRIVY_IMAGE="aquasec/trivy:0.74.0@sha256:ee940acbf1f58ebadb42d01434ce4609530bf1b52536afbd1eee66cd7123c5c9"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

for command_name in aws docker git jq; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "required command is unavailable: ${command_name}"
done

required_environment=(
  AWS_ACCOUNT_ID
  AWS_REGION
  INFRA_REVISION
  GITHUB_RUN_ID
  GITHUB_RUN_ATTEMPT
)
for key in "${required_environment[@]}"; do
  [[ -n "${!key:-}" ]] || fail "${key} is required"
done
[[ "${AWS_ACCOUNT_ID}" =~ ^[0-9]{12}$ ]] || fail "AWS_ACCOUNT_ID must contain 12 digits"
[[ "${AWS_REGION}" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]] || fail "AWS_REGION is invalid"
[[ "${INFRA_REVISION}" =~ ^[0-9a-f]{40}$ ]] || fail "INFRA_REVISION must be a full Git SHA"
[[ "${GITHUB_RUN_ID}" =~ ^[0-9]+$ ]] || fail "GITHUB_RUN_ID must be numeric"
[[ "${GITHUB_RUN_ATTEMPT}" =~ ^[0-9]+$ ]] || fail "GITHUB_RUN_ATTEMPT must be numeric"
[[ -f "${WEB_CHECKOUT}/Dockerfile" ]] || fail "Web checkout is incomplete: ${WEB_CHECKOUT}"

"${SCRIPT_DIR}/validate-release-source.sh" "${SOURCE_FILE}"
[[ "$(git -C "${REPO_ROOT}" rev-parse HEAD)" == "${INFRA_REVISION}" ]] || \
  fail "Infra checkout does not match INFRA_REVISION"

web_revision="$(jq -r '.web_revision' "${SOURCE_FILE}")"
[[ "$(git -C "${WEB_CHECKOUT}" rev-parse HEAD)" == "${web_revision}" ]] || \
  fail "Web checkout does not match releases/staging-source.json"

actual_account_id="$(aws sts get-caller-identity --query Account --output text --region "${AWS_REGION}" --no-cli-pager)"
[[ "${actual_account_id}" == "${AWS_ACCOUNT_ID}" ]] || \
  fail "expected AWS account ${AWS_ACCOUNT_ID}, got ${actual_account_id}"

registry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
image_tag="${INFRA_REVISION:0:12}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
release_id="staging-${image_tag}"
docker_config_dir="$(mktemp -d)"
trivy_cache_dir="$(mktemp -d)"
manifest_tmp="$(mktemp)"
cleanup() {
  rm -rf -- "${docker_config_dir}"
  rm -rf -- "${trivy_cache_dir}"
  rm -f -- "${manifest_tmp}"
}
trap cleanup EXIT
chmod 700 "${docker_config_dir}"
export DOCKER_CONFIG="${docker_config_dir}"
mkdir -p "${SECURITY_EVIDENCE_DIR}"

aws ecr get-login-password --region "${AWS_REGION}" --no-cli-pager | \
  docker login --username AWS --password-stdin "${registry}" >/dev/null

declare -A image_digests
build_and_publish() {
  local image_name="$1"
  local context="$2"
  local dockerfile="$3"
  shift 3
  local repository="foodmind/${image_name}"
  local image_ref="${registry}/${repository}:${image_tag}"
  local digest=""

  printf 'Building %s from %s...\n' "${image_name}" "${context}"
  docker build --pull --file "${dockerfile}" --tag "${image_ref}" "$@" "${context}"

  printf 'Generating SBOM for %s...\n' "${image_name}"
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "${trivy_cache_dir}:/root/.cache/trivy" \
    -v "${SECURITY_EVIDENCE_DIR}:/evidence" \
    "${TRIVY_IMAGE}" image \
    --format cyclonedx \
    --output "/evidence/${image_name}-sbom.cdx.json" \
    "${image_ref}"

  printf 'Scanning %s for fixable Medium-or-higher vulnerabilities...\n' "${image_name}"
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "${trivy_cache_dir}:/root/.cache/trivy" \
    -v "${SECURITY_EVIDENCE_DIR}:/evidence" \
    "${TRIVY_IMAGE}" image \
    --scanners vuln \
    --ignore-unfixed \
    --severity MEDIUM,HIGH,CRITICAL \
    --exit-code 1 \
    --format json \
    --output "/evidence/${image_name}-trivy.json" \
    "${image_ref}"

  docker push "${image_ref}"

  for _ in {1..12}; do
    digest="$(aws ecr describe-images \
      --repository-name "${repository}" \
      --image-ids "imageTag=${image_tag}" \
      --query 'imageDetails[0].imageDigest' \
      --output text \
      --region "${AWS_REGION}" \
      --no-cli-pager 2>/dev/null || true)"
    [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] && break
    sleep 5
  done
  [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "ECR did not return a digest for ${repository}:${image_tag}"
  image_digests["${image_name}"]="${registry}/${repository}@${digest}"
}

build_and_publish model-package "${REPO_ROOT}/services/ml" "${REPO_ROOT}/docker/model-package.Dockerfile"
build_and_publish inference "${REPO_ROOT}/services/intelligence/inference-service" \
  "${REPO_ROOT}/services/intelligence/inference-service/Dockerfile"
build_and_publish recommendation \
  "${REPO_ROOT}/services/intelligence/agent-service/app/agents/recommendation" \
  "${REPO_ROOT}/services/intelligence/agent-service/app/agents/recommendation/Dockerfile" \
  --build-arg "SOURCE_REVISION=${INFRA_REVISION}"
build_and_publish cooking \
  "${REPO_ROOT}/services/intelligence/agent-service/app/agents/cooking" \
  "${REPO_ROOT}/services/intelligence/agent-service/app/agents/cooking/Dockerfile"
build_and_publish chatbot \
  "${REPO_ROOT}/services/intelligence/agent-service/app/agents/chatbot" \
  "${REPO_ROOT}/services/intelligence/agent-service/app/agents/chatbot/Dockerfile"
build_and_publish backend "${REPO_ROOT}/services/backend" "${REPO_ROOT}/services/backend/Dockerfile"
build_and_publish web "${WEB_CHECKOUT}" "${WEB_CHECKOUT}/Dockerfile"

database_migrations="$(jq -r '.database_migrations' "${SOURCE_FILE}")"
backend_revision="$(git -C "${REPO_ROOT}" rev-parse HEAD:services/backend)"
intelligence_revision="$(git -C "${REPO_ROOT}" rev-parse HEAD:services/intelligence)"
ml_revision="$(git -C "${REPO_ROOT}" rev-parse HEAD:services/ml)"

jq -n \
  --arg release_id "${release_id}" \
  --argjson database_migrations "${database_migrations}" \
  --arg model_package "${image_digests[model-package]}" \
  --arg inference "${image_digests[inference]}" \
  --arg recommendation "${image_digests[recommendation]}" \
  --arg cooking "${image_digests[cooking]}" \
  --arg chatbot "${image_digests[chatbot]}" \
  --arg backend "${image_digests[backend]}" \
  --arg web "${image_digests[web]}" \
  --arg infra_revision "${INFRA_REVISION}" \
  --arg ml_revision "${ml_revision}" \
  --arg intelligence_revision "${intelligence_revision}" \
  --arg backend_revision "${backend_revision}" \
  --arg web_revision "${web_revision}" \
  '{
    schema_version: 1,
    release_id: $release_id,
    database_migrations: $database_migrations,
    images: {
      "model-package": $model_package,
      inference: $inference,
      recommendation: $recommendation,
      cooking: $cooking,
      chatbot: $chatbot,
      backend: $backend,
      web: $web
    },
    source_revisions: {
      infra: $infra_revision,
      ml: $ml_revision,
      intelligence: $intelligence_revision,
      backend: $backend_revision,
      web: $web_revision
    }
  }' >"${manifest_tmp}"

"${SCRIPT_DIR}/validate-release-manifest.sh" "${manifest_tmp}" "${AWS_ACCOUNT_ID}" "${AWS_REGION}"
install -m 600 "${manifest_tmp}" "${OUTPUT_FILE}"
printf 'PASS: release %s was published with seven immutable ECR digests.\n' "${release_id}"
