#!/usr/bin/env bash
set -euo pipefail

TAPAUTH_BASE="${TAPAUTH_BASE_URL:-https://tapauth.ai}"
TAPAUTH_AGENT="${TAPAUTH_AGENT_NAME:-tapauth-skill}"
if [ -n "${TAPAUTH_HOME:-}" ]; then
  TAPAUTH_DIR="$TAPAUTH_HOME"
elif [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
  TAPAUTH_DIR="$CLAUDE_PLUGIN_DATA"
else
  TAPAUTH_DIR="./.tapauth"
fi
mkdir -p "$TAPAUTH_DIR" && chmod 700 "$TAPAUTH_DIR"

emit_token() {
  [ -n "${TAPAUTH_TOKEN_B64:-}" ] || { echo "tapauth: no token in response" >&2; exit 1; }
  printf '%s' "$TAPAUTH_TOKEN_B64" | base64 --decode 2>/dev/null || printf '%s' "$TAPAUTH_TOKEN_B64" | base64 -D
  printf '\n'
  exit 0
}

parse_env_response() {
  while IFS='=' read -r key value; do
    value="${value%$'\r'}"
    case "$key" in
      TAPAUTH_GRANT_ID)     TAPAUTH_GRANT_ID="$value" ;;
      TAPAUTH_GRANT_SECRET) TAPAUTH_GRANT_SECRET="$value" ;;
      TAPAUTH_APPROVE_URL)  TAPAUTH_APPROVE_URL="$value" ;;
      TAPAUTH_STATUS)       TAPAUTH_STATUS="$value" ;;
      TAPAUTH_EXPIRES)      TAPAUTH_EXPIRES="$value" ;;
      TAPAUTH_TOKEN_B64)    TAPAUTH_TOKEN_B64="$value" ;;
    esac
  done <<< "$1"
}

provider="${1:-}"
raw_scopes="${2:-}"
validation_regex="${3:-}"
validation_hint="${4:-}"

if [ -z "${provider:-}" ]; then
  echo "usage: tapauth <provider> <scopes> | tapauth secret <description> [validation_regex] [validation_hint]" >&2
  echo "  providers: google, github, linear, vercel, slack, notion, asana, sentry, discord, secret" >&2
  exit 1
fi

if [ "$provider" = "secret" ]; then
  if [ -z "${raw_scopes:-}" ]; then
    echo "tapauth: description is required for secret" >&2
    echo "usage: tapauth secret <description> [validation_regex] [validation_hint]" >&2
    exit 1
  fi
  secret_description="$raw_scopes"
  sorted_scopes=""
  safe_scopes=$(printf '%s' "secret-${secret_description}-${validation_regex}-${validation_hint}" | sed 's/[^A-Za-z0-9._-]/_/g' | cut -c1-180)
else
  if [ -z "${raw_scopes:-}" ]; then
    echo "tapauth: scopes are required for provider '$provider'" >&2
    echo "usage: tapauth <provider> <scopes>" >&2
    exit 1
  fi
  scopes="$raw_scopes"
  sorted_scopes=$(echo "$scopes" | tr "," "\n" | sort | tr "\n" "," | sed "s/,$//")
  safe_scopes=$(echo "$sorted_scopes" | tr '/:' '__')
fi
env_file="${TAPAUTH_DIR}/${provider}-${safe_scopes}.env"

# --- Cached flow ---
if [ -f "$env_file" ]; then
  TAPAUTH_GRANT_ID="" TAPAUTH_GRANT_SECRET="" TAPAUTH_EXPIRES="" TAPAUTH_TOKEN_B64=""
  parse_env_response "$(cat "$env_file")"
  # Refresh
  TAPAUTH_TOKEN_B64="" TAPAUTH_EXPIRES=""
  resp="$(curl -sf -H "Authorization: Bearer ${TAPAUTH_GRANT_SECRET}" \
    -H 'Accept: text/plain' "${TAPAUTH_BASE}/api/v1/grants/${TAPAUTH_GRANT_ID}" || true)"
  parse_env_response "$resp"
  if [ -n "${TAPAUTH_TOKEN_B64:-}" ]; then
    install -m 600 /dev/null "$env_file"
    cat > "$env_file" <<EOF
TAPAUTH_GRANT_ID=${TAPAUTH_GRANT_ID}
TAPAUTH_GRANT_SECRET=${TAPAUTH_GRANT_SECRET}
TAPAUTH_EXPIRES=${TAPAUTH_EXPIRES:-}
EOF
    emit_token
  fi
  echo "tapauth: token refresh failed" >&2
  exit 1
fi

# --- First-run flow ---
if [ "$provider" = "secret" ]; then
  echo "Creating secret request..." >&2
else
  echo "Creating grant for ${provider} (${sorted_scopes})..." >&2
fi
TAPAUTH_GRANT_ID="" TAPAUTH_GRANT_SECRET="" TAPAUTH_APPROVE_URL=""
create_args=(curl -sf -X POST -H 'Accept: text/plain'
  --data-urlencode "provider=${provider}"
  --data-urlencode "agent_name=${TAPAUTH_AGENT}")
if [ "$provider" = "secret" ]; then
  create_args+=(--data-urlencode "secret_description=${secret_description}")
  [ -n "$validation_regex" ] && create_args+=(--data-urlencode "validation_regex=${validation_regex}")
  [ -n "$validation_hint" ] && create_args+=(--data-urlencode "validation_hint=${validation_hint}")
else
  create_args+=(--data-urlencode "scopes=${sorted_scopes}")
fi
create_args+=("${TAPAUTH_BASE}/api/v1/grants")
resp="$("${create_args[@]}" || true)"
parse_env_response "$resp"
if [ -z "${TAPAUTH_GRANT_ID:-}" ] || [ -z "${TAPAUTH_GRANT_SECRET:-}" ]; then
  echo "tapauth: failed to create grant" >&2
  exit 1
fi
if [ "$provider" = "secret" ]; then
  echo "Approve secret request: ${TAPAUTH_APPROVE_URL:-}" >&2
else
  echo "Approve access: ${TAPAUTH_APPROVE_URL:-}" >&2
fi

# Poll — same endpoint
poll_start=$SECONDS
while true; do
  sleep 2
  elapsed=$((SECONDS - poll_start))
  [ "$elapsed" -ge 600 ] && { echo "tapauth: timed out" >&2; exit 1; }
  echo "Waiting for approval... (${elapsed}s)" >&2
  TAPAUTH_TOKEN_B64=""
  resp="$(curl -sf -H "Authorization: Bearer ${TAPAUTH_GRANT_SECRET}" \
    -H 'Accept: text/plain' "${TAPAUTH_BASE}/api/v1/grants/${TAPAUTH_GRANT_ID}" || true)"
  parse_env_response "$resp"
  [ -n "${TAPAUTH_TOKEN_B64:-}" ] && break
  # Check for terminal error
  case "${TAPAUTH_STATUS:-}" in
    expired|revoked|denied|link_expired) echo "tapauth: grant ${TAPAUTH_STATUS}" >&2; exit 1 ;;
  esac
done

# Cache
install -m 600 /dev/null "$env_file"
cat > "$env_file" <<EOF
TAPAUTH_GRANT_ID=${TAPAUTH_GRANT_ID}
TAPAUTH_GRANT_SECRET=${TAPAUTH_GRANT_SECRET}
TAPAUTH_EXPIRES=${TAPAUTH_EXPIRES:-}
EOF
emit_token
