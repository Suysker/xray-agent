if [[ -z "${XRAY_AGENT_PROJECT_ROOT}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

XRAY_AGENT_LIB_DIR="${XRAY_AGENT_PROJECT_ROOT}/lib"
XRAY_AGENT_TEMPLATE_DIR="${XRAY_AGENT_PROJECT_ROOT}/templates"
XRAY_AGENT_PROFILE_DIR="${XRAY_AGENT_PROJECT_ROOT}/profiles"
XRAY_AGENT_DOCS_DIR="${XRAY_AGENT_PROJECT_ROOT}/docs"
XRAY_AGENT_FEATURE_DIR="${XRAY_AGENT_LIB_DIR}/features"

XRAY_AGENT_ETC_DIR="/etc/xray-agent"
XRAY_AGENT_TLS_DIR="${XRAY_AGENT_ETC_DIR}/tls"
XRAY_AGENT_XRAY_DIR="${XRAY_AGENT_ETC_DIR}/xray"
XRAY_AGENT_XRAY_CONF_DIR="${XRAY_AGENT_XRAY_DIR}/conf"
XRAY_AGENT_XRAY_BINARY="${XRAY_AGENT_XRAY_DIR}/xray"

initVar() {
    installType='yum -y install'
    removeType='yum -y remove'
    upgrade="yum -y update"
    echoType='echo -e'
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
        if echo "${row}" | grep -q HYSTERIA2_inbounds; then
            currentInstallProtocolType=${currentInstallProtocolType}'9'
        fi
        if echo "${row}" | grep -q TUN_inbounds; then
            currentInstallProtocolType=${currentInstallProtocolType}'T'
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

checkBTPanel() {
    if pgrep -f "BT-Panel" >/dev/null 2>&1; then
        nginxConfigPath=/www/server/panel/vhost/nginx/
    fi
}

showInstallStatus() {
    if [[ -n "${coreInstallType}" ]]; then
        if [[ -n $(pgrep -f xray/xray) ]]; then
            echoContent yellow "\n核心: Xray-core[运行中]"
        else
            echoContent yellow "\n核心: Xray-core[未运行]"
        fi

        readInstallProtocolType

        if [[ -n ${currentInstallProtocolType} ]]; then
            echoContent yellow "已安装协议: \c"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 0; then
            echoContent yellow "VLESS+TCP[TLS] \c"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 1; then
            echoContent yellow "VLESS+WS[TLS] \c"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 2; then
            echoContent yellow "VMess+WS[TLS] \c"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 7; then
            echoContent yellow "VLESS+TCP[Reality] \c"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 8; then
            echoContent yellow "VLESS+XHTTP \c"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 9; then
            echoContent yellow "Hysteria2 \c"
        fi
        if echo "${currentInstallProtocolType}" | grep -q T; then
            echoContent yellow "TUN \c"
        fi
    fi
}

getPublicIP() {
    local currentIP=
    currentIP=$(curl -s -4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${currentIP}" ]]; then
        currentIP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    fi
    echo "${currentIP}"
}

xrayAgentLoadFeatureFlags() {
    local feature_flags_path="/etc/xray-agent/feature-flags.env"
    if [[ -r "${feature_flags_path}" ]]; then
        source "${feature_flags_path}"
    fi
}

xrayAgentPersistFeatureFlags() {
    local feature_flags_path="/etc/xray-agent/feature-flags.env"
    mkdir -p /etc/xray-agent
    cat <<EOF >"${feature_flags_path}"
XRAY_AGENT_ENABLE_FINALMASK=${XRAY_AGENT_ENABLE_FINALMASK:-false}
XRAY_AGENT_FINALMASK_MODE=${XRAY_AGENT_FINALMASK_MODE:-header}
XRAY_AGENT_FINALMASK_QUIC_PARAMS=${XRAY_AGENT_FINALMASK_QUIC_PARAMS:-off}
XRAY_AGENT_ENABLE_ECH=${XRAY_AGENT_ENABLE_ECH:-false}
XRAY_AGENT_ECH_CONFIG=${XRAY_AGENT_ECH_CONFIG:-example-ech-config}
XRAY_AGENT_ENABLE_VLESS_ENCRYPTION=${XRAY_AGENT_ENABLE_VLESS_ENCRYPTION:-false}
XRAY_AGENT_VLESS_ENCRYPTION_MODE=${XRAY_AGENT_VLESS_ENCRYPTION_MODE:-mlkem768}
XRAY_AGENT_BROWSER_HEADERS=${XRAY_AGENT_BROWSER_HEADERS:-chrome}
XRAY_AGENT_TRUSTED_X_FORWARDED_FOR=${XRAY_AGENT_TRUSTED_X_FORWARDED_FOR:-127.0.0.1}
XRAY_AGENT_TUN_PROCESS_NAMES=${XRAY_AGENT_TUN_PROCESS_NAMES:-curl,wget,bash}
EOF
}

xray_agent_bootstrap_state() {
    initVar
    checkBTPanel
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    xrayAgentLoadFeatureFlags
}
