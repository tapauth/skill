#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# tapauth.sh — OAuth token broker for AI agents (https://tapauth.ai)
# Security: no eval/source; allowlisted KEY=VALUE parser; cache mode 700/600; 600s poll timeout
set -euo pipefail

TAPAUTH_BASE="${TAPAUTH_BASE_URL:-https://tapauth.ai}"
TAPAUTH_DIR="${TAPAUTH_HOME:-${CLAUDE_PLUGIN_DATA:-./.tapauth}}"
mkdir -p "$TAPAUTH_DIR" && chmod 700 "$TAPAUTH_DIR"

mode="url"
[ "${1:-}" = "--token" ] && { mode="token"; shift; }

provider="${1:-}"; scopes="${2:-}"
[ -z "$provider" ] && { echo "usage: tapauth [--token] <provider> [scopes]" >&2; exit 1; }
[[ "$provider" =~ ^[a-z][a-z0-9_]*$ ]] || { echo "tapauth: invalid provider name" >&2; exit 1; }

sorted=""
[ -n "$scopes" ] && sorted=$(printf '%s' "$scopes" | tr ',' '\n' | LC_ALL=C sort -u | tr '\n' ',' | sed 's/,$//')
env_file="${TAPAUTH_DIR}/$(printf '%s' "${provider}-${sorted}" | tr '/:' '__').env"

die() { echo "tapauth: $*" >&2; exit 1; }

# Allowlisted KEY=VALUE parser — avoids eval/source (security review requirement)
parse_env_response() {
  while IFS='=' read -r key value; do
    value="${value%$'\r'}"
    case "$key" in
      TAPAUTH_TOKEN)        TAPAUTH_TOKEN="$value" ;;
      TAPAUTH_GRANT_ID)     TAPAUTH_GRANT_ID="$value" ;;
      TAPAUTH_GRANT_SECRET) TAPAUTH_GRANT_SECRET="$value" ;;
      TAPAUTH_APPROVE_URL)  TAPAUTH_APPROVE_URL="$value" ;;
      TAPAUTH_STATUS)       TAPAUTH_STATUS="$value" ;;
    esac
  done <<< "$1"
}

ready() {
  [ "$mode" = "url" ] && { echo "Already authorized for ${provider}${sorted:+ ($sorted)}. Use --token to get the bearer token."; exit 0; }
  [ -n "${TAPAUTH_TOKEN:-}" ] || die "no token in response"
  echo "${TAPAUTH_TOKEN:-}"; exit 0
}

save() {
  install -m 600 /dev/null "$env_file"
  cat > "$env_file" <<EOF
TAPAUTH_GRANT_ID=${TAPAUTH_GRANT_ID:-}
TAPAUTH_GRANT_SECRET=${TAPAUTH_GRANT_SECRET:-}
EOF
}

fetch() {
  TAPAUTH_TOKEN="" TAPAUTH_STATUS=""
  local resp
  resp=$(curl --silent --show-error -w "\n%{http_code}" \
    -H "Authorization: Bearer ${TAPAUTH_GRANT_SECRET}" \
    -H 'Accept: text/plain' "${TAPAUTH_BASE}/api/v1/grants/${TAPAUTH_GRANT_ID}") || die "failed to contact TapAuth"
  TAPAUTH_HTTP="${resp##*$'\n'}"
  parse_env_response "${resp%$'\n'*}"
}

create_grant() {
  echo "Creating grant for ${provider}${sorted:+ ($sorted)}..." >&2
  TAPAUTH_GRANT_ID="" TAPAUTH_GRANT_SECRET="" TAPAUTH_APPROVE_URL=""
  create_args=(curl --silent --show-error -w "\n%{http_code}" -X POST -H 'Accept: text/plain'
    --data-urlencode "provider=${provider}")
  [ -n "$sorted" ] && create_args+=(--data-urlencode "scopes=${sorted}")
  [ -n "${TAPAUTH_AGENT_NAME:-}" ] && create_args+=(--data-urlencode "agent_name=${TAPAUTH_AGENT_NAME}")
  create_args+=("${TAPAUTH_BASE}/api/v1/grants")
  local resp
  resp=$("${create_args[@]}") || die "failed to contact TapAuth"
  TAPAUTH_HTTP="${resp##*$'\n'}"
  parse_env_response "${resp%$'\n'*}"
  case "$TAPAUTH_HTTP" in
    200|201) [ -n "${TAPAUTH_GRANT_ID:-}" ] && [ -n "${TAPAUTH_GRANT_SECRET:-}" ] || die "failed to create grant" ;;
    *) die "failed to create grant (${TAPAUTH_HTTP})" ;;
  esac
  save
}

emit_url() {
  echo "Approve access: ${TAPAUTH_APPROVE_URL:-${TAPAUTH_BASE}/approve/${TAPAUTH_GRANT_ID}}"
  echo ""
  if [ "${TAPAUTH_STATUS:-}" = "expired" ]; then
    echo "Show this URL to the user. Once they re-authorize, run with --token to get the bearer token."
  else
    echo "Show this URL to the user. Once they approve, run with --token to get the bearer token."
  fi
  exit 0
}

TAPAUTH_GRANT_ID="" TAPAUTH_GRANT_SECRET="" TAPAUTH_APPROVE_URL=""
[ -f "$env_file" ] && parse_env_response "$(cat "$env_file")"

if [ -z "${TAPAUTH_GRANT_ID:-}" ] || [ -z "${TAPAUTH_GRANT_SECRET:-}" ]; then
  [ "$mode" = "token" ] && die "run without --token first to get an approval URL"
  create_grant
  emit_url
fi

fetch
case "$TAPAUTH_HTTP:${TAPAUTH_STATUS:-}" in
  200:*) ready ;;
  202:*) ;;
  410:expired)
    [ "$mode" = "token" ] && die "cached grant expired; run without --token first to re-authorize it"
    emit_url
    ;;
  401:*|404:*|410:revoked|410:denied|410:link_expired|410:*)
    [ "$mode" = "token" ] && die "cached grant is no longer usable; run without --token first to get a new approval URL"
    create_grant
    emit_url
    ;;
  *) die "grant fetch failed (${TAPAUTH_HTTP})" ;;
esac

# --- URL mode ---
[ "$mode" = "url" ] && emit_url

# --- Poll until approved (600s timeout) ---
poll_start=$SECONDS
while true; do
  sleep 5
  [ $((SECONDS - poll_start)) -ge 600 ] && die "timed out"
  echo "Waiting for approval... ($((SECONDS - poll_start))s)" >&2
  fetch
  [ "$TAPAUTH_HTTP" = "200" ] && { echo "Approved! Fetching token..." >&2; ready; }
  case "$TAPAUTH_HTTP:${TAPAUTH_STATUS:-}" in
    202:*) ;;
    410:expired) die "grant expired; run without --token first to re-authorize it" ;;
    410:revoked|410:denied|410:link_expired) die "${TAPAUTH_STATUS}" ;;
    401:*|404:*|410:*) die "grant is no longer usable; run without --token first to get a new approval URL" ;;
    *) die "grant fetch failed (${TAPAUTH_HTTP})" ;;
  esac
done
