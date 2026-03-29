if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_print_vmess_share() {
    local id="$1"
    xray_agent_load_protocol_profile "vmess_ws_tls"
    local XRAY_SHARE_UUID="${id}"
    local XRAY_SHARE_ADDRESS="${domain}"
    local XRAY_SHARE_PORT="$(xray_agent_protocol_port_value)"
    local XRAY_SHARE_SNI="${domain}"
    local XRAY_SHARE_PATH="${path}vws"
    local XRAY_SHARE_NAME="${id}"
    local encoded_json
    encoded_json="$(xray_agent_render_share_template_text "${XRAY_AGENT_PROTOCOL_SHARE_TEMPLATE}" | base64 -w 0)"
    echoContent green "vmess://${encoded_json}\n"
}
