#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export TAPAUTH_SCRIPT="${BATS_TEST_DIRNAME}/../scripts/tapauth.sh"
  export TAPAUTH_HOME="${BATS_TEST_TMPDIR}/tapauth-home"
  export TAPAUTH_BASE_URL="http://mock"
  export TAPAUTH_AGENT_NAME="bats-agent"
  export CURL_MOCK_STATE="${BATS_TEST_TMPDIR}/curl-state"
  export CURL_MOCK_RESPONSE="${BATS_TEST_TMPDIR}/curl-responses"
  export PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"
  mkdir -p "$TAPAUTH_HOME" "$CURL_MOCK_RESPONSE"
}

reset_state() {
  rm -rf "$TAPAUTH_HOME" "$CURL_MOCK_STATE" "$CURL_MOCK_RESPONSE"
  mkdir -p "$TAPAUTH_HOME" "$CURL_MOCK_RESPONSE"
}

write_cache() {
  cat > "${TAPAUTH_HOME}/github-repo.env" <<EOF
TAPAUTH_GRANT_ID=cached-id
TAPAUTH_GRANT_SECRET=cached-secret
TAPAUTH_EXPIRES=2000-01-01T00:00:00Z
EOF
}

write_response() {
  local index="$1"
  shift
  printf '%s\n' "$@" > "${CURL_MOCK_RESPONSE}/${index}.env"
}

write_response_status() {
  local index="$1"
  local http_status="$2"
  shift 2
  {
    printf 'CURL_HTTP_STATUS=%s\n' "$http_status"
    printf '%s\n' "$@"
  } > "${CURL_MOCK_RESPONSE}/${index}.env"
}

call_count() {
  wc -l < "${CURL_MOCK_STATE}/calls.log" | tr -d ' '
}

assert_call_arg() {
  grep -Fxq -- "$2" "${CURL_MOCK_STATE}/call-${1}.args"
}

assert_no_call_arg() {
  ! grep -Fxq -- "$2" "${CURL_MOCK_STATE}/call-${1}.args"
}

@test "first run creates and caches grant without polling" {
  write_response_status 1 201 \
    "TAPAUTH_GRANT_ID=new-id" \
    "TAPAUTH_GRANT_SECRET=new-secret" \
    "TAPAUTH_APPROVE_URL=http://mock/approve/new-id"

  run --separate-stderr "$TAPAUTH_SCRIPT" github repo

  [ "$status" -eq 0 ]
  [[ "$output" == *"Approve access: http://mock/approve/new-id"* ]]
  [[ "$output" == *"start --token immediately"* ]]
  [[ "$stderr" == *"Creating grant for github (repo)..."* ]]
  [ "$(call_count)" -eq 1 ]
  grep -q "TAPAUTH_GRANT_ID=new-id" "${TAPAUTH_HOME}/github-repo.env"
  grep -q "TAPAUTH_GRANT_SECRET=new-secret" "${TAPAUTH_HOME}/github-repo.env"
}

@test "--token without cached grant fails without creating a grant" {
  run --separate-stderr "$TAPAUTH_SCRIPT" --token github repo

  [ "$status" -eq 1 ]
  [ "$output" = "" ]
  [[ "$stderr" == *"run without --token first to get an approval URL"* ]]
  [ ! -f "${CURL_MOCK_STATE}/calls.log" ]
}

@test "cached active grant emits token and rewrites cache in token mode" {
  write_cache
  write_response 1 \
    "TAPAUTH_STATUS=active" \
    "TAPAUTH_TOKEN_B64=Y2FjaGVkLXRva2Vu" \
    "TAPAUTH_EXPIRES=2099-01-01T00:00:00Z"

  run --separate-stderr "$TAPAUTH_SCRIPT" --token github repo

  [ "$status" -eq 0 ]
  [ "$output" = "cached-token" ]
  [ "$stderr" = "" ]
  grep -q "TAPAUTH_GRANT_ID=cached-id" "${TAPAUTH_HOME}/github-repo.env"
  grep -q "TAPAUTH_GRANT_SECRET=cached-secret" "${TAPAUTH_HOME}/github-repo.env"
  grep -q "TAPAUTH_EXPIRES=2099-01-01T00:00:00Z" "${TAPAUTH_HOME}/github-repo.env"
}

@test "url mode with cached active grant points callers to --token" {
  write_cache
  write_response 1 \
    "TAPAUTH_STATUS=active" \
    "TAPAUTH_TOKEN_B64=Y2FjaGVkLXRva2Vu" \
    "TAPAUTH_EXPIRES=2099-01-01T00:00:00Z"

  run --separate-stderr "$TAPAUTH_SCRIPT" github repo

  [ "$status" -eq 0 ]
  [[ "$output" == *"Already authorized for github (repo). Use --token to retrieve it."* ]]
  [ "$stderr" = "" ]
}

@test "cached revoked grant requests a new approval URL in url mode" {
  write_cache
  write_response_status 1 410 "TAPAUTH_STATUS=revoked"
  write_response_status 2 201 \
    "TAPAUTH_GRANT_ID=new-id" \
    "TAPAUTH_GRANT_SECRET=new-secret" \
    "TAPAUTH_APPROVE_URL=http://mock/approve/new-id"
  write_response 3 \
    "TAPAUTH_STATUS=active" \
    "TAPAUTH_TOKEN_B64=bmV3LXRva2Vu" \
    "TAPAUTH_EXPIRES=2099-02-01T00:00:00Z"

  run --separate-stderr "$TAPAUTH_SCRIPT" github repo

  [ "$status" -eq 0 ]
  [[ "$output" == *"Approve access: http://mock/approve/new-id"* ]]
  [[ "$stderr" == *"Creating grant for github (repo)..."* ]]
  grep -q "TAPAUTH_GRANT_ID=new-id" "${TAPAUTH_HOME}/github-repo.env"
  ! grep -q "cached-id" "${TAPAUTH_HOME}/github-repo.env"

  run --separate-stderr "$TAPAUTH_SCRIPT" --token github repo

  [ "$status" -eq 0 ]
  [ "$output" = "new-token" ]
}

@test "cached invalid grant requests a new approval URL in url mode" {
  for http_status in 401 404; do
    reset_state
    write_cache
    write_response_status 1 "$http_status" '{"error":"invalid_cached_grant"}'
    write_response_status 2 201 \
      "TAPAUTH_GRANT_ID=new-${http_status}" \
      "TAPAUTH_GRANT_SECRET=new-secret" \
      "TAPAUTH_APPROVE_URL=http://mock/approve/new-${http_status}"

    run --separate-stderr "$TAPAUTH_SCRIPT" github repo

    [ "$status" -eq 0 ]
    [[ "$output" == *"Approve access: http://mock/approve/new-${http_status}"* ]]
    grep -q "TAPAUTH_GRANT_ID=new-${http_status}" "${TAPAUTH_HOME}/github-repo.env"
    ! grep -q "cached-id" "${TAPAUTH_HOME}/github-repo.env"
  done
}

@test "cached expired grant reuses its approval URL for re-authorization" {
  write_cache
  write_response_status 1 410 "TAPAUTH_STATUS=expired"

  run --separate-stderr "$TAPAUTH_SCRIPT" github repo

  [ "$status" -eq 0 ]
  [[ "$output" == *"Approve access: http://mock/approve/cached-id"* ]]
  [[ "$output" == *"re-authorization completes"* ]]
  grep -q "TAPAUTH_GRANT_ID=cached-id" "${TAPAUTH_HOME}/github-repo.env"
}

@test "token mode refuses terminal cached grants without replacing cache" {
  for grant_status in expired revoked denied link_expired; do
    reset_state
    write_cache
    write_response_status 1 410 "TAPAUTH_STATUS=${grant_status}"

    run --separate-stderr "$TAPAUTH_SCRIPT" --token github repo

    [ "$status" -eq 1 ]
    [ "$output" = "" ]
    [[ "$stderr" == *"run without --token first"* ]]
    grep -q "TAPAUTH_GRANT_ID=cached-id" "${TAPAUTH_HOME}/github-repo.env"
    [ "$(call_count)" -eq 1 ]
  done
}

@test "cached malformed token response keeps cache and fails" {
  write_cache

  run --separate-stderr "$TAPAUTH_SCRIPT" --token github repo

  [ "$status" -eq 1 ]
  [ "$output" = "" ]
  [[ "$stderr" == *"tapauth: no token in response"* ]]
  [ -f "${TAPAUTH_HOME}/github-repo.env" ]
  [ "$(call_count)" -eq 1 ]
}

@test "cached pending grant resumes polling and emits token" {
  write_cache
  write_response_status 1 202 "TAPAUTH_STATUS=pending"
  write_response 2 \
    "TAPAUTH_STATUS=active" \
    "TAPAUTH_TOKEN_B64=cGVuZGluZy10b2tlbg==" \
    "TAPAUTH_EXPIRES=2099-03-01T00:00:00Z"

  run --separate-stderr "$TAPAUTH_SCRIPT" --token github repo

  [ "$status" -eq 0 ]
  [ "$output" = "pending-token" ]
  [[ "$stderr" == *"Waiting for approval"* ]]
  grep -q "TAPAUTH_GRANT_ID=cached-id" "${TAPAUTH_HOME}/github-repo.env"
}

@test "cached pending sub-states resume polling and emit token" {
  for grant_status in pending_registration pending_consent; do
    reset_state
    write_cache
    write_response_status 1 202 "TAPAUTH_STATUS=${grant_status}"
    write_response 2 \
      "TAPAUTH_STATUS=active" \
      "TAPAUTH_TOKEN_B64=cGVuZGluZy10b2tlbg==" \
      "TAPAUTH_EXPIRES=2099-03-01T00:00:00Z"

    run --separate-stderr "$TAPAUTH_SCRIPT" --token github repo

    [ "$status" -eq 0 ]
    [ "$output" = "pending-token" ]
    [[ "$stderr" == *"Waiting for approval"* ]]
    grep -q "TAPAUTH_GRANT_ID=cached-id" "${TAPAUTH_HOME}/github-repo.env"
  done
}

@test "token polling exits promptly on denied grant" {
  write_response_status 1 201 \
    "TAPAUTH_GRANT_ID=new-id" \
    "TAPAUTH_GRANT_SECRET=new-secret" \
    "TAPAUTH_APPROVE_URL=http://mock/approve/new-id"
  write_response_status 2 202 "TAPAUTH_STATUS=pending"
  write_response_status 3 410 "TAPAUTH_STATUS=denied"

  run --separate-stderr "$TAPAUTH_SCRIPT" github repo
  [ "$status" -eq 0 ]

  run --separate-stderr "$TAPAUTH_SCRIPT" --token github repo

  [ "$status" -eq 1 ]
  [ "$output" = "" ]
  [[ "$stderr" == *"tapauth: grant denied"* ]]
  [ "$(call_count)" -eq 3 ]
}

@test "token polling terminal grant statuses exit promptly" {
  for grant_status in expired revoked link_expired; do
    reset_state
    write_response_status 1 201 \
      "TAPAUTH_GRANT_ID=new-id" \
      "TAPAUTH_GRANT_SECRET=new-secret" \
      "TAPAUTH_APPROVE_URL=http://mock/approve/new-id"
    write_response_status 2 202 "TAPAUTH_STATUS=pending"
    write_response_status 3 410 "TAPAUTH_STATUS=${grant_status}"

    run --separate-stderr "$TAPAUTH_SCRIPT" github repo
    [ "$status" -eq 0 ]

    run --separate-stderr "$TAPAUTH_SCRIPT" --token github repo

    [ "$status" -eq 1 ]
    [ "$output" = "" ]
    [[ "$stderr" == *"tapauth: grant ${grant_status}"* ]]
    [ "$(call_count)" -eq 3 ]
  done
}

@test "poll timeout branch exits with timed out" {
  write_response_status 1 201 \
    "TAPAUTH_GRANT_ID=new-id" \
    "TAPAUTH_GRANT_SECRET=new-secret" \
    "TAPAUTH_APPROVE_URL=http://mock/approve/new-id"
  write_response_status 2 202 "TAPAUTH_STATUS=pending"

  run --separate-stderr "$TAPAUTH_SCRIPT" github repo
  [ "$status" -eq 0 ]

  run --separate-stderr env TAPAUTH_POLL_TIMEOUT_SECONDS=0 "$TAPAUTH_SCRIPT" --token github repo

  [ "$status" -eq 1 ]
  [ "$output" = "" ]
  [[ "$stderr" == *"tapauth: timed out"* ]]
  [ "$(call_count)" -eq 2 ]
}

@test "secret first-run sends secret fields and token mode emits secret" {
  write_response_status 1 201 \
    "TAPAUTH_GRANT_ID=secret-id" \
    "TAPAUTH_GRANT_SECRET=secret-grant-secret" \
    "TAPAUTH_APPROVE_URL=http://mock/approve/secret-id"
  write_response 2 \
    "TAPAUTH_STATUS=active" \
    "TAPAUTH_TOKEN_B64=c2VjcmV0LXRva2Vu" \
    "TAPAUTH_EXPIRES=2099-04-01T00:00:00Z"

  run --separate-stderr "$TAPAUTH_SCRIPT" secret "Database password" "^demo-" "starts with demo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Approve secret request: http://mock/approve/secret-id"* ]]
  [[ "$stderr" == *"Creating secret request..."* ]]
  assert_call_arg 1 "provider=secret"
  assert_call_arg 1 "agent_name=bats-agent"
  assert_call_arg 1 "secret_description=Database password"
  assert_call_arg 1 "validation_regex=^demo-"
  assert_call_arg 1 "validation_hint=starts with demo"
  assert_no_call_arg 1 "scopes="

  run --separate-stderr "$TAPAUTH_SCRIPT" --token secret "Database password" "^demo-" "starts with demo"

  [ "$status" -eq 0 ]
  [ "$output" = "secret-token" ]
}
