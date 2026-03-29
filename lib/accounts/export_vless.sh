if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_render_share_template_text() {
    local template_name="$1"
    local template_path="${XRAY_AGENT_PROJECT_ROOT}/templates/share/${template_name}"
    local template_content
    template_content=$(cat "${template_path}")
    eval "cat <<__XRAY_AGENT_SHARE__
${template_content}
__XRAY_AGENT_SHARE__"
}

xray_agent_print_vless_profile_share() {
    local profile_name="$1"
    local id="$2"
    local variant="${3:-}"
    local rendered
    xray_agent_load_protocol_profile "${profile_name}" || return 1
    local address port sni share_path security
    address="$(xray_agent_protocol_address_value "${variant}")"
    port="$(xray_agent_protocol_port_value "${variant}")"
    sni="$(xray_agent_protocol_sni_value "${variant}")"
    share_path="$(xray_agent_protocol_path_value)"
    security="$(xray_agent_protocol_security_value "${variant}")"
    local XRAY_SHARE_UUID="${id}"
    local XRAY_SHARE_ADDRESS="${address}"
    local XRAY_SHARE_PORT="${port}"
    local XRAY_SHARE_SNI="${sni}"
    local XRAY_SHARE_PATH="${share_path#/}"
    local XRAY_SHARE_SECURITY="${security}"
    local XRAY_SHARE_PUBLIC_KEY="${RealityPublicKey}"
    local XRAY_SHARE_NAME="${id}"
    rendered="$(xray_agent_render_share_template_text "${XRAY_AGENT_PROTOCOL_SHARE_TEMPLATE}")"
    echoContent green "${rendered}\n"
}

xray_agent_build_vless_uri() {
    local profile_name="$1"
    local id="$2"
    local variant="${3:-}"
    xray_agent_load_protocol_profile "${profile_name}" || return 1

    local address port sni path_value security query
    address="$(xray_agent_protocol_address_value "${variant}")"
    port="$(xray_agent_protocol_port_value "${variant}")"
    sni="$(xray_agent_protocol_sni_value "${variant}")"
    path_value="$(xray_agent_protocol_path_value)"
    security="$(xray_agent_protocol_security_value "${variant}")"

    query="encryption=none"
    if [[ -n "${XRAY_AGENT_PROTOCOL_FLOW}" ]]; then
        query="${query}&flow=${XRAY_AGENT_PROTOCOL_FLOW}"
    fi
    query="${query}&security=${security}"

    if [[ "${security}" == "tls" ]]; then
        query="${query}&sni=${sni}&alpn=$(xray_agent_urlencode "${XRAY_AGENT_PROTOCOL_ALPN}")&fp=${XRAY_AGENT_PROTOCOL_FP}"
    elif [[ "${security}" == "reality" ]]; then
        query="${query}&sni=${sni}&fp=${XRAY_AGENT_PROTOCOL_FP}&pbk=${RealityPublicKey}"
        if [[ -n "${RealityShortID}" ]]; then
            query="${query}&sid=${RealityShortID}"
        fi
    fi

    case "${XRAY_AGENT_PROTOCOL_TRANSPORT}" in
        tcp)
            query="${query}&type=tcp&headerType=none"
            ;;
        ws)
            query="${query}&type=ws&host=${sni}&path=$(xray_agent_urlencode "${path_value}")"
            ;;
        xhttp)
            query="${query}&type=xhttp"
            if [[ -n "${path_value}" ]]; then
                query="${query}&path=$(xray_agent_urlencode "${path_value}")"
            fi
            if [[ -n "${XRAY_AGENT_PROTOCOL_MODE}" ]]; then
                query="${query}&mode=${XRAY_AGENT_PROTOCOL_MODE}"
            fi
            ;;
    esac

    echo "vless://${id}@${address}:${port}?${query}#${id}"
}

defaultBase64Code() {
    local type="$1"
    local id="$2"
    case "${type}" in
        vlesstcp)
            xray_agent_print_vless_profile_share "vless_tcp_tls" "${id}"
            xray_agent_print_share_bundle "vless_tcp_tls" "${id}"
            ;;
        vlessws)
            xray_agent_print_vless_profile_share "vless_ws_tls" "${id}"
            ;;
        vmessws)
            xray_agent_print_vmess_share "${id}"
            ;;
        vlesstcpreality)
            xray_agent_print_vless_profile_share "vless_reality_tcp" "${id}"
            xray_agent_print_share_bundle "vless_reality_tcp" "${id}"
            ;;
        vlessxhttp)
            if [[ "${coreInstallType}" == "1" || "${coreInstallType}" == "3" ]]; then
                xray_agent_print_vless_profile_share "vless_xhttp" "${id}" "tls"
                xray_agent_print_share_bundle "vless_xhttp" "${id}" "tls"
            fi
            if [[ "${coreInstallType}" == "2" || "${coreInstallType}" == "3" ]]; then
                xray_agent_print_vless_profile_share "vless_xhttp" "${id}" "reality"
                xray_agent_print_share_bundle "vless_xhttp" "${id}" "reality"
            fi
            ;;
    esac
}
