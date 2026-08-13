#!/usr/bin/env bash
set -euo pipefail

SOURCE_FILE="${1:-}"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
[[ -f "${SOURCE_FILE}" ]] || fail "release source not found: ${SOURCE_FILE}"

jq -e '
  type == "object" and
  keys == ["database_migrations", "schema_version", "web_revision"] and
  .schema_version == 1 and
  (.database_migrations | type == "boolean") and
  (.web_revision | type == "string" and test("^[0-9a-f]{40}$"))
' "${SOURCE_FILE}" >/dev/null || fail "release source fields are invalid"

printf 'PASS: release source pins Web to %s.\n' "$(jq -r '.web_revision' "${SOURCE_FILE}")"
