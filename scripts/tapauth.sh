#!/usr/bin/env bash
set -euo pipefail

TAPAUTH_BASE="${TAPAUTH_BASE_URL:-https://tapauth.ai}"
TAPAUTH_DIR="${TAPAUTH_HOME:-${CLAUDE_PLUGIN_DATA:-./.tapauth}}"
mkdir -p "$TAPAUTH_DIR" && chmod 700 "$TAPAUTH_DIR"

mode="url"
if [ "${1:-}" = "--token" ]; then mode="token"; shift; fi

provider="${1:-}"; scopes="${2:-}"
[ -z "$provider" ] && { echo "usage: tapauth [--token] <provider> [scopes]" >&2; exit 1; }
[[ "$provider" =~ ^[a-z][a-z0-9_]*$ ]] || { echo "tapauth: invalid provider name" >&2; exit 1; }

if [ -n "$scopes" ]; then
  sorted=$(echo "$scopes" | tr "," "\n" | sort | tr "\n" "," | sed "s/,$//")
else
  sorted=""
fi
safe_name="${provider}-${sorted:-all}"
env_file="${TAPAUTH_DIR}/$(echo "$safe_name" | tr '/:' '__').env"

save() {
  install -m 600 /dev/null "$env_file"
  cat > "$env_file" <<EOF
TAPAUTH_TOKEN=${TAPAUTH_TOKEN:-}
TAPAUTH_GRANT_ID=${TAPAUTH_GRANT_ID:-}
TAPAUTH_GRANT_SECRET=${TAPAUTH_GRANT_SECRET:-}
TAPAUTH_EXPIRES=${TAPAUTH_EXPIRES:-}
EOF
}

fetch() {
  TAPAUTH_TOKEN="" TAPAUTH_STATUS=""
  local resp http_code body
  resp=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer ${TAPAUTH_GRANT_SECRET}" \
    -H 'Accept: text/plain' "${TAPAUTH_BASE}/api/v1/grants/${TAPAUTH_GRANT_ID}")
  http_code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  eval "$(echo "$body" | grep '^TAPAUTH_[A-Z_]*=')" 2>/dev/null || true
}

# --- Cached flow ---
if [ -f "$env_file" ]; then
  source "$env_file"
  if [ -n "${TAPAUTH_EXPIRES:-}" ] && [ "$(date +%s)" -lt "${TAPAUTH_EXPIRES:-0}" ]; then
    if [ "$mode" = "url" ]; then
      echo "Already authorized for ${provider}${sorted:+ ($sorted)}. Use --token to get the bearer token."
      exit 0
    fi
    echo "${TAPAUTH_TOKEN:-}"; exit 0
  fi
  # Token expired — try refresh
  fetch
  if [ -n "${TAPAUTH_TOKEN:-}" ]; then
    save
    if [ "$mode" = "url" ]; then
      echo "Already authorized for ${provider}${sorted:+ ($sorted)}. Use --token to get the bearer token."
      exit 0
    fi
    echo "$TAPAUTH_TOKEN"; exit 0
  fi
  # Refresh failed — fall through to create a new grant
fi

# --- Grant creation ---
create_grant() {
  echo "Creating grant for ${provider}${sorted:+ ($sorted)}..." >&2
  TAPAUTH_GRANT_ID="" TAPAUTH_GRANT_SECRET="" TAPAUTH_APPROVE_URL=""
  create_args=(curl -s -w "\n%{http_code}" -X POST -H 'Accept: text/plain'
    --data-urlencode "provider=${provider}")
  [ -n "$sorted" ] && create_args+=(--data-urlencode "scopes=${sorted}")
  [ -n "${TAPAUTH_AGENT_NAME:-}" ] && create_args+=(--data-urlencode "agent_name=${TAPAUTH_AGENT_NAME}")
  create_args+=("${TAPAUTH_BASE}/api/v1/grants")
  resp=$("${create_args[@]}")
  eval "$(echo "${resp%$'\n'*}" | grep '^TAPAUTH_[A-Z_]*=')" 2>/dev/null || true
  [ -z "${TAPAUTH_GRANT_ID:-}" ] && { echo "tapauth: failed to create grant" >&2; exit 1; }
  # Save grant info so --token can pick it up
  save
}

# --- Check for pending grant (created by a prior url-mode run) ---
if [ -f "$env_file" ] && [ -z "${TAPAUTH_TOKEN:-}" ] && [ -n "${TAPAUTH_GRANT_ID:-}" ]; then
  # Pending grant exists — try fetching token first
  fetch
  if [ -n "${TAPAUTH_TOKEN:-}" ]; then
    save
    if [ "$mode" = "url" ]; then
      echo "Already authorized for ${provider}${sorted:+ ($sorted)}. Use --token to get the bearer token."
      exit 0
    fi
    echo "$TAPAUTH_TOKEN"; exit 0
  fi
  # Still pending — re-use existing grant
else
  create_grant
fi

# --- URL mode: print approval URL and exit ---
if [ "$mode" = "url" ]; then
  echo "Approve access: ${TAPAUTH_APPROVE_URL:-${TAPAUTH_BASE}/approve/${TAPAUTH_GRANT_ID}}"
  echo ""
  echo "Show this URL to the user. Once they approve, run with --token to get the bearer token."
  exit 0
fi

# --- Token mode: poll until approved ---
poll_start=$SECONDS
while true; do
  sleep 5
  [ $((SECONDS - poll_start)) -ge 600 ] && { echo "tapauth: timed out" >&2; exit 1; }
  echo "Waiting for approval... ($((SECONDS - poll_start))s)" >&2
  fetch
  [ -n "${TAPAUTH_TOKEN:-}" ] && { echo "Approved! Fetching token..." >&2; break; }
  case "${TAPAUTH_STATUS:-}" in expired|revoked|denied|link_expired) echo "tapauth: ${TAPAUTH_STATUS}" >&2; exit 1;; esac
done

save; echo "$TAPAUTH_TOKEN"
