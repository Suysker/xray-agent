xray_agent_render_vless_ws_legacy_config() {
    xray_agent_load_protocol_profile "vless_ws_tls"
    export XRAY_CLIENTS_JSON="$1"
    export XRAY_SNIFFING_JSON="$2"
    export XRAY_WS_PATH="/${path}ws"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}
