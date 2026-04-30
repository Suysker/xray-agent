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
          elif $protocol == "HYSTERIA2" then
            {auth: ., level: 0, email: .}
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
            if [[ "${variant}" == "reality" ]]; then
                xray_agent_select_public_ip_for_reality
            else
                getPublicIP
            fi
            ;;
        auto)
            if [[ "${variant}" == "reality" ]]; then
                xray_agent_select_public_ip_for_reality
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
        hysteria2)
            echo "443"
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
        *)
            echo ""
            ;;
    esac
}

xray_agent_tls_fallbacks_json() {
    local ws_dest vmess_ws_dest nginx_dest
    ws_dest="$(xray_agent_loopback_endpoint 31297)"
    vmess_ws_dest="$(xray_agent_loopback_endpoint 31299)"
    nginx_dest="$(xray_agent_loopback_endpoint 31300)"
    jq -nc \
        --arg wsPath "${XRAY_FALLBACK_WS_PATH}" \
        --arg vmessWsPath "${XRAY_FALLBACK_VMESS_WS_PATH}" \
        --arg wsDest "${ws_dest}" \
        --arg vmessWsDest "${vmess_ws_dest}" \
        --arg nginxDest "${nginx_dest}" \
        '[{path:$wsPath,dest:$wsDest,xver:1},{path:$vmessWsPath,dest:$vmessWsDest,xver:1},{dest:$nginxDest,xver:0}]'
}

xray_agent_reality_fallbacks_json() {
    local xhttp_dest
    xhttp_dest="$(xray_agent_loopback_endpoint 31305)"
    jq -nc --arg xhttpDest "${xhttp_dest}" '[{dest:$xhttpDest,xver:0}]'
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
    xray_agent_export_xray_network_template_vars
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
    xray_agent_export_xray_network_template_vars
    export XRAY_CLIENTS_JSON="$1"
    export XRAY_SNIFFING_JSON="$2"
    export XRAY_WS_PATH="/${path}ws"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}

xray_agent_render_vmess_ws_legacy_config() {
    xray_agent_load_protocol_profile "vmess_ws_tls"
    xray_agent_export_xray_network_template_vars
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
    xray_agent_export_xray_network_template_vars
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
    xray_agent_export_xray_network_template_vars
    export XRAY_CLIENTS_JSON="${clients_json}"
    export XRAY_INBOUND_PORT="${inbound_port}"
    export XRAY_INBOUND_TAG="VLESSXHTTP"
    export XRAY_XHTTP_PATH="/${path}"
    export XRAY_SOCKOPT_JSON
    export XRAY_SNIFFING_JSON="${sniffing_json}"
    XRAY_SOCKOPT_JSON="$(xray_agent_sockopt_with_proxy_protocol "false")"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}

xray_agent_hysteria2_default_masquerade_url() {
    local include_existing="${1:-true}"
    local candidate

    if [[ "${include_existing}" == "true" && -n "${Hysteria2MasqueradeURL:-}" ]]; then
        printf '%s\n' "${Hysteria2MasqueradeURL}"
        return 0
    fi

    candidate="$(xray_agent_hysteria2_nginx_masquerade_url)"
    if [[ -n "${candidate}" ]]; then
        printf '%s\n' "${candidate}"
        return 0
    fi

    candidate="$(xray_agent_hysteria2_reality_masquerade_url)"
    if [[ -n "${candidate}" ]]; then
        printf '%s\n' "${candidate}"
        return 0
    fi

    printf ''
}

xray_agent_hysteria2_nginx_masquerade_url() {
    local nginx_file="${nginxConfigPath:-}/alone.conf"
    [[ -f "${nginx_file}" ]] || return 0
    awk '$1 == "proxy_pass" && $2 ~ /^https?:\/\// {gsub(";","",$2); print $2; exit}' "${nginx_file}"
}

xray_agent_hysteria2_reality_masquerade_url() {
    local target="${RealityDestDomain:-}"
    target="${target//\"/}"
    [[ -n "${target}" ]] || return 0
    target="${target%%,*}"
    target="${target#https://}"
    target="${target#http://}"
    target="${target%%/*}"
    target="${target%%:*}"
    [[ -n "${target}" ]] || return 0
    printf 'https://%s/\n' "${target}"
}

xray_agent_hysteria2_default_domain() {
    if [[ -n "${domain:-}" ]]; then
        printf '%s\n' "${domain}"
    elif [[ -n "${TLSDomain:-}" ]]; then
        printf '%s\n' "${TLSDomain}"
    fi
}

xray_agent_hysteria2_prompt_mbps() {
    local label="$1"
    local default_value="${2:-0}"
    local input_value
    while true; do
        read -r -p "${label}[Mbps，回车默认${default_value}，0表示不开Brutal]:" input_value
        input_value="${input_value:-${default_value}}"
        if [[ "${input_value}" =~ ^[0-9]+$ ]]; then
            printf '%s\n' "${input_value}"
            return 0
        fi
        echoContent red " ---> 请输入整数 Mbps" >&2
    done
}

xray_agent_hysteria2_prepare_tls_domain() {
    local default_domain input_domain
    default_domain="$(xray_agent_hysteria2_default_domain)"
    if [[ -n "${default_domain}" ]]; then
        echoContent yellow "请输入 Hysteria2 使用的域名[回车使用 ${default_domain}]:"
        read -r -p "域名:" input_domain
        if [[ -n "${input_domain}" && "${input_domain}" != "${default_domain}" ]]; then
            domain="${input_domain}"
            TLSDomain=
        else
            domain="${default_domain}"
        fi
    else
        echoContent yellow "请输入 Hysteria2 使用的域名[必须是自己控制且可签发证书的真实域名]:"
        read -r -p "域名:" domain
    fi
    [[ -n "${domain:-}" ]] || xray_agent_error " ---> Hysteria2 域名不可为空"
    TLSDomain="${TLSDomain:-${domain}}"

    if [[ ! -f "/etc/xray-agent/tls/${TLSDomain}.crt" || ! -f "/etc/xray-agent/tls/${TLSDomain}.key" ]]; then
        installTLS 1 0
    fi
}

xray_agent_hysteria2_prepare_runtime() {
    local reuse_hysteria2_config="n"
    local default_masquerade_url input_masquerade_url
    xray_agent_hysteria2_prepare_tls_domain
    echoContent yellow " ---> Hysteria2 需要当前 Xray-core 支持 protocol=hysteria；旧内核请先用菜单12升级"
    if [[ "$(xray_agent_public_ip_total_count)" -gt 1 ]]; then
        echoContent yellow " ---> 检测到多个公网 IP。Hysteria2/UDP 在多出口场景可能需要你确认系统路由和云防火墙，避免 UDP 回复源地址不一致。"
    fi
    checkUDPPort 443
    allowPort 443 udp

    if [[ -n "${Hysteria2MasqueradeURL:-}" ]]; then
        read -r -p "读取到上次 Hysteria2 配置，是否继续使用？[Y/n]:" reuse_hysteria2_config
        reuse_hysteria2_config="${reuse_hysteria2_config:-y}"
    fi

    if [[ "${reuse_hysteria2_config}" != "y" ]]; then
        default_masquerade_url="$(xray_agent_hysteria2_default_masquerade_url false)"
        if [[ -n "${default_masquerade_url}" ]]; then
            echoContent yellow "请输入 Hysteria2 伪装站 URL，[回车使用 ${default_masquerade_url}]:"
        else
            echoContent yellow "请输入 Hysteria2 伪装站 URL[例如 https://www.example.com/]:"
        fi
        read -r -p "URL:" input_masquerade_url
        Hysteria2MasqueradeURL="${input_masquerade_url:-${default_masquerade_url}}"
        [[ -n "${Hysteria2MasqueradeURL}" ]] || xray_agent_error " ---> Hysteria2 伪装站 URL 不可为空"
        Hysteria2BrutalUpMbps="$(xray_agent_hysteria2_prompt_mbps "上行带宽" "${Hysteria2BrutalUpMbps:-0}")"
        Hysteria2BrutalDownMbps="$(xray_agent_hysteria2_prompt_mbps "下行带宽" "${Hysteria2BrutalDownMbps:-0}")"
    fi

    Hysteria2Port=443
}

xray_agent_hysteria2_finalmask_suffix() {
    local up_mbps="${Hysteria2BrutalUpMbps:-0}"
    local down_mbps="${Hysteria2BrutalDownMbps:-0}"
    local quic_params

    if [[ "${up_mbps}" == "0" && "${down_mbps}" == "0" ]]; then
        printf ''
        return 0
    fi

    quic_params="$(jq -nc \
        --arg up "${up_mbps} mbps" \
        --arg down "${down_mbps} mbps" \
        --argjson useUp "$([[ "${up_mbps}" == "0" ]] && echo false || echo true)" \
        --argjson useDown "$([[ "${down_mbps}" == "0" ]] && echo false || echo true)" \
        '{
          quicParams:
            ({congestion:"brutal"}
            + (if $useUp then {brutalUp:$up} else {} end)
            + (if $useDown then {brutalDown:$down} else {} end))
        }')"
    printf ',\n        "finalmask": %s' "${quic_params}"
}

xray_agent_render_hysteria2_inbound() {
    local clients_json="$1"
    local sniffing_json="$2"
    xray_agent_load_protocol_profile "hysteria2"
    xray_agent_export_xray_network_template_vars
    export XRAY_HYSTERIA2_CLIENTS_JSON="${clients_json}"
    export XRAY_HYSTERIA2_MASQUERADE_URL_JSON
    export XRAY_HYSTERIA2_FINALMASK_SUFFIX
    export XRAY_SNIFFING_JSON="${sniffing_json}"
    export XRAY_TLS_DOMAIN="${TLSDomain}"
    XRAY_HYSTERIA2_MASQUERADE_URL_JSON="$(xray_agent_json_string "${Hysteria2MasqueradeURL:-$(xray_agent_hysteria2_default_masquerade_url)}")"
    XRAY_HYSTERIA2_FINALMASK_SUFFIX="$(xray_agent_hysteria2_finalmask_suffix)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}

xray_agent_hysteria2_render_from_current_users() {
    local clients_json sniffing_json
    if [[ -z "${UUID:-}" ]]; then
        xray_agent_prepare_uuid
    fi
    xray_agent_hysteria2_prepare_runtime
    clients_json="$(xray_agent_generate_clients_json "HYSTERIA2" "${UUID}")"
    sniffing_json="$(xray_agent_default_sniffing_json)"
    xray_agent_render_hysteria2_inbound "${clients_json}" "${sniffing_json}"
}

xray_agent_hysteria2_enable_or_reconfigure() {
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    if [[ -z "${coreInstallType}" ]]; then
        echoContent red " ---> 未安装 Xray-core 套餐，请先安装 TLS 或 Reality 套餐"
        return 1
    fi
    xray_agent_hysteria2_render_from_current_users
    reloadCore
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    echoContent green " ---> Hysteria2 已启用，UDP/443"
}

xray_agent_hysteria2_uninstall() {
    local hysteria2_file="${configPath}09_Hysteria2_inbounds.json"
    if [[ -f "${hysteria2_file}" ]]; then
        rm -f "${hysteria2_file}"
        reloadCore
        echoContent green " ---> Hysteria2 已卸载"
    else
        echoContent yellow " ---> Hysteria2 未安装"
    fi
}

xray_agent_hysteria2_show_accounts() {
    local hysteria2_file="${configPath}09_Hysteria2_inbounds.json"
    readConfigHostPathUUID
    if [[ ! -f "${hysteria2_file}" ]]; then
        echoContent yellow " ---> Hysteria2 未安装"
        return 0
    fi
    jq -r '.inbounds[0].settings.clients[]?.auth' "${hysteria2_file}" | tr -d '\r' | while read -r auth; do
        [[ -n "${auth}" ]] || continue
        xray_agent_blank
        echoContent skyBlue " ---> 账号:${auth}"
        defaultBase64Code hysteria2 "${auth}"
    done
}

xray_agent_hysteria2_manage_menu() {
    local hysteria2_status
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    xray_agent_blank
    echoContent skyBlue "功能 1/${totalProgress} : Hysteria2"
    echoContent red "=============================================================="
    echoContent yellow "1.查看 Hysteria2 账号"
    echoContent yellow "2.启用或重配 Hysteria2"
    echoContent yellow "3.卸载 Hysteria2"
    echoContent red "=============================================================="
    read -r -p "请输入:" hysteria2_status
    case "${hysteria2_status}" in
        1) xray_agent_hysteria2_show_accounts ;;
        2) xray_agent_hysteria2_enable_or_reconfigure ;;
        3) xray_agent_hysteria2_uninstall ;;
    esac
}
