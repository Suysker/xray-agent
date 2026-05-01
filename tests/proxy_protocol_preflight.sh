#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export XRAY_AGENT_PROJECT_ROOT="${ROOT_DIR}"

source "${ROOT_DIR}/install.sh"

if ! command -v jq >/dev/null 2>&1 && command -v jq.exe >/dev/null 2>&1; then
    jq() {
        local arg converted_args=()
        for arg in "$@"; do
            if [[ "${arg}" == /* && -e "${arg}" ]] && command -v wslpath >/dev/null 2>&1; then
                converted_args+=("$(wslpath -w "${arg}")")
            else
                converted_args+=("${arg}")
            fi
        done
        jq.exe "${converted_args[@]}" | tr -d '\r'
    }
fi

xray_agent_port_owner() {
    printf '%s\n' "${XRAY_AGENT_TEST_PORT443_OWNER:-empty}"
}

handleNginx() { :; }
reloadCore() { :; }

domain="example.com"

setup_case() {
    TEST_TMP="$(mktemp -d)"
    export XRAY_AGENT_PROFILE_DIR="${TEST_TMP}/profiles"
    export XRAY_AGENT_NGINX_SCAN_DIRS="${TEST_TMP}/scan"
    export XRAY_AGENT_NGINX_BACKUP_DIR="${TEST_TMP}/backup"
    nginxConfigPath="${TEST_TMP}/nginx/"
    configPath="${TEST_TMP}/xray/conf/"
    mkdir -p "${XRAY_AGENT_PROFILE_DIR}/nginx" "${XRAY_AGENT_NGINX_SCAN_DIRS}" "${nginxConfigPath}" "${configPath}" "${XRAY_AGENT_NGINX_BACKUP_DIR}"
}

teardown_case() {
    rm -rf "${TEST_TMP}"
}

recommendation() {
    xray_agent_nginx_proxy_protocol_recommendation_json | jq -r '.recommended'
}

assert_recommendation() {
    local name="$1"
    local expected="$2"
    local actual
    actual="$(recommendation)"
    if [[ "${actual}" != "${expected}" ]]; then
        echo "FAIL ${name}: expected ${expected}, got ${actual}" >&2
        xray_agent_nginx_proxy_protocol_recommendation_json >&2
        exit 1
    fi
    echo "ok ${name}"
}

setup_case
assert_recommendation "clean host defaults on" "on"
teardown_case

setup_case
cat >"${nginxConfigPath}alone.stream" <<'EOF'
stream {
    server {
        listen 443;
        proxy_protocol on;
    }
}
EOF
assert_recommendation "existing alone.stream on stays on" "on"
teardown_case

setup_case
cat >"${nginxConfigPath}alone.stream" <<'EOF'
stream {
    server {
        listen 443;
    }
}
EOF
assert_recommendation "existing alone.stream without proxy stays off" "off"
teardown_case

setup_case
cat >"${XRAY_AGENT_NGINX_SCAN_DIRS}/panel.conf" <<'EOF'
server {
    listen 443 ssl proxy_protocol;
    server_name www.example.com;
}
EOF
assert_recommendation "panel proxy_protocol listen defaults on" "on"
teardown_case

setup_case
cat >"${XRAY_AGENT_NGINX_SCAN_DIRS}/panel.conf" <<'EOF'
server {
    listen 443 ssl proxy_protocol;
    server_name www.example.com;
}
EOF
xray_agent_nginx_save_reverse_proxy_json "$(jq -nc '{
  version:1,
  frontdoor:{proxy_protocol:"auto",last_reason:""},
  default_upstream:{url:"https://huggingface.co"},
  sites:[
    {server_name:"legacy.example.com",mode:"stream_tls",upstream:"127.0.0.1:9443",proxy_protocol:"unknown",enabled:true}
  ]
}')"
assert_recommendation "panel proxy_protocol priority beats unknown registered backend" "on"
teardown_case

setup_case
xray_agent_nginx_save_reverse_proxy_json "$(jq -nc '{
  version:1,
  frontdoor:{proxy_protocol:"auto",last_reason:""},
  default_upstream:{url:"https://huggingface.co"},
  sites:[
    {server_name:"a.example.com",mode:"stream_tls",upstream:"127.0.0.1:8443",proxy_protocol:"supported",enabled:true},
    {server_name:"b.example.com",mode:"stream_tls",upstream:"127.0.0.1:9443",proxy_protocol:"supported",enabled:true}
  ]
}')"
assert_recommendation "all registered https backends supported defaults on" "on"
teardown_case

setup_case
xray_agent_nginx_save_reverse_proxy_json "$(jq -nc '{
  version:1,
  frontdoor:{proxy_protocol:"auto",last_reason:""},
  default_upstream:{url:"https://huggingface.co"},
  sites:[
    {server_name:"a.example.com",mode:"stream_tls",upstream:"127.0.0.1:8443",proxy_protocol:"supported",enabled:true},
    {server_name:"b.example.com",mode:"stream_tls",upstream:"127.0.0.1:9443",proxy_protocol:"unknown",enabled:true}
  ]
}')"
assert_recommendation "any unknown https backend defaults off" "off"
teardown_case

setup_case
xray_agent_nginx_save_reverse_proxy_json "$(jq -nc '{
  version:1,
  frontdoor:{proxy_protocol:"auto",last_reason:""},
  default_upstream:{url:"https://huggingface.co"},
  sites:[
    {server_name:"example.com",mode:"http_fallback",upstream:"http://127.0.0.1:8080",host:"example.com",enabled:true}
  ]
}')"
assert_recommendation "only http fallback defaults on" "on"
teardown_case

setup_case
cat >"${XRAY_AGENT_NGINX_SCAN_DIRS}/ordinary.conf" <<'EOF'
server {
    listen 443 ssl;
    server_name www.example.com;
}
EOF
assert_recommendation "ordinary panel https defaults off" "off"
teardown_case

setup_case
panel_file="${XRAY_AGENT_NGINX_SCAN_DIRS}/standalone-proxy-directive.conf"
cat >"${panel_file}" <<'EOF'
server {
    listen 443 ssl;
    server_name www.example.com;
    proxy_protocol on;
}
EOF
panel_before="$(cat "${panel_file}")"
assert_recommendation "standalone proxy_protocol directive without listen proxy defaults off" "off"
panel_after="$(cat "${panel_file}")"
if [[ "${panel_before}" != "${panel_after}" ]]; then
    echo "FAIL third-party config was modified during preflight" >&2
    exit 1
fi
echo "ok third-party configs are read-only during preflight"
teardown_case

setup_case
cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'EOF'
{
  "inbounds": [
    {
      "tag": "tls",
      "streamSettings": {
        "network": "raw",
        "sockopt": {
          "tcpNoDelay": true
        }
      }
    }
  ]
}
EOF
xray_agent_nginx_sync_xray_proxy_protocol true
if [[ "$(jq -r '.inbounds[0].streamSettings.rawSettings.acceptProxyProtocol' "${configPath}02_VLESS_TCP_inbounds.json")" != "true" ]]; then
    echo "FAIL Xray rawSettings.acceptProxyProtocol was not created" >&2
    exit 1
fi
if [[ "$(jq -r '.inbounds[0].streamSettings.sockopt.acceptProxyProtocol' "${configPath}02_VLESS_TCP_inbounds.json")" != "true" ]]; then
    echo "FAIL Xray sockopt.acceptProxyProtocol was not synced" >&2
    exit 1
fi
if [[ "$(jq -r '.inbounds[0].streamSettings.sockopt.tcpNoDelay' "${configPath}02_VLESS_TCP_inbounds.json")" != "true" ]]; then
    echo "FAIL Xray sockopt existing fields were not preserved" >&2
    exit 1
fi
echo "ok Xray proxy protocol sync creates rawSettings and preserves sockopt"
teardown_case

setup_case
path="rollback-test"
Port="31301"
RealityPort="31302"
RealityServerNames="\"reality.example.com\""
xray_agent_nginx_save_reverse_proxy_json "$(jq -nc '{
  version:1,
  frontdoor:{proxy_protocol:"off",last_reason:"before"},
  default_upstream:{url:"https://huggingface.co"},
  sites:[]
}')"
cat >"${nginxConfigPath}alone.stream" <<'EOF'
old stream content
EOF
xray_agent_nginx_test_config() { return 1; }
updated_json="$(xray_agent_nginx_reverse_proxy_json | jq '.frontdoor.proxy_protocol = "on" | .frontdoor.last_reason = "rollback-test"')"
if xray_agent_nginx_apply_reverse_proxy_update "${updated_json}" auto; then
    echo "FAIL rollback test unexpectedly succeeded" >&2
    exit 1
fi
if [[ "$(xray_agent_nginx_reverse_proxy_json | jq -r '.frontdoor.proxy_protocol')" != "off" ]]; then
    echo "FAIL reverse proxy JSON was not rolled back" >&2
    exit 1
fi
if [[ "$(cat "${nginxConfigPath}alone.stream")" != "old stream content" ]]; then
    echo "FAIL alone.stream was not rolled back" >&2
    exit 1
fi
echo "ok failed nginx apply rolls back JSON and stream config"
teardown_case
