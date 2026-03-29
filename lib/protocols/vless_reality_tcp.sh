xray_agent_render_vless_reality_tcp_inbound() {
    local clients_json="$1"
    local accept_proxy_protocol="$2"
    local sniffing_json="$3"
    xray_agent_load_protocol_profile "vless_reality_tcp"
    export XRAY_CLIENTS_JSON="${clients_json}"
    export XRAY_FALLBACKS_JSON='[{"dest":31305,"xver":0}]'
    export XRAY_SOCKOPT_JSON
    export XRAY_SNIFFING_JSON="${sniffing_json}"
    export XRAY_INBOUND_PORT="${RealityPort}"
    export XRAY_INBOUND_TAG="VLESSReality"
    export XRAY_ACCEPT_PROXY_PROTOCOL="${accept_proxy_protocol}"
    export XRAY_REALITY_DEST="${RealityDestDomain}"
    export XRAY_REALITY_SERVER_NAMES_JSON
    export XRAY_REALITY_PRIVATE_KEY="${RealityPrivateKey}"
    export XRAY_REALITY_PUBLIC_KEY="${RealityPublicKey}"
    export XRAY_REALITY_SHORT_IDS_JSON
    XRAY_SOCKOPT_JSON="$(xray_agent_sockopt_with_proxy_protocol "${accept_proxy_protocol}")"
    XRAY_REALITY_SERVER_NAMES_JSON="$(printf '%s' "${RealityServerNames}" | jq -R 'split(",")')"
    XRAY_REALITY_SHORT_IDS_JSON="$(printf '%s' "${RealityShortID}" | jq -R 'split(",") | map(select(length > 0))')"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}
