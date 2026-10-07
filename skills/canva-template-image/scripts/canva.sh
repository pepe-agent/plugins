#!/usr/bin/env bash
# Fill a Canva brand template and export it as an image, through the Canva Connect API.
# Usage: canva.sh auth-url | auth-code CODE [STATE] | status | templates [QUERY] | fields TEMPLATE_ID
#        | upload SOURCE [NAME] | fill TEMPLATE_ID [--title T] --text NAME=VALUE ... --image NAME=ASSET_ID ...
#        | export DESIGN_ID [--format png|jpg|pdf] [--out PATH] | make TEMPLATE_ID ... [--format F] [--out P]
# Env: CANVA_CLIENT_ID, CANVA_CLIENT_SECRET, CANVA_REDIRECT_URI, optional CANVA_API_URL, CANVA_STATE_DIR.
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true
umask 077

API=${CANVA_API_URL:-https://api.canva.com/rest/v1}
STATE=${CANVA_STATE_DIR:-$HOME/.pepe-canva}
TOKENS=$STATE/tokens.json
AUTHORIZE_URL=https://www.canva.com/api/oauth/authorize
SCOPES="design:content:read design:content:write brandtemplate:meta:read brandtemplate:content:read asset:read asset:write"
POLL_TRIES=${CANVA_POLL_TRIES:-30}
POLL_SLEEP=${CANVA_POLL_SLEEP:-2}
ACCESS="" REFRESH=""

# Anything printed passes through here: secrets removed, one line, bounded.
redact() {
  local s=$1 t
  for t in "$ACCESS" "$REFRESH" "${CANVA_CLIENT_SECRET:-}"; do
    [ -n "$t" ] && s=${s//"$t"/[redacted]}
  done
  if [ -f "$TOKENS" ]; then
    for t in $(jq -r '[.access_token, .refresh_token] | map(select(. != null)) | .[]' "$TOKENS" 2>/dev/null || true); do
      s=${s//"$t"/[redacted]}
    done
  fi
  s=$(printf '%s' "$s" | tr '\n\r\t' '   ')
  printf '%s' "${s:0:300}"
}

die() { printf 'canva: %s\n' "$(redact "$*")" >&2; exit 1; }

need_env() { local v; for v in "$@"; do [ -n "${!v:-}" ] || die "$v is not set"; done; }

# Strict patterns, checked before anything goes into a URL, a header or JSON.
valid() { [[ $2 =~ $1 ]] || die "invalid $3"; }
ID_RE='^[A-Za-z0-9_-]{1,64}$'
NAME_RE='^[A-Za-z0-9_. -]{1,100}$'
valid_id() { valid "$ID_RE" "$1" "$2"; }

api_error() { # body of a failed response -> short message
  local m
  m=$(printf '%s' "$1" | jq -r '[.code, .message, .error_description, .error] | map(select(type == "string")) | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end) | join(": ")' 2>/dev/null | head -n 1 || true)
  printf '%s' "${m:-no details}"
}

# curl for the token endpoint: client id/secret and form body go through stdin, never argv.
token_request() { # form-body
  local out rc=0
  need_env CANVA_CLIENT_ID CANVA_CLIENT_SECRET
  valid '^[A-Za-z0-9_.~-]+$' "$CANVA_CLIENT_ID" "CANVA_CLIENT_ID"
  valid '^[A-Za-z0-9_.~-]+$' "$CANVA_CLIENT_SECRET" "CANVA_CLIENT_SECRET"
  out=$(printf 'user = "%s:%s"\ndata = "%s"\n' "$CANVA_CLIENT_ID" "$CANVA_CLIENT_SECRET" "$1" |
    curl -sS --fail-with-body --max-time 30 -K - "$API/oauth/token" 2>/dev/null) || rc=$?
  [ "$rc" -eq 0 ] || { [ "$rc" -eq 22 ] && die "token request refused: $(api_error "$out")"; die "could not reach Canva (curl exit $rc)"; }
  printf '%s' "$out"
}

store_tokens() { # token endpoint response
  local tmp now
  printf '%s' "$1" | jq -e '(.access_token | type == "string") and (.refresh_token | type == "string") and (.expires_in | type == "number")' >/dev/null ||
    die "unexpected answer from the token endpoint"
  now=$(date +%s)
  mkdir -p "$STATE" && chmod 700 "$STATE"
  tmp=$(mktemp "$STATE/.tokens.XXXXXX")
  printf '%s' "$1" | jq --argjson now "$now" '{access_token, refresh_token, expires_at: ($now + .expires_in)}' >"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$TOKENS"
  ACCESS=$(jq -r .access_token "$TOKENS")
  REFRESH=$(jq -r .refresh_token "$TOKENS")
}

# Sets ACCESS, refreshing (and persisting the rotated refresh token) when it expires within 60 seconds.
ensure_token() {
  local expires
  [ -f "$TOKENS" ] || die "not authorized yet: run auth-url, open the link, then auth-code"
  ACCESS=$(jq -r .access_token "$TOKENS")
  REFRESH=$(jq -r .refresh_token "$TOKENS")
  expires=$(jq -r .expires_at "$TOKENS")
  if [ $((expires - $(date +%s))) -lt 60 ]; then
    valid '^[A-Za-z0-9._~+/=-]+$' "$REFRESH" "stored refresh token, authorize again"
    store_tokens "$(token_request "grant_type=refresh_token&refresh_token=$REFRESH")"
  fi
}

# call METHOD PATH [curl args]: authenticated request, prints the JSON body.
call() {
  local method=$1 path=$2 out rc=0
  shift 2
  ensure_token
  out=$(printf 'header = "Authorization: Bearer %s"\n' "$ACCESS" |
    curl -sS --fail-with-body --max-time 60 -K - -X "$method" "$API$path" "$@" 2>/dev/null) || rc=$?
  if [ "$rc" -ne 0 ]; then
    [ "$rc" -eq 22 ] && die "Canva refused $method $path: $(api_error "$out")"
    die "could not reach Canva (curl exit $rc)"
  fi
  printf '%s' "$out"
}

call_json() { call "$1" "$2" -H 'Content-Type: application/json' --data "$3"; }

# poll PATH: waits for .job.status to leave in_progress; prints the job JSON on success.
poll() { # path what
  local i out status
  for ((i = 0; i < POLL_TRIES; i++)); do
    out=$(call GET "$1") || exit 1
    status=$(printf '%s' "$out" | jq -r '.job.status // "unknown"')
    case $status in
      success) printf '%s' "$out"; return 0 ;;
      failed) die "$2 failed: $(printf '%s' "$out" | jq -r '[.job.error.code, .job.error.message] | map(select(. != null)) | join(": ")')" ;;
    esac
    sleep "$POLL_SLEEP"
  done
  die "$2 did not finish in time"
}

cmd_auth_url() {
  local verifier state challenge enc_redirect
  need_env CANVA_CLIENT_ID CANVA_REDIRECT_URI
  valid '^[A-Za-z0-9_.~-]+$' "$CANVA_CLIENT_ID" "CANVA_CLIENT_ID"
  verifier=$(random_alnum 64)
  state=$(random_alnum 32)
  challenge=$(sha256_b64url "$verifier")
  mkdir -p "$STATE" && chmod 700 "$STATE"
  printf '%s' "$verifier" >"$STATE/pkce_verifier"
  printf '%s' "$state" >"$STATE/pkce_state"
  chmod 600 "$STATE/pkce_verifier" "$STATE/pkce_state"
  enc() { jq -rn --arg v "$1" '$v | @uri'; }
  enc_redirect=$(enc "$CANVA_REDIRECT_URI")
  printf '%s?code_challenge_method=S256&response_type=code&client_id=%s&scope=%s&code_challenge=%s&state=%s&redirect_uri=%s\n' \
    "$AUTHORIZE_URL" "$CANVA_CLIENT_ID" "$(enc "$SCOPES")" "$challenge" "$state" "$enc_redirect"
}

# Bounded read of /dev/urandom, so nothing depends on SIGPIPE to stop.
random_alnum() { head -c 2048 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c "$1"; }

sha256_b64url() {
  local hex
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "$1" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '=\n'
  else
    if command -v sha256sum >/dev/null 2>&1; then hex=$(printf '%s' "$1" | sha256sum | cut -d' ' -f1)
    else hex=$(printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1); fi
    # hex -> bytes without xxd: turn every pair into a \xHH escape for printf
    # shellcheck disable=SC2059
    printf "$(printf '%s' "$hex" | sed 's/../\\x&/g')" | base64 | tr '+/' '-_' | tr -d '=\n'
  fi
}

cmd_auth_code() {
  local code=${1:-} given_state=${2:-} verifier state
  [ -n "$code" ] || die "usage: auth-code CODE [STATE]"
  if [[ $code == http* ]]; then # the whole redirect URL was pasted
    given_state=$(printf '%s' "$code" | sed -n 's/.*[?&]state=\([^&#]*\).*/\1/p')
    code=$(printf '%s' "$code" | sed -n 's/.*[?&]code=\([^&#]*\).*/\1/p')
  fi
  valid '^[A-Za-z0-9._~+/=-]+$' "$code" "authorization code"
  [ -f "$STATE/pkce_verifier" ] || die "no pending authorization: run auth-url first"
  verifier=$(cat "$STATE/pkce_verifier")
  state=$(cat "$STATE/pkce_state")
  if [ -n "$given_state" ] && [ "$given_state" != "$state" ]; then die "state does not match, run auth-url again"; fi
  need_env CANVA_REDIRECT_URI
  store_tokens "$(token_request "grant_type=authorization_code&code=$code&code_verifier=$verifier&redirect_uri=$(jq -rn --arg v "$CANVA_REDIRECT_URI" '$v | @uri')")"
  rm -f "$STATE/pkce_verifier" "$STATE/pkce_state"
  echo "authorized; tokens stored in $TOKENS"
}

cmd_status() {
  local left
  [ -f "$TOKENS" ] || { echo "not authorized: run auth-url, open the link, then auth-code"; exit 1; }
  left=$(($(jq -r .expires_at "$TOKENS") - $(date +%s)))
  echo "authorized; access token valid for $((left > 0 ? left : 0))s (refreshed automatically)"
}

cmd_templates() {
  local query=${1:-} cont="" out page
  for page in 1 2 3 4 5; do
    set -- -G --data-urlencode "dataset=non_empty" --data-urlencode "limit=50"
    [ -z "$query" ] || set -- "$@" --data-urlencode "query=$query"
    [ -z "$cont" ] || set -- "$@" --data-urlencode "continuation=$cont"
    out=$(call GET /brand-templates "$@")
    printf '%s' "$out" | jq -r '.items[] | "\(.id)\t\(.title | gsub("[\\n\\r\\t]"; " "))"'
    cont=$(printf '%s' "$out" | jq -r '.continuation // empty')
    [ -n "$cont" ] || break
  done
}

cmd_fields() {
  local id=${1:-}
  valid_id "$id" "template id"
  call GET "/brand-templates/$id/dataset" | jq -r '.dataset // {} | to_entries[] | "\(.key | gsub("[\\n\\r\\t]"; " "))\t\(.value.type)"'
}

cmd_upload() {
  local src=${1:-} name=${2:-} body out job
  [ -n "$src" ] || die "usage: upload SOURCE [NAME]"
  if [ -z "$name" ]; then
    name=$(printf '%s' "$(basename "${src%%\?*}")" | tr -c 'A-Za-z0-9 _.()-' '_')
    name=${name:0:50}
    [ -n "$name" ] || name=upload
  fi
  valid '^[A-Za-z0-9 _.()-]{1,50}$' "$name" "asset name"
  if [[ $src == https://* ]]; then
    [ "${#src}" -le 2048 ] && [[ $src != *[[:space:]]* ]] || die "invalid asset URL"
    body=$(jq -nc --arg name "$name" --arg url "$src" '{name: $name, url: $url}')
    job=$(call_json POST /url-asset-uploads "$body" | jq -r '.job.id // empty')
    [ -n "$job" ] || die "Canva did not return an upload job"
    valid_id "$job" "job id"
    out=$(poll "/url-asset-uploads/$job" "asset upload")
  else
    [ -f "$src" ] || die "not an https URL and not a file: $src"
    job=$(call POST /asset-uploads \
      -H "Asset-Upload-Metadata: $(jq -nc --arg n "$(printf '%s' "$name" | base64 | tr -d '\n')" '{name_base64: $n}')" \
      -H 'Content-Type: application/octet-stream' --data-binary "@$src" | jq -r '.job.id // empty')
    [ -n "$job" ] || die "Canva did not return an upload job"
    valid_id "$job" "job id"
    out=$(poll "/asset-uploads/$job" "asset upload")
  fi
  printf '%s' "$out" | jq -r '.job.asset.id // empty'
}

# parse_opts ARGS...: fills TITLE, DATA (JSON), FORMAT and OUT.
parse_opts() {
  local pair key val
  while [ $# -gt 0 ]; do
    case $1 in
      --title) [ $# -ge 2 ] || die "--title needs a value"; TITLE=$2; shift 2 ;;
      --text | --image)
        [ $# -ge 2 ] && [[ $2 == *=* ]] || die "$1 needs NAME=VALUE"
        pair=$2; key=${pair%%=*}; val=${pair#*=}
        valid "$NAME_RE" "$key" "field name"
        if [ "$1" = "--text" ]; then
          DATA=$(jq -c --arg k "$key" --arg v "$val" '. + {($k): {type: "text", text: $v}}' <<<"$DATA")
        else
          valid_id "$val" "asset id for $key"
          DATA=$(jq -c --arg k "$key" --arg v "$val" '. + {($k): {type: "image", asset_id: $v}}' <<<"$DATA")
        fi
        shift 2 ;;
      --format) [ "$WITH_EXPORT" = 1 ] && [ $# -ge 2 ] || die "unexpected option --format"; FORMAT=$2; shift 2 ;;
      --out) [ "$WITH_EXPORT" = 1 ] && [ $# -ge 2 ] || die "unexpected option --out"; OUT=$2; shift 2 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [ "${#TITLE}" -le 255 ] || die "title is longer than 255 characters"
  case $FORMAT in png | jpg | pdf) ;; *) die "format must be png, jpg or pdf" ;; esac
}

# fill_job TEMPLATE_ID: sets DESIGN_ID and DESIGN_URL from the current TITLE and DATA.
fill_job() {
  local id=$1 dataset bad body job out
  [ "$DATA" != "{}" ] || die "give at least one --text NAME=VALUE or --image NAME=ASSET_ID"
  dataset=$(call GET "/brand-templates/$id/dataset")
  bad=$(jq -rn --argjson ds "$dataset" --argjson d "$DATA" '
    ($ds.dataset // {}) as $f
    | [$d | to_entries[] | select(($f[.key].type // "") != .value.type) | "\(.value.type) field \"\(.key)\""][0] // empty')
  if [ -n "$bad" ]; then
    die "the template has no $bad (fields: $(printf '%s' "$dataset" | jq -r '[.dataset // {} | to_entries[] | "\(.key) (\(.value.type))"] | join(", ")'))"
  fi
  body=$(jq -nc --arg id "$id" --arg title "$TITLE" --argjson data "$DATA" \
    '{type: "create_from_brand_template", brand_template_id: $id, data: $data} + (if $title == "" then {} else {title: $title} end)')
  job=$(call_json POST /autofills "$body" | jq -r '.job.id // empty')
  [ -n "$job" ] || die "Canva did not return an autofill job"
  valid_id "$job" "job id"
  out=$(poll "/autofills/$job" "autofill")
  DESIGN_ID=$(printf '%s' "$out" | jq -r '.job.result.design.id // empty')
  DESIGN_URL=$(printf '%s' "$out" | jq -r '.job.result.design.url // .job.result.design.urls.edit_url // empty')
  [ -n "$DESIGN_ID" ] || die "autofill finished without a design"
  valid_id "$DESIGN_ID" "design id from Canva"
}

# export_job DESIGN_ID: downloads the first exported page to OUT (or ./canva-ID.ext) and prints the path.
export_job() {
  local id=$1 job out url dest tmp rc=0
  job=$(call_json POST /exports "$(jq -nc --arg id "$id" --arg t "$FORMAT" \
    '{design_id: $id, format: ({type: $t} + (if $t == "jpg" then {quality: 90} else {} end))}')" | jq -r '.job.id // empty')
  [ -n "$job" ] || die "Canva did not return an export job"
  valid_id "$job" "job id"
  out=$(poll "/exports/$job" "export")
  url=$(printf '%s' "$out" | jq -r '.job.urls[0] // empty')
  [ -n "$url" ] || die "export finished without a file"
  [[ $url == https://* || ( $API == http://127.0.0.1* && $url == http://127.0.0.1* ) ]] || die "export link is not https"
  dest=${OUT:-./canva-$id.$FORMAT}
  tmp=$(mktemp "${dest}.XXXXXX") || die "cannot write to $dest"
  # The download link is pre-signed: no token goes with it.
  curl -sS --fail --max-time 120 -L -o "$tmp" "$url" 2>/dev/null || rc=$?
  if [ "$rc" -ne 0 ]; then rm -f "$tmp"; die "could not download the exported file (curl exit $rc)"; fi
  chmod 644 "$tmp"
  mv "$tmp" "$dest"
  echo "$dest"
}

TITLE="" DATA="{}" FORMAT=png OUT="" WITH_EXPORT=0 DESIGN_ID="" DESIGN_URL=""

cmd=${1:-}
[ $# -eq 0 ] || shift
case $cmd in
  auth-url) cmd_auth_url ;;
  auth-code) cmd_auth_code "$@" ;;
  status) cmd_status ;;
  templates) cmd_templates "$@" ;;
  fields) cmd_fields "$@" ;;
  upload) cmd_upload "$@" ;;
  fill | make)
    tid=${1:-}
    valid_id "$tid" "template id"
    shift
    if [ "$cmd" = make ]; then WITH_EXPORT=1; fi
    parse_opts "$@"
    fill_job "$tid"
    echo "design_id: $DESIGN_ID"
    echo "edit_url: $DESIGN_URL"
    if [ "$cmd" = make ]; then export_job "$DESIGN_ID"; fi
    ;;
  export)
    did=${1:-}
    valid_id "$did" "design id"
    shift
    WITH_EXPORT=1
    parse_opts "$@"
    [ "$DATA" = "{}" ] && [ -z "$TITLE" ] || die "export takes only --format and --out"
    export_job "$did"
    ;;
  *) die "usage: canva.sh auth-url | auth-code | status | templates | fields | upload | fill | export | make" ;;
esac
