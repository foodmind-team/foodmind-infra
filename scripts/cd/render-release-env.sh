#!/usr/bin/env bash
set -euo pipefail

MANIFEST_FILE="${1:-}"
OUTPUT_FILE="${2:-}"

if [[ -z "${MANIFEST_FILE}" || -z "${OUTPUT_FILE}" ]]; then
  printf 'Usage: %s MANIFEST OUTPUT\n' "$0" >&2
  exit 1
fi

umask 077
tmp_file="${OUTPUT_FILE}.tmp.$$"
trap 'rm -f "${tmp_file}"' EXIT

jq -r '
  [
    ["FOODMIND_MODEL_PACKAGE_IMAGE", .images["model-package"]],
    ["FOODMIND_INFERENCE_IMAGE", .images.inference],
    ["FOODMIND_RECOMMENDATION_IMAGE", .images.recommendation],
    ["FOODMIND_COOKING_IMAGE", .images.cooking],
    ["FOODMIND_CHATBOT_IMAGE", .images.chatbot],
    ["FOODMIND_BACKEND_IMAGE", .images.backend],
    ["FOODMIND_WEB_IMAGE", .images.web]
  ] | .[] | @tsv
' "${MANIFEST_FILE}" | while IFS=$'\t' read -r key value; do
  printf '%s=%s\n' "${key}" "${value}"
done >"${tmp_file}"

chmod 600 "${tmp_file}"
mv -f "${tmp_file}" "${OUTPUT_FILE}"
trap - EXIT
