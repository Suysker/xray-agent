if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

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

xray_agent_bootstrap_state() {
    checkBTPanel
    if declare -F xray_agent_run_legacy_migrations >/dev/null 2>&1; then
        xray_agent_run_legacy_migrations
    fi
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    xrayAgentLoadFeatureFlags
}
