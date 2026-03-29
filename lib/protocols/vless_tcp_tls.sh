xray_agent_render_vless_tcp_tls_inbound() {
    local clients_json="$1"
    local accept_proxy_protocol="$2"
    local sniffing_json="$3"
    xray_agent_load_protocol_profile "vless_tcp_tls"
    export XRAY_CLIENTS_JSON="${clients_json}"
    export XRAY_FALLBACKS_JSON='[{"path":"/'"${path}"'ws","dest":31297,"xver":1},{"path":"/'"${path}"'vws","dest":31299,"xver":1},{"dest":31305,"xver":0}]'
    export XRAY_SOCKOPT_JSON
    export XRAY_SNIFFING_JSON="${sniffing_json}"
    export XRAY_INBOUND_PORT="${Port}"
    export XRAY_INBOUND_TAG="VLESSTCP"
    export XRAY_ACCEPT_PROXY_PROTOCOL="${accept_proxy_protocol}"
    export XRAY_TLS_DOMAIN="${TLSDomain}"
    XRAY_SOCKOPT_JSON="$(xray_agent_sockopt_with_proxy_protocol "${accept_proxy_protocol}")"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}
