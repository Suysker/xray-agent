#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERIFY_TOOL_DIR=

ensure_jq() {
    local candidate
    if command -v jq >/dev/null 2>&1; then
        return 0
    fi
    for candidate in \
        /mnt/c/Users/*/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_*/jq.exe \
        /c/Users/*/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_*/jq.exe; do
        [[ -f "${candidate}" ]] || continue
        VERIFY_TOOL_DIR=$(mktemp -d)
        cat >"${VERIFY_TOOL_DIR}/jq" <<'EOF'
#!/usr/bin/env bash
set -e
jq_exe="__JQ_EXE__"
converted_args=()
for arg in "$@"; do
    if [[ "${arg}" == /* && -e "${arg}" ]] && command -v wslpath >/dev/null 2>&1; then
        converted_args+=("$(wslpath -w "${arg}")")
    else
        converted_args+=("${arg}")
    fi
done
exec "${jq_exe}" "${converted_args[@]}"
EOF
        sed -i "s|__JQ_EXE__|${candidate//|/\\|}|g" "${VERIFY_TOOL_DIR}/jq"
        chmod +x "${VERIFY_TOOL_DIR}/jq"
        export PATH="${VERIFY_TOOL_DIR}:${PATH}"
        return 0
    done
    echo "jq is required for verify/render-protocols.sh" >&2
    exit 1
}

ensure_jq
source "${ROOT_DIR}/install.sh"

xray_agent_render_common_xray_configs() {
    export XRAY_LOG_ERROR_PATH="/etc/xray-agent/xray/error.log"
    export XRAY_LOG_LEVEL="warning"
    export XRAY_POLICY_HANDSHAKE=2
    export XRAY_POLICY_CONN_IDLE=420
    export XRAY_OUTBOUNDS_JSON
    export XRAY_ROUTING_RULES_JSON
    export XRAY_ROUTING_DOMAIN_STRATEGY="AsIs"
    export XRAY_DNS_SERVERS_JSON
    export XRAY_DNS_QUERY_STRATEGY="UseIP"
    XRAY_OUTBOUNDS_JSON="$(xray_agent_default_outbounds_json)"
    XRAY_ROUTING_RULES_JSON="$(xray_agent_default_routing_rules_json)"
    XRAY_DNS_SERVERS_JSON="$(xray_agent_default_dns_servers_json)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/00_log.json.tpl" "${configPath}00_log.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/01_policy.json.tpl" "${configPath}01_policy.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/09_routing.json.tpl" "${configPath}09_routing.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/10_outbounds.json.tpl" "${configPath}10_ipv4_outbounds.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/11_dns.json.tpl" "${configPath}11_dns.json"
}

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}" "${VERIFY_TOOL_DIR:-}"' EXIT

initVar
configPath="${TMP_DIR}/conf/"
nginxConfigPath="${TMP_DIR}/nginx/"
mkdir -p "${configPath}" "${nginxConfigPath}"

domain="example.com"
TLSDomain="example.com"
path="demo"
Port=443
RealityPort=8443
UUID="11111111-1111-1111-1111-111111111111"
RealityPrivateKey="private-key"
RealityPublicKey="public-key"
RealityServerNames="www.cloudflare.com,cdn.cloudflare.com"
RealityDestDomain="www.cloudflare.com:443"
RealityShortID="1234abcd"
XHTTPMode="auto"
reuse443=

xray_agent_prepare_uuid() { :; }
xray_agent_prepare_reality_keys() { :; }

sniffing_json="$(xray_agent_default_sniffing_json)"
xray_agent_render_vless_tcp_tls_inbound "$(xray_agent_generate_clients_json "VLESS_TCP" "${UUID}")" "false" "${sniffing_json}"
xray_agent_render_vless_ws_legacy_config "$(xray_agent_generate_clients_json "VLESS_WS" "${UUID}")" "${sniffing_json}"
xray_agent_render_vmess_ws_legacy_config "$(xray_agent_generate_clients_json "VMESS_WS" "${UUID}")" "${sniffing_json}"
xray_agent_render_vless_reality_tcp_inbound "$(xray_agent_generate_clients_json "VLESS_TCP" "${UUID}")" "false" "${sniffing_json}"
xray_agent_render_vless_xhttp_inbound "$(xray_agent_generate_clients_json "VLESS_XHTTP" "${UUID}")" "31305" "${sniffing_json}"
xray_agent_render_hysteria2_profile
xray_agent_render_local_tun_profile

find "${configPath}" -name "*.json" -print0 | while IFS= read -r -d '' file; do
    jq empty "${file}"
done

rm -f "${configPath}"*.json

XRAY_AGENT_BROWSER_HEADERS="edge"
XRAY_AGENT_TRUSTED_X_FORWARDED_FOR="10.0.0.0/8"

xray_agent_load_install_profile "tls_vision_xhttp"
[[ "${XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS}" == "vless_tcp_tls,vless_ws_tls,vmess_ws_tls,vless_xhttp" ]]
xray_agent_render_tls_bundle
for file in \
    "${configPath}02_VLESS_TCP_inbounds.json" \
    "${configPath}03_VLESS_WS_inbounds.json" \
    "${configPath}05_VMess_WS_inbounds.json" \
    "${configPath}08_VLESS_XHTTP_inbounds.json"; do
    [[ -f "${file}" ]]
    jq -e '.inbounds[0].streamSettings.sockopt.trustedXForwardedFor[0] == "10.0.0.0/8"' "${file}" >/dev/null
done
[[ ! -f "${configPath}07_VLESS_Reality_TCP_inbounds.json" ]]
[[ "$(jq -r '.inbounds[0].streamSettings.xhttpSettings.headers["User-Agent"][0]' "${configPath}08_VLESS_XHTTP_inbounds.json")" == *"Edg/131.0.0.0"* ]]

find "${configPath}" -name "*.json" -print0 | while IFS= read -r -d '' file; do
    jq empty "${file}"
done

rm -f "${configPath}"*.json

xray_agent_load_install_profile "reality_vision_xhttp"
[[ "${XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS}" == "vless_reality_tcp,vless_xhttp" ]]
xray_agent_render_reality_bundle
for file in \
    "${configPath}07_VLESS_Reality_TCP_inbounds.json" \
    "${configPath}08_VLESS_XHTTP_inbounds.json"; do
    [[ -f "${file}" ]]
    jq -e '.inbounds[0].streamSettings.sockopt.trustedXForwardedFor[0] == "10.0.0.0/8"' "${file}" >/dev/null
done
[[ ! -f "${configPath}02_VLESS_TCP_inbounds.json" ]]
[[ ! -f "${configPath}03_VLESS_WS_inbounds.json" ]]
[[ ! -f "${configPath}05_VMess_WS_inbounds.json" ]]
[[ "$(jq -r '.inbounds[0].streamSettings.xhttpSettings.headers["User-Agent"][0]' "${configPath}08_VLESS_XHTTP_inbounds.json")" == *"Edg/131.0.0.0"* ]]

find "${configPath}" -name "*.json" -print0 | while IFS= read -r -d '' file; do
    jq empty "${file}"
done

echo "PASS render-protocols"
