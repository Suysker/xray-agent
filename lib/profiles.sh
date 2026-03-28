if [[ -z "${XRAY_AGENT_PROFILE_DIR}" ]]; then
    XRAY_AGENT_PROFILE_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/profiles"
fi

xray_agent_reset_profile_definition() {
    XRAY_AGENT_PROFILE_NAME=
    XRAY_AGENT_PROFILE_DISPLAY_NAME=
    XRAY_AGENT_PROFILE_ADDRESS_SOURCE=
    XRAY_AGENT_PROFILE_PORT_SOURCE=
    XRAY_AGENT_PROFILE_TRANSPORT=
    XRAY_AGENT_PROFILE_SECURITY=
    XRAY_AGENT_PROFILE_FLOW=
    XRAY_AGENT_PROFILE_SNI_SOURCE=
    XRAY_AGENT_PROFILE_PATH_SOURCE=
    XRAY_AGENT_PROFILE_MODE=
    XRAY_AGENT_PROFILE_ALPN=
    XRAY_AGENT_PROFILE_FP=
    XRAY_AGENT_PROFILE_PBK_SOURCE=
    XRAY_AGENT_PROFILE_SID_SOURCE=
    XRAY_AGENT_PROFILE_PROTOCOL=
    XRAY_AGENT_PROFILE_TAG=
    XRAY_AGENT_PROFILE_INBOUND_PATH=
    XRAY_AGENT_PROFILE_MUX=
    XRAY_AGENT_PROFILE_FINALMASK=
    XRAY_AGENT_PROFILE_BROWSER_HEADERS=
    XRAY_AGENT_PROFILE_ECH=
    XRAY_AGENT_PROFILE_VLESS_ENCRYPTION=
}

xray_agent_load_profile() {
    local profile_path="${XRAY_AGENT_PROFILE_DIR}/$1.env"
    if [[ ! -r "${profile_path}" ]]; then
        return 1
    fi

    xray_agent_reset_profile_definition
    source "${profile_path}"

    XRAY_AGENT_PROFILE_PROTOCOL="${XRAY_AGENT_PROFILE_PROTOCOL:-vless}"
    XRAY_AGENT_PROFILE_TAG="${XRAY_AGENT_PROFILE_TAG:-${XRAY_AGENT_PROFILE_NAME}}"
    return 0
}

xray_agent_profile_address() {
    case "${XRAY_AGENT_PROFILE_ADDRESS_SOURCE}" in
        domain)
            echo "${domain}"
            ;;
        public_ip)
            getPublicIP
            ;;
    esac
}

xray_agent_profile_port() {
    case "${XRAY_AGENT_PROFILE_PORT_SOURCE}" in
        Port)
            echo "${Port}"
            ;;
        RealityPort)
            echo "${RealityPort}"
            ;;
    esac
}

xray_agent_primary_reality_server_name() {
    echo "${RealityServerNames}" | awk -F ',' '{print $1}'
}

xray_agent_profile_sni() {
    case "${XRAY_AGENT_PROFILE_SNI_SOURCE}" in
        domain)
            echo "${domain}"
            ;;
        reality_server_name)
            xray_agent_primary_reality_server_name
            ;;
    esac
}

xray_agent_profile_path() {
    case "${XRAY_AGENT_PROFILE_PATH_SOURCE}" in
        path)
            echo "/${path}"
            ;;
    esac
}

xray_agent_profile_sid() {
    case "${XRAY_AGENT_PROFILE_SID_SOURCE}" in
        RealityShortID)
            echo "${RealityShortID}"
            ;;
    esac
}

xray_agent_build_vless_uri() {
    local profile_name="$1"
    local id="$2"

    if ! xray_agent_load_profile "${profile_name}"; then
        return 1
    fi

    local address port sni alpn fp path_value sid_value
    address="$(xray_agent_profile_address)"
    port="$(xray_agent_profile_port)"
    sni="$(xray_agent_profile_sni)"
    alpn="$(xray_agent_urlencode "${XRAY_AGENT_PROFILE_ALPN}")"
    fp="${XRAY_AGENT_PROFILE_FP}"
    path_value="$(xray_agent_profile_path)"
    sid_value="$(xray_agent_profile_sid)"

    local query="encryption=none"
    if [[ -n "${XRAY_AGENT_PROFILE_FLOW}" ]]; then
        query="${query}&flow=${XRAY_AGENT_PROFILE_FLOW}"
    fi

    query="${query}&security=${XRAY_AGENT_PROFILE_SECURITY}"

    if [[ "${XRAY_AGENT_PROFILE_SECURITY}" == "tls" ]]; then
        query="${query}&sni=${sni}&alpn=${alpn}&fp=${fp}"
    elif [[ "${XRAY_AGENT_PROFILE_SECURITY}" == "reality" ]]; then
        query="${query}&sni=${sni}&fp=${fp}&pbk=${RealityPublicKey}"
        if [[ -n "${sid_value}" ]]; then
            query="${query}&sid=${sid_value}"
        fi
    fi

    if [[ "${XRAY_AGENT_PROFILE_TRANSPORT}" == "tcp" ]]; then
        query="${query}&type=tcp&headerType=none"
    elif [[ "${XRAY_AGENT_PROFILE_TRANSPORT}" == "xhttp" ]]; then
        query="${query}&type=xhttp"
        if [[ -n "${path_value}" ]]; then
            query="${query}&path=$(xray_agent_urlencode "${path_value}")"
        fi
        if [[ -n "${XRAY_AGENT_PROFILE_MODE}" ]]; then
            query="${query}&mode=${XRAY_AGENT_PROFILE_MODE}"
        fi
    fi

    echo "vless://${id}@${address}:${port}?${query}#${id}"
}

xray_agent_profile_display_name() {
    if xray_agent_load_profile "$1"; then
        echo "${XRAY_AGENT_PROFILE_DISPLAY_NAME}"
    fi
}
