#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

XRAY_AGENT_LIB_DIR="${XRAY_AGENT_PROJECT_ROOT}/lib"
XRAY_AGENT_TEMPLATE_DIR="${XRAY_AGENT_PROJECT_ROOT}/templates"
XRAY_AGENT_PROFILE_DIR="${XRAY_AGENT_PROJECT_ROOT}/profiles"
XRAY_AGENT_DOCS_DIR="${XRAY_AGENT_PROJECT_ROOT}/docs"
XRAY_AGENT_PACKAGING_DIR="${XRAY_AGENT_PROJECT_ROOT}/packaging"

XRAY_AGENT_ETC_DIR="/etc/xray-agent"
XRAY_AGENT_TLS_DIR="${XRAY_AGENT_ETC_DIR}/tls"
XRAY_AGENT_XRAY_DIR="${XRAY_AGENT_ETC_DIR}/xray"
XRAY_AGENT_XRAY_CONF_DIR="${XRAY_AGENT_XRAY_DIR}/conf"
XRAY_AGENT_XRAY_BINARY="${XRAY_AGENT_XRAY_DIR}/xray"

xray_agent_etc_path() {
    printf '%s/%s\n' "${XRAY_AGENT_ETC_DIR}" "$1"
}

xray_agent_xray_conf_file() {
    printf '%s/%s\n' "${XRAY_AGENT_XRAY_CONF_DIR}" "$1"
}

xray_agent_nginx_conf_file() {
    printf '%s%s\n' "${nginxConfigPath}" "$1"
}

xray_agent_tls_inbound_file() {
    [[ -n "${frontingType:-}" ]] || return 1
    xray_agent_xray_conf_file "${frontingType}.json"
}

xray_agent_reality_inbound_file() {
    [[ -n "${RealityfrontingType:-}" ]] || return 1
    xray_agent_xray_conf_file "${RealityfrontingType}.json"
}

xray_agent_xhttp_inbound_file() {
    xray_agent_xray_conf_file "08_VLESS_XHTTP_inbounds.json"
}

xray_agent_hysteria2_inbound_file() {
    xray_agent_xray_conf_file "09_Hysteria2_inbounds.json"
}

xray_agent_inbound_clients_csv() {
    local inbound_file="$1"
    [[ -f "${inbound_file}" ]] || return 0
    jq -r '.inbounds[0].settings.clients[]?.id' "${inbound_file}" | tr -d '\r' | paste -sd, -
}

xray_agent_hysteria2_clients_csv() {
    local inbound_file="$1"
    [[ -f "${inbound_file}" ]] || return 0
    jq -r '.inbounds[0].settings.clients[]?.auth' "${inbound_file}" | tr -d '\r' | paste -sd, -
}

xray_agent_inbound_port() {
    local inbound_file="$1"
    [[ -f "${inbound_file}" ]] || return 0
    jq -r '.inbounds[0].port // empty' "${inbound_file}" | tr -d '\r'
}

xray_agent_tls_base_path_from_inbound() {
    local inbound_file="$1"
    local fallback_path base_path
    [[ -f "${inbound_file}" ]] || return 0
    fallback_path="$(jq -r '.inbounds[0].settings.fallbacks[]? | select(.path) | .path' "${inbound_file}" | tr -d '\r' | head -1)"
    base_path="${fallback_path#/}"
    case "${base_path}" in
        *vws) base_path="${base_path%vws}" ;;
        *ws) base_path="${base_path%ws}" ;;
    esac
    printf '%s\n' "${base_path}"
}

xray_agent_tls_domain_from_inbound() {
    local inbound_file="$1"
    local cert_path cert_file
    [[ -f "${inbound_file}" ]] || return 0
    cert_path="$(jq -r '.inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile // empty' "${inbound_file}" | tr -d '\r')"
    cert_file="${cert_path##*/}"
    printf '%s\n' "${cert_file%.crt}"
}

xray_agent_nginx_server_name() {
    local nginx_file
    nginx_file="$(xray_agent_nginx_conf_file "alone.conf")"
    [[ -f "${nginx_file}" ]] || return 0
    awk '$1 == "server_name" && $2 ~ /\./ {gsub(";","",$2); print $2; exit}' "${nginx_file}"
}

xray_agent_reality_value() {
    local inbound_file="$1"
    local jq_filter="$2"
    [[ -f "${inbound_file}" ]] || return 0
    jq -r "${jq_filter}" "${inbound_file}" | tr -d '\r'
}

xray_agent_parse_x25519_field() {
    local output="$1"
    local field="$2"
    awk -F ':' -v field="${field}" '
        BEGIN {
            wanted = tolower(field)
            gsub(/[[:space:]_-]/, "", wanted)
        }
        {
            key = tolower($1)
            gsub(/[[:space:]_-]/, "", key)
            if (key == wanted) {
                value = $0
                sub(/^[^:]*:[[:space:]]*/, "", value)
                print value
                exit
            }
        }
    ' <<<"${output}"
}

xray_agent_generate_reality_keypair() {
    local reality_keypair
    [[ -x "${ctlPath:-}" ]] || return 1
    reality_keypair="$("${ctlPath}" x25519 2>/dev/null)" || return 1
    RealityPrivateKey="$(xray_agent_parse_x25519_field "${reality_keypair}" "Private key")"
    RealityPublicKey="$(xray_agent_parse_x25519_field "${reality_keypair}" "Public key")"
    [[ -n "${RealityPrivateKey}" && -n "${RealityPublicKey}" ]]
}

xray_agent_reality_public_key_from_private() {
    local private_key="$1"
    local reality_keypair
    [[ -n "${private_key}" && -x "${ctlPath:-}" ]] || return 1
    reality_keypair="$("${ctlPath}" x25519 -i "${private_key}" 2>/dev/null)" || return 1
    xray_agent_parse_x25519_field "${reality_keypair}" "Public key"
}

xray_agent_ensure_reality_public_key() {
    local derived_public_key
    if [[ -n "${RealityPrivateKey:-}" ]]; then
        derived_public_key="$(xray_agent_reality_public_key_from_private "${RealityPrivateKey}" || true)"
        if [[ -n "${derived_public_key}" ]]; then
            RealityPublicKey="${derived_public_key}"
        fi
    fi
    [[ -n "${RealityPublicKey:-}" ]]
}

xray_agent_reality_public_key_value() {
    if xray_agent_ensure_reality_public_key; then
        printf '%s\n' "${RealityPublicKey}"
    fi
}

xray_agent_xhttp_path_from_inbound() {
    local inbound_file="$1"
    [[ -f "${inbound_file}" ]] || return 0
    jq -r '.inbounds[0].streamSettings.xhttpSettings.path // empty' "${inbound_file}" | tr -d '\r' | awk -F "[/]" '{print $2}'
}

xray_agent_xhttp_mode_from_inbound() {
    local inbound_file="$1"
    [[ -f "${inbound_file}" ]] || return 0
    jq -r '.inbounds[0].streamSettings.xhttpSettings.mode // "auto"' "${inbound_file}" | tr -d '\r'
}

initVar() {
    installType='yum -y install'
    removeType='yum -y remove'
    upgrade="yum -y update"
    xrayCoreCPUVendor=""
    domain=
    path=
    UUID=
    Port=
    totalProgress=1
    coreInstallType=
    currentInstallProtocolType=
    frontingType=
    centosVersion=
    release=
    updateReleaseInfoChange=
    nginxConfigPath=/etc/nginx/conf.d/
    configPath="${XRAY_AGENT_XRAY_CONF_DIR}/"
    ctlPath="${XRAY_AGENT_XRAY_BINARY}"
    prereleaseStatus=false
    sslType=
    TLSDomain=
    RealityfrontingType=
    RealityPrivateKey=
    RealityPublicKey=
    RealityServerNames=
    RealityDestDomain=
    RealityPort=
    RealityShortID=
    XHTTPMode=auto
    reuse443=
}

checkBTPanel() {
    if pgrep -f "BT-Panel" >/dev/null 2>&1; then
        nginxConfigPath=/www/server/panel/vhost/nginx/
    fi
}

checkSystem() {
    if [[ -n $(find /etc -name "redhat-release") ]] || grep </proc/version -q -i "centos"; then
        mkdir -p /etc/yum.repos.d
        if [[ -f "/etc/centos-release" ]]; then
            centosVersion=$(rpm -q centos-release | awk -F "[-]" '{print $3}' | awk -F "[.]" '{print $1}')
            if [[ -z "${centosVersion}" ]] && grep </etc/centos-release -q -i "release 8"; then
                centosVersion=8
            fi
        fi
        release="centos"
        installType='yum -y install'
        removeType='yum -y remove'
        upgrade="yum update -y --skip-broken"
    elif grep </etc/issue -q -i "debian" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "debian" && [[ -f "/proc/version" ]]; then
        release="debian"
        installType='apt -y install'
        upgrade="apt update"
        updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
        removeType='apt -y autoremove'
    elif grep </etc/issue -q -i "ubuntu" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "ubuntu" && [[ -f "/proc/version" ]]; then
        release="ubuntu"
        installType='apt -y install'
        upgrade="apt update"
        updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
        removeType='apt -y autoremove'
        if grep </etc/issue -q -i "16."; then
            release=
        fi
    fi

    if [[ -z ${release} ]]; then
        xray_agent_blank
        echoContent red "本脚本不支持此系统，请将下方日志反馈给开发者"
        xray_agent_blank
        echoContent yellow "$(cat /etc/issue)"
        echoContent yellow "$(cat /proc/version)"
        exit 0
    fi
}

checkCPUVendor() {
    if [[ -n $(which uname) ]]; then
        if [[ "$(uname)" == "Linux" ]]; then
            case "$(uname -m)" in
                amd64 | x86_64)
                    xrayCoreCPUVendor="Xray-linux-64"
                    ;;
                armv8 | aarch64)
                    xrayCoreCPUVendor="Xray-linux-arm64-v8a"
                    ;;
                *)
                    echoContent red "不支持此CPU架构"
                    exit 1
                    ;;
            esac
        fi
    else
        echoContent red "无法识别此CPU架构，默认amd64、x86_64"
        xrayCoreCPUVendor="Xray-linux-64"
    fi
}

xray_agent_run_legacy_migrations() {
    mkdir -p "${XRAY_AGENT_TLS_DIR}" "${XRAY_AGENT_XRAY_CONF_DIR}"
    if [[ -f "$(xray_agent_xray_conf_file "10_outbounds.json")" ]] && [[ ! -f "$(xray_agent_xray_conf_file "10_ipv4_outbounds.json")" ]]; then
        mv "$(xray_agent_xray_conf_file "10_outbounds.json")" "$(xray_agent_xray_conf_file "10_ipv4_outbounds.json")"
    fi
}

readInstallType() {
    coreInstallType=
    reuse443=
    if [[ -d "${XRAY_AGENT_ETC_DIR}" ]]; then
        if [[ -d "/etc/xray-agent/xray" && -f "${ctlPath}" ]]; then
            if [[ -d "/etc/xray-agent/xray/conf" ]] && [[ -f "${configPath}02_VLESS_TCP_inbounds.json" ]] && [[ -f "${configPath}07_VLESS_Reality_TCP_inbounds.json" ]]; then
                coreInstallType=3
            elif [[ -d "/etc/xray-agent/xray/conf" ]] && [[ -f "${configPath}02_VLESS_TCP_inbounds.json" ]]; then
                coreInstallType=1
            elif [[ -d "/etc/xray-agent/xray/conf" ]] && [[ -f "${configPath}07_VLESS_Reality_TCP_inbounds.json" ]]; then
                coreInstallType=2
            fi
            if [[ -f "${nginxConfigPath}alone.stream" ]]; then
                reuse443="y"
            fi
        fi
    fi
}

readInstallProtocolType() {
    currentInstallProtocolType=
    frontingType=
    RealityfrontingType=

    while read -r row; do
        if echo "${row}" | grep -q VLESS_TCP_inbounds; then
            currentInstallProtocolType=${currentInstallProtocolType}'0'
            frontingType=02_VLESS_TCP_inbounds
        fi
        if echo "${row}" | grep -q VLESS_WS_inbounds; then
            currentInstallProtocolType=${currentInstallProtocolType}'1'
        fi
        if echo "${row}" | grep -q VMess_WS_inbounds; then
            currentInstallProtocolType=${currentInstallProtocolType}'2'
        fi
        if echo "${row}" | grep -q VLESS_Reality_TCP_inbounds; then
            currentInstallProtocolType=${currentInstallProtocolType}'7'
            RealityfrontingType=07_VLESS_Reality_TCP_inbounds
        fi
        if echo "${row}" | grep -q VLESS_XHTTP_inbounds; then
            currentInstallProtocolType=${currentInstallProtocolType}'8'
        fi
        if echo "${row}" | grep -q Hysteria2_inbounds; then
            currentInstallProtocolType=${currentInstallProtocolType}'9'
        fi
    done < <(find "${configPath}" -name "*inbounds.json" 2>/dev/null | awk -F "[.]" '{print $1}')
}

readConfigHostPathUUID() {
    path=
    Port=
    UUID=
    domain=
    TLSDomain=
    RealityPort=
    RealityPublicKey=
    RealityServerNames=
    RealityDestDomain=
    RealityShortID=
    XHTTPMode=auto
    Hysteria2Port=
    Hysteria2MasqueradeURL=
    Hysteria2BrutalUpMbps=
    Hysteria2BrutalDownMbps=

    local tls_inbound_file reality_inbound_file xhttp_inbound_file hysteria2_inbound_file
    tls_inbound_file="$(xray_agent_tls_inbound_file 2>/dev/null || true)"
    reality_inbound_file="$(xray_agent_reality_inbound_file 2>/dev/null || true)"
    xhttp_inbound_file="$(xray_agent_xhttp_inbound_file)"
    hysteria2_inbound_file="$(xray_agent_hysteria2_inbound_file)"

    if [[ -n "${tls_inbound_file}" && -f "${tls_inbound_file}" ]]; then
        path="$(xray_agent_tls_base_path_from_inbound "${tls_inbound_file}")"
        Port="$(xray_agent_inbound_port "${tls_inbound_file}")"
        domain="$(xray_agent_nginx_server_name)"
        UUID="$(xray_agent_inbound_clients_csv "${tls_inbound_file}")"
        TLSDomain="$(xray_agent_tls_domain_from_inbound "${tls_inbound_file}")"
    fi

    if [[ -n "${reality_inbound_file}" && -f "${reality_inbound_file}" ]]; then
        if [[ -z "${path}" ]]; then
            UUID="$(xray_agent_inbound_clients_csv "${reality_inbound_file}")"
        fi
        RealityServerNames="$(xray_agent_reality_value "${reality_inbound_file}" '.inbounds[0].streamSettings.realitySettings.serverNames | join(",")')"
        RealityPublicKey="$(xray_agent_reality_value "${reality_inbound_file}" '.inbounds[0].streamSettings.realitySettings.publicKey // .inbounds[0].streamSettings.realitySettings.password // empty')"
        RealityPort="$(xray_agent_inbound_port "${reality_inbound_file}")"
        RealityDestDomain="$(xray_agent_reality_value "${reality_inbound_file}" '.inbounds[0].streamSettings.realitySettings.target // .inbounds[0].streamSettings.realitySettings.dest // empty')"
        RealityPrivateKey="$(xray_agent_reality_value "${reality_inbound_file}" '.inbounds[0].streamSettings.realitySettings.privateKey')"
        RealityShortID="$(xray_agent_reality_value "${reality_inbound_file}" '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty')"
        xray_agent_ensure_reality_public_key || true
        if [[ -z "${path}" && -f "${xhttp_inbound_file}" ]]; then
            path="$(xray_agent_xhttp_path_from_inbound "${xhttp_inbound_file}")"
        fi
    fi

    if [[ -f "${xhttp_inbound_file}" ]]; then
        XHTTPMode="$(xray_agent_xhttp_mode_from_inbound "${xhttp_inbound_file}")"
    fi

    if [[ -f "${hysteria2_inbound_file}" ]]; then
        Hysteria2Port="$(xray_agent_inbound_port "${hysteria2_inbound_file}")"
        Hysteria2MasqueradeURL="$(jq -r '.inbounds[0].streamSettings.hysteriaSettings.masquerade.url // empty' "${hysteria2_inbound_file}" | tr -d '\r')"
        Hysteria2BrutalUpMbps="$(jq -r '.inbounds[0].streamSettings.finalmask.quicParams.brutalUp // empty' "${hysteria2_inbound_file}" | tr -d '\r' | awk '{print $1}')"
        Hysteria2BrutalDownMbps="$(jq -r '.inbounds[0].streamSettings.finalmask.quicParams.brutalDown // empty' "${hysteria2_inbound_file}" | tr -d '\r' | awk '{print $1}')"
        if [[ -z "${TLSDomain}" ]]; then
            TLSDomain="$(xray_agent_tls_domain_from_inbound "${hysteria2_inbound_file}")"
        fi
        if [[ -z "${domain}" ]]; then
            domain="${TLSDomain}"
        fi
        if [[ -z "${UUID}" ]]; then
            UUID="$(xray_agent_hysteria2_clients_csv "${hysteria2_inbound_file}")"
        fi
    fi
}

showInstallStatus() {
    if [[ -n "${coreInstallType}" ]]; then
        if [[ -n $(pgrep -f xray/xray) ]]; then
            xray_agent_blank
            echoContent yellow "核心: Xray-core[运行中]"
        else
            xray_agent_blank
            echoContent yellow "核心: Xray-core[未运行]"
        fi

        readInstallProtocolType

        if [[ -n ${currentInstallProtocolType} ]]; then
            xray_agent_print_inline yellow "已安装协议: "
        fi
        if echo "${currentInstallProtocolType}" | grep -q 0; then
            xray_agent_print_inline yellow "VLESS+TCP[TLS] "
        fi
        if echo "${currentInstallProtocolType}" | grep -q 1; then
            xray_agent_print_inline yellow "VLESS+WS[TLS] "
        fi
        if echo "${currentInstallProtocolType}" | grep -q 2; then
            xray_agent_print_inline yellow "VMess+WS[TLS] "
        fi
        if echo "${currentInstallProtocolType}" | grep -q 7; then
            xray_agent_print_inline yellow "VLESS+TCP[Reality] "
        fi
        if echo "${currentInstallProtocolType}" | grep -q 8; then
            xray_agent_print_inline yellow "VLESS+XHTTP "
        fi
        if echo "${currentInstallProtocolType}" | grep -q 9; then
            xray_agent_print_inline yellow "Hysteria2 "
        fi
    fi
}

xray_agent_bootstrap_state() {
    checkBTPanel
    if declare -F xray_agent_run_legacy_migrations >/dev/null 2>&1; then
        xray_agent_run_legacy_migrations
    fi
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
}
