xray_agent_normalize_browser_headers_profile() {
    local browser_name="${XRAY_AGENT_BROWSER_HEADERS:-chrome}"
    browser_name="${browser_name,,}"
    case "${browser_name}" in
        chrome|firefox|edge)
            ;;
        *)
            browser_name="chrome"
            ;;
    esac
    printf '%s\n' "${browser_name}"
}

xray_agent_xhttp_headers_json_for_browser() {
    local browser_name="${1:-chrome}"
    case "${browser_name}" in
        firefox)
            jq -nc '{
              "User-Agent": ["Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0"],
              "Accept-Language": ["en-US,en;q=0.9"],
              "Cache-Control": ["no-cache"]
            }'
            ;;
        edge)
            jq -nc '{
              "User-Agent": ["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0"],
              "Sec-CH-UA": ["\"Chromium\";v=\"131\", \"Microsoft Edge\";v=\"131\", \"Not_A Brand\";v=\"24\""],
              "Sec-CH-UA-Mobile": ["?0"],
              "Sec-CH-UA-Platform": ["\"Windows\""]
            }'
            ;;
        *)
            jq -nc '{
              "User-Agent": ["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"],
              "Sec-CH-UA": ["\"Chromium\";v=\"131\", \"Google Chrome\";v=\"131\", \"Not_A Brand\";v=\"24\""],
              "Sec-CH-UA-Mobile": ["?0"],
              "Sec-CH-UA-Platform": ["\"Windows\""]
            }'
            ;;
    esac
}

xray_agent_default_xhttp_headers_json() {
    xray_agent_xhttp_headers_json_for_browser "$(xray_agent_normalize_browser_headers_profile)"
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
