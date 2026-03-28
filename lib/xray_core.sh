xray_agent_generate_clients_json() {
    local protocol="$1"
    local uuid_csv="$2"
    jq -nc --arg protocol "${protocol}" --arg uuidCsv "${uuid_csv}" '
      ($uuidCsv | split(",") | map(select(length > 0))) as $uuids
      | $uuids
      | map(
          if $protocol == "VLESS_TCP" then
            {id: ., flow: "xtls-rprx-vision"}
          elif $protocol == "VLESS_XHTTP" then
            {id: .}
          elif $protocol == "VMESS_WS" then
            {id: ., alterId: 0}
          else
            {id: .}
          end
        )'
}

generate_clients() {
    if declare -F xray_agent_generate_clients_json >/dev/null 2>&1; then
        xray_agent_generate_clients_json "$1" "$2"
        return 0
    fi
    echo "[]"
}

xray_agent_generate_hysteria_users_json() {
    local uuid_csv="$1"
    jq -nc --arg uuidCsv "${uuid_csv}" '($uuidCsv | split(",") | map(select(length > 0))) | map({password: .})'
}

xray_agent_prepare_uuid() {
    if [[ -n "${UUID}" ]]; then
        read -r -p "读取到上次安装记录，是否使用上次安装时的UUID ？[y/n]:" historyUUIDStatus
        if [[ "${historyUUIDStatus}" != "y" ]]; then
            echoContent yellow "请输入自定义UUID[需合法](支持以逗号为分割输入多个)，[回车]随机UUID"
            read -r -p 'UUID:' UUID
        fi
    else
        echoContent yellow "请输入自定义UUID[需合法](支持以逗号为分割输入多个)，[回车]随机UUID"
        read -r -p 'UUID:' UUID
    fi
    if [[ -z "${UUID}" ]]; then
        UUID=$(${ctlPath} uuid)
    fi
}

xray_agent_prepare_reality_keys() {
    if [[ -n "${RealityPublicKey}" ]]; then
        read -r -p "读取到上次安装记录，是否使用上次安装时的PublicKey/PrivateKey ？[y/n]:" historyKeyStatus
        if [[ "${historyKeyStatus}" != "y" ]]; then
            local reality_keypair
            reality_keypair=$(${ctlPath} x25519)
            RealityPrivateKey=$(echo "${reality_keypair}" | head -1 | awk '{print $3}')
            RealityPublicKey=$(echo "${reality_keypair}" | tail -n 1 | awk '{print $3}')
        fi
    else
        local reality_keypair
        reality_keypair=$(${ctlPath} x25519)
        RealityPrivateKey=$(echo "${reality_keypair}" | head -1 | awk '{print $3}')
        RealityPublicKey=$(echo "${reality_keypair}" | tail -n 1 | awk '{print $3}')
    fi
    if [[ -z "${RealityShortID}" ]]; then
        RealityShortID=$(openssl rand -hex 4 2>/dev/null)
    fi
}

xray_agent_render_common_xray_configs() {
    local keepconfigstatus="n"
    if [[ -f "${configPath}10_ipv4_outbounds.json" ]] || [[ -f "${configPath}09_routing.json" ]]; then
        read -r -p "是否保留路由和分流规则 ？[y/n]:" keepconfigstatus
    fi
    if [[ "${keepconfigstatus}" == "y" ]]; then
        return 0
    fi
    export XRAY_LOG_ERROR_PATH="/etc/xray-agent/xray/error.log"
    export XRAY_LOG_LEVEL="warning"
    export XRAY_POLICY_HANDSHAKE=$((RANDOM % 4 + 2))
    export XRAY_POLICY_CONN_IDLE=$(((RANDOM % 11) * 30 + 300))
    export XRAY_OUTBOUNDS_JSON
    export XRAY_ROUTING_RULES_JSON
    export XRAY_ROUTING_DOMAIN_STRATEGY="AsIs"
    export XRAY_DNS_SERVERS_JSON
    export XRAY_DNS_QUERY_STRATEGY="UseIP"
    XRAY_OUTBOUNDS_JSON="$(xray_agent_default_outbounds_json)"
    XRAY_ROUTING_RULES_JSON="$(xray_agent_default_routing_rules_json)"
    XRAY_DNS_SERVERS_JSON="$(xray_agent_default_dns_servers_json)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/00_log.json.tpl" "${configPath}00_log.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/01_policy.json.tpl" "${configPath}01_policy.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/09_routing.json.tpl" "${configPath}09_routing.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/10_outbounds.json.tpl" "${configPath}10_ipv4_outbounds.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/11_dns.json.tpl" "${configPath}11_dns.json"
}

xray_agent_default_xhttp_headers_json() {
    jq -nc '{User-Agent: ["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36"]}'
}

xray_agent_render_vless_ws_legacy_config() {
    export XRAY_CLIENTS_JSON="$1"
    export XRAY_SNIFFING_JSON="$2"
    export XRAY_WS_PATH="/${path}ws"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbound_vless_ws_tls.json.tpl" "${configPath}03_VLESS_WS_inbounds.json"
}

xray_agent_render_vmess_ws_legacy_config() {
    export XRAY_CLIENTS_JSON="$1"
    export XRAY_SNIFFING_JSON="$2"
    export XRAY_WS_PATH="/${path}vws"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbound_vmess_ws_tls.json.tpl" "${configPath}05_VMess_WS_inbounds.json"
}

xray_agent_render_tls_bundle() {
    xray_agent_prepare_uuid
    xray_agent_render_common_xray_configs
    local accept_proxy_protocol="false"
    if [[ "${reuse443}" == "y" ]]; then
        accept_proxy_protocol="true"
    fi
    local vless_tcp_clients_json vless_xhttp_clients_json vmess_clients_json sniffing_json
    export XRAY_CLIENTS_JSON
    export XRAY_FALLBACKS_JSON='[{"path":"/'"${path}"'ws","dest":31297,"xver":1},{"path":"/'"${path}"'vws","dest":31299,"xver":1},{"dest":31305,"xver":0}]'
    export XRAY_SOCKOPT_JSON
    export XRAY_SNIFFING_JSON
    export XRAY_INBOUND_PORT="${Port}"
    export XRAY_INBOUND_TAG="VLESSTCP"
    export XRAY_ACCEPT_PROXY_PROTOCOL="${accept_proxy_protocol}"
    export XRAY_TLS_DOMAIN="${TLSDomain}"
    vless_tcp_clients_json="$(xray_agent_generate_clients_json "VLESS_TCP" "${UUID}")"
    vless_xhttp_clients_json="$(xray_agent_generate_clients_json "VLESS_XHTTP" "${UUID}")"
    vmess_clients_json="$(xray_agent_generate_clients_json "VMESS_WS" "${UUID}")"
    sniffing_json="$(xray_agent_default_sniffing_json)"
    XRAY_CLIENTS_JSON="${vless_tcp_clients_json}"
    XRAY_SOCKOPT_JSON="$(xray_agent_sockopt_with_proxy_protocol "${accept_proxy_protocol}")"
    XRAY_SNIFFING_JSON="${sniffing_json}"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbound_vless_tls_vision.json.tpl" "${configPath}02_VLESS_TCP_inbounds.json"
    xray_agent_render_vless_ws_legacy_config "${vless_xhttp_clients_json}" "${sniffing_json}"
    xray_agent_render_vmess_ws_legacy_config "${vmess_clients_json}" "${sniffing_json}"
    export XRAY_INBOUND_PORT="31305"
    export XRAY_INBOUND_TAG="VLESSXHTTP"
    export XRAY_XHTTP_PATH="/${path}"
    export XRAY_XHTTP_MODE="${XHTTPMode:-auto}"
    export XRAY_XHTTP_HEADERS_JSON
    XRAY_CLIENTS_JSON="${vless_xhttp_clients_json}"
    XRAY_SOCKOPT_JSON="$(xray_agent_sockopt_with_proxy_protocol "false")"
    XRAY_XHTTP_HEADERS_JSON="$(xray_agent_default_xhttp_headers_json)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbound_vless_xhttp_tls.json.tpl" "${configPath}08_VLESS_XHTTP_inbounds.json"
    if declare -F xray_agent_apply_tls_feature_patches >/dev/null 2>&1; then
        xray_agent_apply_tls_feature_patches "${configPath}02_VLESS_TCP_inbounds.json" "${configPath}08_VLESS_XHTTP_inbounds.json"
    fi
}

xray_agent_render_reality_bundle() {
    xray_agent_prepare_reality_keys
    xray_agent_prepare_uuid
    xray_agent_render_common_xray_configs
    local accept_proxy_protocol="false"
    if [[ "${reuse443}" == "y" ]]; then
        accept_proxy_protocol="true"
    fi
    export XRAY_CLIENTS_JSON
    export XRAY_FALLBACKS_JSON='[{"dest":31305,"xver":0}]'
    export XRAY_SOCKOPT_JSON
    export XRAY_SNIFFING_JSON
    export XRAY_INBOUND_PORT="${RealityPort}"
    export XRAY_INBOUND_TAG="VLESSReality"
    export XRAY_ACCEPT_PROXY_PROTOCOL="${accept_proxy_protocol}"
    export XRAY_REALITY_DEST="${RealityDestDomain}"
    export XRAY_REALITY_SERVER_NAMES_JSON
    export XRAY_REALITY_PRIVATE_KEY="${RealityPrivateKey}"
    export XRAY_REALITY_PUBLIC_KEY="${RealityPublicKey}"
    export XRAY_REALITY_SHORT_IDS_JSON
    XRAY_CLIENTS_JSON="$(xray_agent_generate_clients_json "VLESS_TCP" "${UUID}")"
    XRAY_SOCKOPT_JSON="$(xray_agent_sockopt_with_proxy_protocol "${accept_proxy_protocol}")"
    XRAY_SNIFFING_JSON="$(xray_agent_default_sniffing_json)"
    XRAY_REALITY_SERVER_NAMES_JSON="$(printf '%s' "${RealityServerNames}" | jq -R 'split(",")')"
    XRAY_REALITY_SHORT_IDS_JSON="$(printf '%s' "${RealityShortID}" | jq -R 'split(",") | map(select(length > 0))')"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbound_vless_reality_vision.json.tpl" "${configPath}07_VLESS_Reality_TCP_inbounds.json"
    export XRAY_INBOUND_PORT="31305"
    export XRAY_INBOUND_TAG="VLESSXHTTP"
    export XRAY_XHTTP_PATH="/${path}"
    export XRAY_XHTTP_MODE="${XHTTPMode:-auto}"
    export XRAY_XHTTP_HEADERS_JSON
    XRAY_CLIENTS_JSON="$(xray_agent_generate_clients_json "VLESS_XHTTP" "${UUID}")"
    XRAY_SOCKOPT_JSON="$(xray_agent_sockopt_with_proxy_protocol "false")"
    XRAY_XHTTP_HEADERS_JSON="$(xray_agent_default_xhttp_headers_json)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbound_vless_xhttp_reality.json.tpl" "${configPath}08_VLESS_XHTTP_inbounds.json"
    if declare -F xray_agent_apply_reality_feature_patches >/dev/null 2>&1; then
        xray_agent_apply_reality_feature_patches "${configPath}07_VLESS_Reality_TCP_inbounds.json" "${configPath}08_VLESS_XHTTP_inbounds.json"
    fi
}

initXrayRealityConfig() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 初始化 Xray-core Reality配置"
    xray_agent_render_reality_bundle
}

initXrayConfig() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 初始化Xray配置"
    xray_agent_render_tls_bundle
}

xray_agent_render_hysteria2_profile() {
    xray_agent_prepare_uuid
    xray_agent_render_common_xray_configs
    export XRAY_INBOUND_PORT="${Port:-8443}"
    export XRAY_INBOUND_TAG="HYSTERIA2"
    export XRAY_TLS_DOMAIN="${TLSDomain}"
    export XRAY_HYSTERIA_USERS_JSON
    export XRAY_HYSTERIA_SETTINGS_JSON
    export XRAY_SOCKOPT_JSON
    export XRAY_SNIFFING_JSON
    XRAY_HYSTERIA_USERS_JSON="$(xray_agent_generate_hysteria_users_json "${UUID}")"
    XRAY_HYSTERIA_SETTINGS_JSON="$(jq -nc '{password: "", up_mbps: 200, down_mbps: 1000}')"
    XRAY_SOCKOPT_JSON="$(xray_agent_default_sockopt_json)"
    XRAY_SNIFFING_JSON="$(xray_agent_default_sniffing_json)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbound_hysteria2.json.tpl" "${configPath}12_HYSTERIA2_inbounds.json"
    if declare -F xray_agent_apply_hysteria2_feature_patches >/dev/null 2>&1; then
        xray_agent_apply_hysteria2_feature_patches "${configPath}12_HYSTERIA2_inbounds.json"
    fi
}

xray_agent_render_local_tun_profile() {
    xray_agent_render_common_xray_configs
    export XRAY_INBOUND_TAG="TUN"
    export XRAY_TUN_MTU="1500"
    export XRAY_SNIFFING_JSON
    XRAY_SNIFFING_JSON="$(xray_agent_default_sniffing_json)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbound_tun.json.tpl" "${configPath}20_TUN_inbounds.json"
    if declare -F xray_agent_apply_tun_feature_patches >/dev/null 2>&1; then
        xray_agent_apply_tun_feature_patches "${configPath}20_TUN_inbounds.json" "${configPath}09_routing.json"
    fi
}

handleXray() {
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]] && [[ -n $(find /etc/systemd/system/ -name "xray.service") ]]; then
        if [[ -z $(pgrep -f "xray/xray") ]] && [[ "$1" == "start" ]]; then
            systemctl start xray.service
        elif [[ -n $(pgrep -f "xray/xray") ]] && [[ "$1" == "stop" ]]; then
            systemctl stop xray.service
        fi
    fi
    sleep 0.8
    if [[ "$1" == "start" && -z $(pgrep -f "xray/xray") ]]; then
        xray_agent_error "Xray启动失败"
    fi
    if [[ "$1" == "stop" && -n $(pgrep -f "xray/xray") ]]; then
        xray_agent_error "xray关闭失败"
    fi
}

installXray() {
    readInstallType
    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装Xray"
    if [[ -z "${coreInstallType}" ]]; then
        version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -1)
        if wget --help | grep -q show-progress; then
            wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
        else
            wget -c -P /etc/xray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip" >/dev/null 2>&1
        fi
        unzip -o "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip" -d /etc/xray-agent/xray >/dev/null
        rm -rf "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip"
        version=$(curl -s https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases | jq -r '.[]|.tag_name' | head -1)
        rm /etc/xray-agent/xray/geo* >/dev/null 2>&1
        wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geosite.dat"
        wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geoip.dat"
        chmod 655 "${ctlPath}"
    else
        read -r -p "是否更新、升级？[y/n]:" reInstallXrayStatus
        if [[ "${reInstallXrayStatus}" == "y" ]]; then
            rm -f "${ctlPath}"
            installXray "$1"
        fi
    fi
}

installXrayService() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 配置Xray开机自启"
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]]; then
        rm -rf /etc/systemd/system/xray.service
        execStart="${ctlPath} run -confdir /etc/xray-agent/xray/conf"
        cat <<EOF >/etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
User=root
Nice=-20
ExecStart=${execStart}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable xray.service
    fi
}

auto_update_geodata() {
    if [[ -f "/etc/xray-agent/xray/xray" ]] || [[ -f "/etc/xray-agent/xray/geosite.dat" ]] || [[ -f "/etc/xray-agent/xray/geoip.dat" ]]; then
        cat >/etc/xray-agent/auto_update_geodata.sh <<EOF
#!/bin/sh
wget -O /etc/xray-agent/xray/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat && wget -O /etc/xray-agent/xray/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat && systemctl restart xray
EOF
        chmod +x /etc/xray-agent/auto_update_geodata.sh
        crontab -l >/etc/xray-agent/backup_crontab.cron
        historyCrontab=$(sed '/auto_update_geodata.sh/d' /etc/xray-agent/backup_crontab.cron)
        echo "${historyCrontab}" >/etc/xray-agent/backup_crontab.cron
        echo "30 1 * * 1 /bin/bash /etc/xray-agent/auto_update_geodata.sh >> /etc/xray-agent/crontab_geo.log 2>&1" >>/etc/xray-agent/backup_crontab.cron
        crontab /etc/xray-agent/backup_crontab.cron
    else
        crontab -l | grep -v 'auto_update_geodata.sh' | crontab -
    fi
}

checkGFWStatue() {
    readInstallType
    echoContent skyBlue "\n进度 $1/${totalProgress} : 验证服务启动状态"
    if [[ -n "${coreInstallType}" ]] && [[ -n $(pgrep -f xray/xray) ]]; then
        echoContent green " ---> 服务启动成功"
    else
        xray_agent_error " ---> 服务启动失败，请检查终端是否有日志打印"
    fi
}

reloadCore() {
    handleXray stop
    handleXray start
}

xrayVersionManageMenu() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : Xray版本管理"
    echoContent red "\n=============================================================="
    echoContent yellow "1.升级Xray-core"
    echoContent yellow "2.升级Xray-core 预览版"
    echoContent yellow "3.回退Xray-core"
    echoContent yellow "4.关闭Xray-core"
    echoContent yellow "5.打开Xray-core"
    echoContent yellow "6.重启Xray-core"
    echoContent yellow "7.更新geosite、geoip"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectXrayType
    case "${selectXrayType}" in
        1)
            updateXray
            ;;
        2)
            prereleaseStatus=true
            updateXray
            ;;
        3)
            curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -5 | awk '{print ""NR""":"$0}'
            read -r -p "请输入要回退的版本:" selectXrayVersionType
            version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -5 | awk '{print ""NR""":"$0}' | grep "${selectXrayVersionType}:" | awk -F "[:]" '{print $2}')
            if [[ -n "${version}" ]]; then
                updateXray "${version}"
            fi
            ;;
        4)
            handleXray stop
            ;;
        5)
            handleXray start
            ;;
        6)
            reloadCore
            ;;
        7)
            /etc/xray-agent/auto_update_geodata.sh
            ;;
    esac
}

updateXray() {
    readInstallType
    prereleaseStatus=${prereleaseStatus:-false}
    if [[ -n "$1" ]]; then
        version=$1
    else
        version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r ".[]|select (.prerelease==${prereleaseStatus})|.tag_name" | head -1)
    fi
    if [[ -z "${coreInstallType}" ]]; then
        if wget --help | grep -q show-progress; then
            wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
        else
            wget -c -P /etc/xray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip" >/dev/null 2>&1
        fi
        unzip -o "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip" -d /etc/xray-agent/xray >/dev/null
        rm -rf "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip"
        chmod 655 "${ctlPath}"
        handleXray stop
        handleXray start
    else
        if [[ -n "$1" ]]; then
            read -r -p "回退版本为${version}，是否继续？[y/n]:" rollbackXrayStatus
            if [[ "${rollbackXrayStatus}" == "y" ]]; then
                handleXray stop
                rm -f "${ctlPath}"
                updateXray "${version}"
            fi
        else
            read -r -p "最新版本为:${version}，是否更新？[y/n]:" installXrayStatus
            if [[ "${installXrayStatus}" == "y" ]]; then
                rm -f "${ctlPath}"
                updateXray
            fi
        fi
    fi
}

checkLog() {
    if [[ -z "${coreInstallType}" ]]; then
        xray_agent_error " ---> 没有检测到安装目录，请执行脚本安装内容"
    fi
    local logStatus=false
    if grep -q "access" "${configPath}00_log.json"; then
        logStatus=true
    fi
    echoContent skyBlue "\n功能 $1/${totalProgress} : 查看日志"
    echoContent red "\n=============================================================="
    if [[ "${logStatus}" == "false" ]]; then
        echoContent yellow "1.打开access日志"
    else
        echoContent yellow "1.关闭access日志"
    fi
    echoContent yellow "2.监听access日志"
    echoContent yellow "3.监听error日志"
    echoContent yellow "4.查看证书定时任务日志"
    echoContent yellow "5.查看证书安装日志"
    echoContent yellow "6.清空日志"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectAccessLogType
    local configPathLog="${configPath//conf\//}"
    case ${selectAccessLogType} in
        1)
            if [[ "${logStatus}" == "false" ]]; then
                cat <<EOF >"${configPath}00_log.json"
{
    "log": {
        "access": "${configPathLog}access.log",
        "error": "${configPathLog}error.log",
        "loglevel": "debug"
    }
}
EOF
            else
                cat <<EOF >"${configPath}00_log.json"
{
    "log": {
        "error": "${configPathLog}error.log",
        "loglevel": "warning"
    }
}
EOF
            fi
            reloadCore
            ;;
        2)
            tail -f "${configPathLog}access.log"
            ;;
        3)
            tail -f "${configPathLog}error.log"
            ;;
        4)
            tail -n 100 /etc/xray-agent/crontab_tls.log
            ;;
        5)
            tail -n 100 /etc/xray-agent/tls/acme.log
            ;;
        6)
            echo >"${configPathLog}access.log"
            echo >"${configPathLog}error.log"
            ;;
    esac
}

xrayCoreInstall() {
    totalProgress=11
    installTools 1
    initTLSNginxConfig 2
    handleXray stop
    installTLS 3 0
    installXray 4
    installXrayService 5
    randomPathFunction 6
    customPortFunction "Vision"
    updateRedirectNginxConf "Vision" 7
    xray_agent_render_tls_bundle
    installCronTLS 9
    reloadCore
    auto_update_geodata
    checkGFWStatue 10
    showAccounts 11
}

xrayCoreInstall_Reality() {
    totalProgress=8
    installTools 1
    handleXray stop
    installXray 2
    installXrayService 3
    initTLSRealityConfig 4
    xray_agent_tls_warning_for_target "${RealityDestDomain}"
    randomPathFunction 5
    customPortFunction "Reality"
    xray_agent_tls_warning_for_xhttp_port "${RealityPort}"
    updateRedirectNginxConf "Reality" 5.5
    xray_agent_render_reality_bundle
    reloadCore
    auto_update_geodata
    checkGFWStatue 7
    showAccounts 8
}

xray_agent_install_hysteria2_native() {
    totalProgress=9
    installTools 1
    initTLSNginxConfig 2
    handleXray stop
    installTLS 3 0
    installXray 4
    installXrayService 5
    echoContent yellow "请输入 Hysteria2 监听端口[回车默认 8443]"
    read -r -p "端口:" Port
    if [[ -z "${Port}" ]]; then
        Port=8443
    fi
    checkPort "${Port}"
    allowPort "${Port}" udp
    allowPort "${Port}" tcp
    xray_agent_render_hysteria2_profile
    reloadCore
    auto_update_geodata
    checkGFWStatue 8
}

updateXRayAgent() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 更新xray-agent脚本"
    rm -rf /etc/xray-agent/install.sh
    if wget --help | grep -q show-progress; then
        wget -c -q --show-progress -P /etc/xray-agent/ -N --no-check-certificate "${XRAY_AGENT_PROJECT_RAW_INSTALL_URL}"
    else
        wget -c -q -P /etc/xray-agent/ -N --no-check-certificate "${XRAY_AGENT_PROJECT_RAW_INSTALL_URL}"
    fi
    sudo chmod 700 /etc/xray-agent/install.sh
}
