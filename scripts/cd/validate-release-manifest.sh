#!/usr/bin/env bash
set -euo pipefail

MANIFEST_FILE="${1:-}"
EXPECTED_ACCOUNT_ID="${2:-}"
EXPECTED_REGION="${3:-}"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
[[ -f "${MANIFEST_FILE}" ]] || fail "release manifest not found: ${MANIFEST_FILE}"
[[ "${EXPECTED_ACCOUNT_ID}" =~ ^[0-9]{12}$ ]] || fail "expected AWS account ID must contain 12 digits"
[[ "${EXPECTED_REGION}" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]] || fail "expected AWS Region is invalid"

jq -e '
  type == "object" and
  keys == ["database_migrations", "images", "release_id", "schema_version", "source_revisions"] and
  .schema_version == 1 and
  (.release_id | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$")) and
  (.database_migrations | type == "boolean") and
  (.images | type == "object") and
  (.source_revisions | type == "object")
' "${MANIFEST_FILE}" >/dev/null || fail "release manifest shape or top-level fields are invalid"

required_images=(model-package inference recommendation cooking chatbot backend web)
required_revisions=(infra ml intelligence backend web)

actual_images="$(jq -r '.images | keys | join(" ")' "${MANIFEST_FILE}")"
actual_revisions="$(jq -r '.source_revisions | keys | join(" ")' "${MANIFEST_FILE}")"

[[ "${actual_images}" == "backend chatbot cooking inference model-package recommendation web" ]] || \
  fail "images must contain exactly: ${required_images[*]}"
[[ "${actual_revisions}" == "backend infra intelligence ml web" ]] || \
  fail "source_revisions must contain exactly: ${required_revisions[*]}"

registry="${EXPECTED_ACCOUNT_ID}.dkr.ecr.${EXPECTED_REGION}.amazonaws.com"
for image_name in "${required_images[@]}"; do
  image_ref="$(jq -er --arg name "${image_name}" '.images[$name]' "${MANIFEST_FILE}")"
  expected_prefix="${registry}/foodmind/${image_name}@sha256:"
  [[ "${image_ref}" == "${expected_prefix}"* ]] || fail "${image_name} must use the expected private ECR repository"
  digest="${image_ref#${expected_prefix}}"
  [[ "${digest}" =~ ^[0-9a-f]{64}$ ]] || fail "${image_name} must be pinned by a lowercase sha256 digest"
done

for component in "${required_revisions[@]}"; do
  revision="$(jq -er --arg name "${component}" '.source_revisions[$name]' "${MANIFEST_FILE}")"
  [[ "${revision}" =~ ^[0-9a-f]{40}$ ]] || fail "${component} source revision must be a full lowercase Git SHA"
done

printf 'PASS: release manifest %s is structurally valid and digest-pinned.\n' \
  "$(jq -r '.release_id' "${MANIFEST_FILE}")"
