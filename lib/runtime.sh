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
    configPath=/etc/xray-agent/xray/conf/
    ctlPath=/etc/xray-agent/xray/xray
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
    mkdir -p /etc/xray-agent/tls /etc/xray-agent/xray/conf
    if [[ -f "/etc/xray-agent/xray/conf/10_outbounds.json" ]] && [[ ! -f "/etc/xray-agent/xray/conf/10_ipv4_outbounds.json" ]]; then
        mv /etc/xray-agent/xray/conf/10_outbounds.json /etc/xray-agent/xray/conf/10_ipv4_outbounds.json
    fi
}

readInstallType() {
    coreInstallType=
    reuse443=
    if [[ -d "/etc/xray-agent" ]]; then
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

    if [[ -f "${configPath}${frontingType}.json" ]]; then
        local fallback
        fallback=$(jq -r -c '.inbounds[0].settings.fallbacks[]|select(.path)' "${configPath}${frontingType}.json" | head -1)
        path=$(echo "${fallback}" | jq -r .path | awk -F "[/]" '{print $2}' | awk -F "[w][s]" '{print $1}')
        if [[ -z "${path}" ]]; then
            path=$(echo "${fallback}" | jq -r .path | awk -F "[/]" '{print $2}' | awk -F "[v][w][s]" '{print $1}')
        fi
        Port=$(jq -r .inbounds[0].port "${configPath}${frontingType}.json")
        domain=$(grep "server_name" "${nginxConfigPath}alone.conf" | awk '$2 ~ /\./ {gsub(";","",$2); print $2; exit}')
        UUID=$(jq -r '.inbounds[0].settings.clients[] | .id' "${configPath}${frontingType}.json" | paste -sd, -)
        TLSDomain=$(jq -r .inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile "${configPath}${frontingType}.json" | awk -F "[/]" '{print $5}' | awk -F "[.][c][r][t]" '{print $1}')
    fi

    if [[ -f "${configPath}${RealityfrontingType}.json" ]]; then
        if [[ -z "${path}" ]]; then
            UUID=$(jq -r '.inbounds[0].settings.clients[] | .id' "${configPath}${RealityfrontingType}.json" | paste -sd, -)
        fi
        RealityServerNames=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames | join(",")' "${configPath}${RealityfrontingType}.json")
        RealityPublicKey=$(jq -r .inbounds[0].streamSettings.realitySettings.publicKey "${configPath}${RealityfrontingType}.json")
        RealityPort=$(jq -r .inbounds[0].port "${configPath}${RealityfrontingType}.json")
        RealityDestDomain=$(jq -r .inbounds[0].streamSettings.realitySettings.dest "${configPath}${RealityfrontingType}.json")
        RealityPrivateKey=$(jq -r .inbounds[0].streamSettings.realitySettings.privateKey "${configPath}${RealityfrontingType}.json")
        RealityShortID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "${configPath}${RealityfrontingType}.json")
        if [[ -z "${path}" ]] && [[ -f "${configPath}08_VLESS_XHTTP_inbounds.json" ]]; then
            path=$(jq -r .inbounds[0].streamSettings.xhttpSettings.path "${configPath}08_VLESS_XHTTP_inbounds.json" | awk -F "[/]" '{print $2}')
        fi
    fi

    if [[ -f "${configPath}08_VLESS_XHTTP_inbounds.json" ]]; then
        XHTTPMode=$(jq -r '.inbounds[0].streamSettings.xhttpSettings.mode // "auto"' "${configPath}08_VLESS_XHTTP_inbounds.json")
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
