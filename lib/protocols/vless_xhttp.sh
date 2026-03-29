xray_agent_default_xhttp_headers_json() {
    jq -nc '{"User-Agent": ["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36"]}'
}

xray_agent_render_vless_xhttp_inbound() {
    local clients_json="$1"
    local inbound_port="$2"
    local sniffing_json="$3"
    xray_agent_load_protocol_profile "vless_xhttp"
    export XRAY_CLIENTS_JSON="${clients_json}"
    export XRAY_INBOUND_PORT="${inbound_port}"
    export XRAY_INBOUND_TAG="VLESSXHTTP"
    export XRAY_XHTTP_PATH="/${path}"
    export XRAY_XHTTP_MODE="${XHTTPMode:-auto}"
    export XRAY_XHTTP_HEADERS_JSON
    export XRAY_SOCKOPT_JSON
    export XRAY_SNIFFING_JSON="${sniffing_json}"
    XRAY_SOCKOPT_JSON="$(xray_agent_sockopt_with_proxy_protocol "false")"
    XRAY_XHTTP_HEADERS_JSON="$(xray_agent_default_xhttp_headers_json)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}
