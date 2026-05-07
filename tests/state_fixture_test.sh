#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

source ./install.sh >/dev/null 2>&1

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    [[ "${actual}" == "${expected}" ]] || fail "${message}: expected [${expected}], got [${actual}]"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    [[ "${haystack}" == *"${needle}"* ]] || fail "${message}: missing [${needle}]"
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    [[ "${haystack}" != *"${needle}"* ]] || fail "${message}: unexpected [${needle}]"
}

jq() {
    if [[ "$*" == "-nc []" ]]; then
        printf '[]\n'
        return 0
    fi
    if [[ "$1" == "-nc" && "$2" == "--arg" && "$3" == "xhttpDest" ]]; then
        printf '[{"dest":"%s","xver":0}]\n' "$4"
        return 0
    fi
    command jq "$@"
}

xray_agent_loopback_endpoint() {
    printf '127.0.0.1:%s\n' "$1"
}

xray_agent_port_owner() {
    printf '空闲\n'
}

allowPort() {
    :
}

checkPort() {
    :
}

TEST_ROOT=
reset_fixture() {
    TEST_ROOT="$(mktemp -d)"
    XRAY_AGENT_ETC_DIR="${TEST_ROOT}/etc/xray-agent"
    XRAY_AGENT_TLS_DIR="${XRAY_AGENT_ETC_DIR}/tls"
    XRAY_AGENT_XRAY_DIR="${XRAY_AGENT_ETC_DIR}/xray"
    XRAY_AGENT_XRAY_CONF_DIR="${XRAY_AGENT_XRAY_DIR}/conf"
    XRAY_AGENT_XRAY_BINARY="${XRAY_AGENT_XRAY_DIR}/xray"
    configPath="${XRAY_AGENT_XRAY_CONF_DIR}/"
    ctlPath="${XRAY_AGENT_XRAY_BINARY}"
    totalProgress=1
    nginxConfigPath="${TEST_ROOT}/nginx/conf.d/"
    XRAY_AGENT_ADGUARD_HOME_DIR="${TEST_ROOT}/AdGuardHome"
    XRAY_AGENT_ADGUARD_ACTIVE_OVERRIDE=
    XRAY_AGENT_INSTALL_STREAM_ONLY=false
    XRAY_AGENT_FORCE_SHARED_FRONTDOOR=false
    XRAY_AGENT_SHARED_FRONTDOOR_PORT_PREPARED=
    XRAY_AGENT_TEST_REALITY_TLS_PING_OUTPUT=
    mkdir -p "${XRAY_AGENT_TLS_DIR}" "${XRAY_AGENT_XRAY_CONF_DIR}" "${nginxConfigPath}" "${XRAY_AGENT_XRAY_DIR}"
    : >"${XRAY_AGENT_XRAY_BINARY}"
}

touch_inbound() {
    : >"${XRAY_AGENT_XRAY_CONF_DIR}/$1"
}

reset_fixture
readInstallType
assert_eq "" "${coreInstallType:-}" "uninstalled state"

touch_inbound "02_VLESS_TCP_inbounds.json"
rm -f "${XRAY_AGENT_XRAY_BINARY}"
readInstallType
assert_eq "1" "${coreInstallType:-}" "tls-only state"
: >"${XRAY_AGENT_XRAY_BINARY}"

reset_fixture
touch_inbound "07_VLESS_Reality_TCP_inbounds.json"
readInstallType
assert_eq "2" "${coreInstallType:-}" "reality-only state"

touch_inbound "02_VLESS_TCP_inbounds.json"
readInstallType
assert_eq "3" "${coreInstallType:-}" "combined tls+reality state"

menu_output="$(xray_agent_print_install_menu_items)"
assert_contains "${menu_output}" "1.重新安装TLS套餐" "combined menu shows reinstall tls"
assert_contains "${menu_output}" "2.重新安装Reality套餐" "combined menu shows reinstall reality"

Port=443
RealityPort=
reuse443=
XRAY_AGENT_INSTALL_STREAM_ONLY=false
readInstallProtocolType
customPortFunction "Reality" </dev/null >/dev/null
assert_eq "y" "${reuse443}" "combined install forces shared frontdoor"
assert_eq "true" "${XRAY_AGENT_INSTALL_STREAM_ONLY}" "combined install schedules stream-only nginx"
assert_eq "31301" "${Port}" "combined install moves tls backend off 443"
assert_eq "31302" "${RealityPort}" "combined install uses reality backend port"

profile_steps="$(grep '^steps=' profiles/install/reality_vision_xhttp.profile)"
assert_not_contains "${profile_steps}" "update_nginx_reality" "reality profile does not update nginx"
assert_not_contains "${profile_steps}" "init_tls_nginx" "reality profile does not initialize nginx tls"
assert_not_contains "${profile_steps}" "install_tls" "reality profile does not install tls certificate"
assert_not_contains "${profile_steps}" "配置镜像站点" "reality profile does not render mirror-site step"
assert_contains "${profile_steps}" "render_reality_bundle,reload_core,optional_hysteria2" "reality profile asks hysteria2 only after main reload"
assert_not_contains "${profile_steps}" "optional_hysteria2,render_reality_bundle" "reality profile does not ask hysteria2 before render"
default_reality_steps="$(xray_agent_default_install_profile_steps xrayCoreInstall_Reality)"
assert_not_contains "${default_reality_steps}" "update_nginx_reality" "default reality steps do not update nginx"
assert_contains "${default_reality_steps}" "update_nginx_stream_if_requested" "default reality steps keep explicit stream hook"
assert_contains "${default_reality_steps}" "render_reality_bundle,reload_core,optional_hysteria2" "default reality steps ask hysteria2 after reload"
dispatch_steps="$(sed -n '/xray_agent_dispatch_install_profile_step()/,/^}/p' lib/installer.sh)"
assert_not_contains "${dispatch_steps}" "update_nginx_reality" "installer dispatch does not expose old reality nginx step"
stream_only_fn="$(sed -n '/xray_agent_nginx_update_stream_only()/,/^}/p' lib/nginx.sh)"
assert_contains "${stream_only_fn}" "xray_agent_ensure_nginx_tools" "forced shared frontdoor ensures nginx tools"

XRAY_AGENT_INSTALL_PROFILE_ENTRY="xrayCoreInstall_Reality"
XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS="vless_reality_tcp,vless_xhttp"
if xray_agent_install_context_needs_nginx; then
    fail "reality install context should not require nginx"
fi
if xray_agent_install_context_needs_cert_tools; then
    fail "reality install context should not require cert tools"
fi
XRAY_AGENT_INSTALL_PROFILE_ENTRY="xrayCoreInstall"
if ! xray_agent_install_context_needs_nginx; then
    fail "tls install context should require nginx"
fi
if ! xray_agent_install_context_needs_cert_tools; then
    fail "tls install context should require cert tools"
fi

XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS="vless_reality_tcp,vless_xhttp"
assert_eq '[{"dest":"127.0.0.1:31305","xver":0}]' "$(xray_agent_reality_fallbacks_json)" "xhttp fallback enabled"
XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS="vless_reality_tcp"
assert_eq '[]' "$(xray_agent_reality_fallbacks_json)" "xhttp fallback disabled"

xray_agent_validate_reuse_path "itunes-assets"
assert_eq "ok" "$(xray_agent_reuse_status)" "valid path reuse ok"
xray_agent_validate_reuse_path "itunes-assetsws" >/dev/null 2>&1 || true
assert_eq "block" "$(xray_agent_reuse_status)" "ws suffix path reuse blocked"
xray_agent_validate_reuse_path "bad path" >/dev/null 2>&1 || true
assert_eq "block" "$(xray_agent_reuse_status)" "space path reuse blocked"

xray_agent_validate_reuse_uuid "8fb45875-8a03-4d15-8e61-ab13e4974830"
assert_eq "ok" "$(xray_agent_reuse_status)" "valid uuid reuse ok"
xray_agent_validate_reuse_uuid "not-a-uuid" >/dev/null 2>&1 || true
assert_eq "block" "$(xray_agent_reuse_status)" "invalid uuid reuse blocked"

xray_agent_detect_network_capabilities() {
    :
}
xray_agent_cert_resolved_records() {
    :
}
xray_agent_cert_port_owner() {
    printf '空闲\n'
}
xray_agent_validate_reuse_domain "example.com" >/dev/null
assert_eq "warn" "$(xray_agent_reuse_status)" "domain without dns warns"
xray_agent_validate_reuse_domain "bad domain" >/dev/null 2>&1 || true
assert_eq "block" "$(xray_agent_reuse_status)" "invalid domain blocked"

xray_agent_port_owner() {
    printf '空闲\n'
}
xray_agent_validate_reuse_tcp_port "Reality" "31302" >/dev/null
assert_eq "ok" "$(xray_agent_reuse_status)" "free tcp port reusable"
xray_agent_port_owner() {
    printf 'apache/123\n'
}
xray_agent_validate_reuse_tcp_port "Reality" "443" >/dev/null 2>&1 || true
assert_eq "block" "$(xray_agent_reuse_status)" "unexpected tcp owner blocked"
xray_agent_port_owner() {
    printf '空闲\n'
}

XRAY_AGENT_TEST_REALITY_TLS_PING_OUTPUT=$'Handshake succeeded\nTLS Post-Quantum key exchange: false\nCertificate chain'\''s total length: 3610 (certs count: 2)\nCert'\''s allowed domains: [video-ssl.itunes.apple.com audio-ssl.itunes.apple.com]'
xray_agent_validate_reuse_reality_target "video-ssl.itunes.apple.com:443"
assert_eq "warn" "$(xray_agent_reuse_status)" "reality target with no pq warns"
assert_contains "${XRAY_AGENT_REALITY_TLS_PING_ALLOWED_DOMAINS}" "video-ssl.itunes.apple.com" "tls ping allowed domains parsed"
xray_agent_validate_reuse_server_names "video-ssl.itunes.apple.com" "${XRAY_AGENT_REALITY_TLS_PING_ALLOWED_DOMAINS}"
assert_eq "ok" "$(xray_agent_reuse_status)" "matching serverNames ok"
xray_agent_validate_reuse_server_names "example.com" "${XRAY_AGENT_REALITY_TLS_PING_ALLOWED_DOMAINS}" >/dev/null 2>&1 || true
assert_eq "block" "$(xray_agent_reuse_status)" "mismatched serverNames blocked"
XRAY_AGENT_TEST_REALITY_TLS_PING_OUTPUT=$'TLS ping failed'
xray_agent_validate_reuse_reality_target "video-ssl.itunes.apple.com:443" >/dev/null 2>&1 || true
assert_eq "block" "$(xray_agent_reuse_status)" "failed tls ping blocks reality target"
unset XRAY_AGENT_TEST_REALITY_TLS_PING_OUTPUT

chmod +x "${XRAY_AGENT_XRAY_BINARY}"
xray_agent_reality_public_key_from_private() {
    [[ "$1" == "priv-good" ]] && printf 'pub-good\n'
}
xray_agent_validate_reuse_reality_keys "priv-good" "pub-good"
assert_eq "ok" "$(xray_agent_reuse_status)" "matching reality keys ok"
xray_agent_validate_reuse_reality_keys "priv-good" "pub-bad" >/dev/null 2>&1 || true
assert_eq "block" "$(xray_agent_reuse_status)" "mismatched reality keys blocked"

Hysteria2MasqueradeURL="https://example.com/"
Hysteria2BrutalUpMbps=0
Hysteria2BrutalDownMbps=0
Hysteria2HopPorts="20000-20010"
Hysteria2HopInterval=30
xray_agent_validate_reuse_hysteria2_config
assert_eq "ok" "$(xray_agent_reuse_status)" "valid hysteria2 config ok"
Hysteria2MasqueradeURL="ftp://example.com/"
xray_agent_validate_reuse_hysteria2_config >/dev/null 2>&1 || true
assert_eq "block" "$(xray_agent_reuse_status)" "invalid hysteria2 url blocked"

reset_fixture
adg_menu="$(xray_agent_adguard_print_menu)"
assert_contains "${adg_menu}" "状态: 未安装" "adguard uninstalled status"
assert_contains "${adg_menu}" "1.安装AdGuardHome" "adguard install action"

mkdir -p "${XRAY_AGENT_ADGUARD_HOME_DIR}"
: >"$(xray_agent_adguard_binary_path)"
XRAY_AGENT_ADGUARD_ACTIVE_OVERRIDE="active"
: >"$(xray_agent_adguard_config_path)"
adg_menu="$(xray_agent_adguard_print_menu)"
assert_contains "${adg_menu}" "状态: 运行中" "adguard running status"
assert_contains "${adg_menu}" "1.重新安装/修复AdGuardHome" "adguard repair action"
assert_not_contains "${adg_menu}" "1.安装Adguardhome" "adguard does not show old install label"
assert_not_contains "${adg_menu}" "1.安装AdGuardHome" "installed adguard does not show plain install label"
assert_contains "${adg_menu}" "4.关闭AdGuardHome" "adguard stop action"

XRAY_AGENT_ADGUARD_ACTIVE_OVERRIDE="inactive"
adg_menu="$(xray_agent_adguard_print_menu)"
assert_contains "${adg_menu}" "状态: 已安装未运行" "adguard stopped status"
assert_contains "${adg_menu}" "5.打开AdGuardHome" "adguard start action"

rm -f "$(xray_agent_adguard_config_path)"
XRAY_AGENT_ADGUARD_ACTIVE_OVERRIDE="active"
adg_menu="$(xray_agent_adguard_print_menu)"
assert_contains "${adg_menu}" "状态: 运行中(未初始化)" "adguard missing config status"

prompt_calls=0
xray_agent_prompt_yes_no() {
    prompt_calls=$((prompt_calls + 1))
    return 0
}
path="bad path"
randomPathFunction 1 <<<"goodpath" >/dev/null
assert_eq "0" "${prompt_calls}" "blocked old path does not ask reuse"
assert_eq "goodpath" "${path}" "blocked old path falls through to new input"

prompt_calls=0
hysteria_enable_calls=0
acme_calls=0
xray_agent_prompt_yes_no() {
    prompt_calls=$((prompt_calls + 1))
    return 1
}
xray_agent_hysteria2_enable_or_reconfigure() {
    hysteria_enable_calls=$((hysteria_enable_calls + 1))
}
xray_agent_ensure_acme_tools() {
    acme_calls=$((acme_calls + 1))
}
xray_agent_offer_optional_hysteria2 1 >/dev/null
assert_eq "1" "${prompt_calls}" "optional hysteria2 prompts once"
assert_eq "0" "${hysteria_enable_calls}" "declined hysteria2 does not enable"
assert_eq "0" "${acme_calls}" "declined hysteria2 does not touch acme"

printf 'ok - state fixture tests passed\n'
