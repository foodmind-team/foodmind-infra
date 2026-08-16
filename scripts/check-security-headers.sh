#!/usr/bin/env bash
set -euo pipefail

target_url="${1:-}"
if [[ ! "${target_url}" =~ ^https://[^[:space:]]+$ ]]; then
  printf 'Usage: %s https://staging.example.com/healthz\n' "${0##*/}" >&2
  exit 2
fi

headers="$(
  curl --fail --silent --show-error \
    --connect-timeout 10 --max-time 30 \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --dump-header - --output /dev/null \
    "${target_url}"
)"
headers="${headers//$'\r'/}"

header_value() {
  local header_name="$1"
  awk -v expected="${header_name}" '
    {
      separator = index($0, ":")
      if (separator > 0 && tolower(substr($0, 1, separator - 1)) == tolower(expected)) {
        value = substr($0, separator + 1)
        sub("^[[:space:]]*", "", value)
        print value
        exit
      }
    }
  ' <<<"${headers}"
}

require_header() {
  local header_name="$1"
  local expected_fragment="$2"
  local value
  value="$(header_value "${header_name}")"
  if [[ -z "${value}" ]]; then
    printf 'ERROR: required response header is missing: %s\n' "${header_name}" >&2
    return 1
  fi
  if [[ "${value}" != *"${expected_fragment}"* ]]; then
    printf 'ERROR: %s does not contain required policy: %s\n' "${header_name}" "${expected_fragment}" >&2
    return 1
  fi
  printf 'PASS: %s\n' "${header_name}"
}

reject_header_fragment() {
  local header_name="$1"
  local rejected_fragment="$2"
  local value
  value="$(header_value "${header_name}")"
  if [[ "${value}" == *"${rejected_fragment}"* ]]; then
    printf 'ERROR: %s contains rejected policy: %s\n' "${header_name}" "${rejected_fragment}" >&2
    return 1
  fi
  printf 'PASS: %s rejects broad policy fragment\n' "${header_name}"
}

require_header 'Strict-Transport-Security' 'max-age=31536000'
require_header 'Content-Security-Policy' "default-src 'self'"
require_header 'Content-Security-Policy' "connect-src 'self' https://*.amazonaws.com"
require_header 'Content-Security-Policy' "frame-ancestors 'none'"
require_header 'Content-Security-Policy' "object-src 'none'"
require_header 'Content-Security-Policy' "style-src 'self'"
require_header 'Content-Security-Policy' "style-src-attr 'unsafe-inline'"
reject_header_fragment 'Content-Security-Policy' "style-src 'self' 'unsafe-inline'"
require_header 'X-Content-Type-Options' 'nosniff'
require_header 'X-Frame-Options' 'DENY'
require_header 'Referrer-Policy' 'strict-origin-when-cross-origin'
require_header 'Permissions-Policy' 'camera=()'
require_header 'Permissions-Policy' 'microphone=()'
require_header 'Permissions-Policy' 'geolocation=(self)'
require_header 'Cross-Origin-Opener-Policy' 'same-origin'
require_header 'Cross-Origin-Resource-Policy' 'same-origin'

printf 'PASS: staging security header policy is present.\n'
