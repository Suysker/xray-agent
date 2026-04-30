#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_protocol_template_dir() {
    echo "${XRAY_AGENT_PROJECT_ROOT}/templates/xray"
}

xray_agent_share_template_dir() {
    echo "${XRAY_AGENT_PROJECT_ROOT}/templates/share"
}

xray_agent_reset_protocol_profile() {
    XRAY_AGENT_PROTOCOL_NAME=
    XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE=
    XRAY_AGENT_PROTOCOL_SHARE_TEMPLATE=
    XRAY_AGENT_PROTOCOL_PROTOCOL=
    XRAY_AGENT_PROTOCOL_TRANSPORT=
    XRAY_AGENT_PROTOCOL_SECURITY=
    XRAY_AGENT_PROTOCOL_FLOW=
    XRAY_AGENT_PROTOCOL_ADDRESS_SOURCE=
    XRAY_AGENT_PROTOCOL_PORT_SOURCE=
    XRAY_AGENT_PROTOCOL_SNI_SOURCE=
    XRAY_AGENT_PROTOCOL_PATH_SOURCE=
    XRAY_AGENT_PROTOCOL_MODE=
    XRAY_AGENT_PROTOCOL_ALPN=
    XRAY_AGENT_PROTOCOL_FP=
    XRAY_AGENT_PROTOCOL_CLIENT_KIND=
    XRAY_AGENT_PROTOCOL_CONFIG_FILE=
}

xray_agent_load_protocol_profile() {
    local profile_path="${XRAY_AGENT_PROFILE_DIR}/protocol/$1.profile"
    local key value
    if [[ ! -r "${profile_path}" ]]; then
        return 1
    fi

    xray_agent_reset_protocol_profile
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        case "${key}" in
            name) XRAY_AGENT_PROTOCOL_NAME="${value}" ;;
            inbound_template) XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE="${value}" ;;
            share_template) XRAY_AGENT_PROTOCOL_SHARE_TEMPLATE="${value}" ;;
            protocol) XRAY_AGENT_PROTOCOL_PROTOCOL="${value}" ;;
            transport) XRAY_AGENT_PROTOCOL_TRANSPORT="${value}" ;;
            security) XRAY_AGENT_PROTOCOL_SECURITY="${value}" ;;
            flow) XRAY_AGENT_PROTOCOL_FLOW="${value}" ;;
            address_source) XRAY_AGENT_PROTOCOL_ADDRESS_SOURCE="${value}" ;;
            port_source) XRAY_AGENT_PROTOCOL_PORT_SOURCE="${value}" ;;
            sni_source) XRAY_AGENT_PROTOCOL_SNI_SOURCE="${value}" ;;
            path_source) XRAY_AGENT_PROTOCOL_PATH_SOURCE="${value}" ;;
            mode) XRAY_AGENT_PROTOCOL_MODE="${value}" ;;
            alpn) XRAY_AGENT_PROTOCOL_ALPN="${value}" ;;
            fp) XRAY_AGENT_PROTOCOL_FP="${value}" ;;
            client_kind) XRAY_AGENT_PROTOCOL_CLIENT_KIND="${value}" ;;
            config_file) XRAY_AGENT_PROTOCOL_CONFIG_FILE="${value}" ;;
        esac
    done <"${profile_path}"
}

xray_agent_generate_clients_json() {
    local protocol="$1"
    local uuid_csv="$2"
    jq -nc --arg protocol "${protocol}" --arg uuidCsv "${uuid_csv}" '
      ($uuidCsv | split(",") | map(select(length > 0))) as $uuids
      | $uuids
      | map(
          if $protocol == "VLESS_TCP" then
            {id: ., flow: "xtls-rprx-vision"}
          elif $protocol == "VLESS_XHTTP" or $protocol == "VLESS_WS" then
            {id: .}
          elif $protocol == "VMESS_WS" then
            {id: ., alterId: 0}
          else
            {id: .}
          end
        )'
}

generate_clients() {
    xray_agent_generate_clients_json "$1" "$2"
}

xray_agent_protocol_variant() {
    local requested_variant="${1:-}"
    if [[ -n "${requested_variant}" ]]; then
        echo "${requested_variant}"
    elif [[ "${coreInstallType}" == "2" ]]; then
        echo "reality"
    else
        echo "tls"
    fi
}

xray_agent_protocol_security_value() {
    local variant
    variant="$(xray_agent_protocol_variant "${1:-}")"
    case "${XRAY_AGENT_PROTOCOL_SECURITY}" in
        auto)
            if [[ "${variant}" == "reality" ]]; then
                echo "reality"
            else
                echo "tls"
            fi
            ;;
        *)
            echo "${XRAY_AGENT_PROTOCOL_SECURITY}"
            ;;
    esac
}

xray_agent_protocol_address_value() {
    local variant
    variant="$(xray_agent_protocol_variant "${1:-}")"
    case "${XRAY_AGENT_PROTOCOL_ADDRESS_SOURCE}" in
        domain)
            echo "${domain}"
            ;;
        public_ip)
            getPublicIP
            ;;
        auto)
            if [[ "${variant}" == "reality" ]]; then
                getPublicIP
            else
                echo "${domain}"
            fi
            ;;
    esac
}

xray_agent_protocol_port_value() {
    local variant
    variant="$(xray_agent_protocol_variant "${1:-}")"

    if [[ "${reuse443}" == "y" ]]; then
        echo "443"
        return 0
    fi

    case "${XRAY_AGENT_PROTOCOL_PORT_SOURCE}" in
        Port)
            echo "${Port}"
            ;;
        RealityPort)
            echo "${RealityPort}"
            ;;
        auto)
            if [[ "${variant}" == "reality" ]]; then
                echo "${RealityPort}"
            else
                echo "${Port}"
            fi
            ;;
    esac
}

xray_agent_primary_reality_server_name() {
    echo "${RealityServerNames}" | sed 's/"//g' | awk -F ',' '{print $1}'
}

xray_agent_protocol_sni_value() {
    local variant
    variant="$(xray_agent_protocol_variant "${1:-}")"
    case "${XRAY_AGENT_PROTOCOL_SNI_SOURCE}" in
        domain)
            echo "${domain}"
            ;;
        reality_server_name)
            xray_agent_primary_reality_server_name
            ;;
        auto)
            if [[ "${variant}" == "reality" ]]; then
                xray_agent_primary_reality_server_name
            else
                echo "${domain}"
            fi
            ;;
    esac
}

xray_agent_protocol_path_value() {
    case "${XRAY_AGENT_PROTOCOL_PATH_SOURCE}" in
        path)
            echo "/${path}"
            ;;
        path_ws)
            echo "/${path}ws"
            ;;
        path_vws)
            echo "/${path}vws"
            ;;
    esac
}

xray_agent_tls_fallbacks_json() {
    jq -nc \
        --arg wsPath "${XRAY_FALLBACK_WS_PATH}" \
        --arg vmessWsPath "${XRAY_FALLBACK_VMESS_WS_PATH}" \
        '[{path:$wsPath,dest:31297,xver:1},{path:$vmessWsPath,dest:31299,xver:1},{dest:31300,xver:0}]'
}

xray_agent_reality_fallbacks_json() {
    jq -nc '[{dest:31305,xver:0}]'
}

xray_agent_csv_json_array() {
    local csv_value="$1"
    csv_value="${csv_value//\"/}"
    jq -nc --arg csv "${csv_value}" '
      $csv
      | split(",")
      | map(gsub("^\\s+|\\s+$"; ""))
      | map(select(length > 0))'
}

xray_agent_short_ids_json_array() {
    local csv_value="$1"
    csv_value="${csv_value//\"/}"
    jq -nc --arg csv "${csv_value}" '
      ($csv
      | split(",")
      | map(gsub("^\\s+|\\s+$"; ""))
      | map(select(length > 0))) as $ids
      | if $ids == [] then [""] else $ids end'
}

xray_agent_render_vless_tcp_tls_inbound() {
    local clients_json="$1"
    local accept_proxy_protocol="$2"
    local sniffing_json="$3"
    xray_agent_load_protocol_profile "vless_tcp_tls"
    export XRAY_CLIENTS_JSON="${clients_json}"
    export XRAY_FALLBACK_WS_PATH="/${path}ws"
    export XRAY_FALLBACK_VMESS_WS_PATH="/${path}vws"
    export XRAY_FALLBACKS_JSON
    export XRAY_SOCKOPT_JSON
    export XRAY_SNIFFING_JSON="${sniffing_json}"
    export XRAY_INBOUND_PORT="${Port}"
    export XRAY_INBOUND_TAG="VLESSTCP"
    export XRAY_ACCEPT_PROXY_PROTOCOL="${accept_proxy_protocol}"
    export XRAY_TLS_DOMAIN="${TLSDomain}"
    XRAY_FALLBACKS_JSON="$(xray_agent_tls_fallbacks_json)"
    XRAY_SOCKOPT_JSON="$(xray_agent_sockopt_with_proxy_protocol "${accept_proxy_protocol}")"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}

xray_agent_render_vless_ws_legacy_config() {
    xray_agent_load_protocol_profile "vless_ws_tls"
    export XRAY_CLIENTS_JSON="$1"
    export XRAY_SNIFFING_JSON="$2"
    export XRAY_WS_PATH="/${path}ws"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}

xray_agent_render_vmess_ws_legacy_config() {
    xray_agent_load_protocol_profile "vmess_ws_tls"
    export XRAY_CLIENTS_JSON="$1"
    export XRAY_SNIFFING_JSON="$2"
    export XRAY_WS_PATH="/${path}vws"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}

xray_agent_render_vless_reality_tcp_inbound() {
    local clients_json="$1"
    local accept_proxy_protocol="$2"
    local sniffing_json="$3"
    xray_agent_load_protocol_profile "vless_reality_tcp"
    export XRAY_CLIENTS_JSON="${clients_json}"
    export XRAY_FALLBACKS_JSON
    export XRAY_SOCKOPT_JSON
    export XRAY_SNIFFING_JSON="${sniffing_json}"
    export XRAY_INBOUND_PORT="${RealityPort}"
    export XRAY_INBOUND_TAG="VLESSReality"
    export XRAY_ACCEPT_PROXY_PROTOCOL="${accept_proxy_protocol}"
    export XRAY_REALITY_TARGET="${RealityDestDomain}"
    export XRAY_REALITY_SERVER_NAMES_JSON
    export XRAY_REALITY_PRIVATE_KEY="${RealityPrivateKey}"
    export XRAY_REALITY_SHORT_IDS_JSON
    XRAY_FALLBACKS_JSON="$(xray_agent_reality_fallbacks_json)"
    XRAY_SOCKOPT_JSON="$(xray_agent_sockopt_with_proxy_protocol "${accept_proxy_protocol}")"
    XRAY_REALITY_SERVER_NAMES_JSON="$(xray_agent_csv_json_array "${RealityServerNames}")"
    XRAY_REALITY_SHORT_IDS_JSON="$(xray_agent_short_ids_json_array "${RealityShortID}")"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
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
    export XRAY_SOCKOPT_JSON
    export XRAY_SNIFFING_JSON="${sniffing_json}"
    XRAY_SOCKOPT_JSON="$(xray_agent_sockopt_with_proxy_protocol "false")"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}
