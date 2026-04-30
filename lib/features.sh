#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

aliasInstall() {
    if [[ -f "$HOME/install.sh" ]] && [[ -d "/etc/xray-agent" ]] && grep <"$HOME/install.sh" -q "xray-agent"; then
        mv "$HOME/install.sh" /etc/xray-agent/install.sh
        local vasmaType=
        if [[ -d "/usr/bin/" ]]; then
            if [[ ! -f "/usr/bin/vasma" ]]; then
                ln -s /etc/xray-agent/install.sh /usr/bin/vasma
                chmod 700 /usr/bin/vasma
                vasmaType=true
            fi
            rm -rf "$HOME/install.sh"
        elif [[ -d "/usr/sbin" ]]; then
            if [[ ! -f "/usr/sbin/vasma" ]]; then
                ln -s /etc/xray-agent/install.sh /usr/sbin/vasma
                chmod 700 /usr/sbin/vasma
                vasmaType=true
            fi
            rm -rf "$HOME/install.sh"
        fi
        if [[ "${vasmaType}" == "true" ]]; then
            echoContent green "快捷方式创建成功，可执行[vasma]重新打开脚本"
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
    xray_agent_blank
    echoContent skyBlue "功能 $1/${totalProgress} : 查看日志"
    xray_agent_blank
    echoContent red "=============================================================="
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
                xray_agent_write_access_log_config true
            else
                xray_agent_write_access_log_config false
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

xray_agent_access_log_config_json() {
    local access_enabled="${1:-false}"
    if [[ "${access_enabled}" == "true" ]]; then
        jq -nc '{log:{access:"/etc/xray-agent/xray/access.log",error:"/etc/xray-agent/xray/error.log",loglevel:"debug"}}'
    else
        jq -nc '{log:{error:"/etc/xray-agent/xray/error.log",loglevel:"warning"}}'
    fi
}

xray_agent_write_access_log_config() {
    xray_agent_json_write "${configPath}00_log.json" "$(xray_agent_access_log_config_json "$1")"
}

xray_agent_render_dokodemo_port() {
    local port="$1"
    xray_agent_export_xray_network_template_vars
    export XRAY_DOKODEMO_PORT="${port}"
    export XRAY_TARGET_PORT="${Port}"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/extras/dokodemo_port.json.tpl" "${configPath}02_dokodemodoor_inbounds_${port}.json"
}

addCorePort() {
    if [[ "${coreInstallType}" != "1" ]] && [[ "${coreInstallType}" != "3" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 0
    fi
    echoContent yellow "# 只给TLS+VISION添加新端口，永远不会支持Reality(Reality只建议用443)"
    xray_agent_blank
    echoContent yellow "1.添加端口"
    echoContent yellow "2.删除端口"
    echoContent yellow "3.查看已添加端口"
    read -r -p "请选择:" selectNewPortType
    if [[ "${selectNewPortType}" == "1" ]]; then
        read -r -p "请输入端口号:" newPort
        if [[ -n "${newPort}" ]]; then
            while read -r port; do
                if [[ "${port}" == "${Port}" ]]; then
                    continue
                fi
                rm -rf "$(find ${configPath}* | grep "${port}")"
                allowPort "${port}"
                xray_agent_render_dokodemo_port "${port}"
            done < <(echo "${newPort}" | tr ',' '\n')
            reloadCore
        fi
    elif [[ "${selectNewPortType}" == "2" ]]; then
        find "${configPath}" -name "*dokodemodoor*" | awk -F "[c][o][n][f][/]" '{print ""NR""":"$2}'
        read -r -p "请输入要删除的端口编号:" portIndex
        dokoConfig=$(find "${configPath}" -name "*dokodemodoor*" | awk -F "[c][o][n][f][/]" '{print ""NR""":"$2}' | grep "${portIndex}:")
        if [[ -n "${dokoConfig}" ]]; then
            rm "${configPath}/$(echo "${dokoConfig}" | awk -F "[:]" '{print $2}')"
            reloadCore
        fi
    else
        find "${configPath}" -name "*dokodemodoor*" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}'
    fi
}

xray_agent_default_sniffing_json() {
    jq -nc '{enabled:true,destOverride:["http","tls","quic"],metadataOnly:false,routeOnly:false}'
}

manageSniffing() {
    if [[ "${coreInstallType}" == "1" ]]; then
        current_sniffing=$(jq '.inbounds[].sniffing.enabled' "${configPath}${frontingType}.json")
        current_routeOnly=$(jq '.inbounds[].sniffing.routeOnly' "${configPath}${frontingType}.json")
    elif [[ "${coreInstallType}" == "2" ]]; then
        current_sniffing=$(jq '.inbounds[].sniffing.enabled' "${configPath}${RealityfrontingType}.json")
        current_routeOnly=$(jq '.inbounds[].sniffing.routeOnly' "${configPath}${RealityfrontingType}.json")
    else
        current_sniffing=$(jq -s '.[0].inbounds[].sniffing.enabled and .[1].inbounds[].sniffing.enabled' "${configPath}${frontingType}.json" "${configPath}${RealityfrontingType}.json")
        current_routeOnly=$(jq -s '.[0].inbounds[].sniffing.routeOnly and .[1].inbounds[].sniffing.routeOnly' "${configPath}${frontingType}.json" "${configPath}${RealityfrontingType}.json")
    fi
    echoContent yellow "1. $( [[ "${current_sniffing}" == "true" ]] && echo "关闭" || echo "开启" ) 流量嗅探"
    echoContent yellow "2. $( [[ "${current_routeOnly}" == "true" ]] && echo "关闭" || echo "开启" ) 流量嗅探仅供路由"
    read -r -p "请按照上面示例输入:" sniffingtype
    case ${sniffingtype} in
        1)
            find "${configPath}" -name "*_inbounds.json" | while read -r configfile; do
                if [[ "${current_sniffing}" == "true" ]]; then
                    xray_agent_json_update_file "${configfile}" '.inbounds[].sniffing.enabled = false'
                else
                    xray_agent_json_update_file "${configfile}" '.inbounds[].sniffing.enabled = true'
                fi
            done
            ;;
        2)
            find "${configPath}" -name "*_inbounds.json" | while read -r configfile; do
                if [[ "${current_routeOnly}" == "true" ]]; then
                    xray_agent_json_update_file "${configfile}" '.inbounds[].sniffing.routeOnly = false'
                else
                    xray_agent_json_update_file "${configfile}" '.inbounds[].sniffing.routeOnly = true'
                fi
            done
            ;;
    esac
    reloadCore
}

xray_agent_default_sockopt_json() {
    jq -nc '{acceptProxyProtocol:false,tcpFastOpen:true,tcpMptcp:false,tcpNoDelay:false}'
}

xray_agent_sockopt_with_proxy_protocol() {
    local accept_proxy="${1:-false}"
    jq -nc --argjson acceptProxyProtocol "${accept_proxy}" '{acceptProxyProtocol:$acceptProxyProtocol,tcpFastOpen:true,tcpMptcp:false,tcpNoDelay:false}'
}

xray_agent_apply_trusted_x_forwarded_for() {
    local target_path="$1"
    local trusted_source="${2:-$(xray_agent_internal_loopback_host)}"
    [[ -f "${target_path}" ]] || return 0
    xray_agent_json_update_file "${target_path}" '.inbounds[0].streamSettings.sockopt.trustedXForwardedFor = [$trustedSource]' --arg trustedSource "${trusted_source}"
}

xray_agent_apply_trusted_xff_patch() {
    local target_path="$1"
    local trusted_source="${XRAY_AGENT_TRUSTED_X_FORWARDED_FOR:-$(xray_agent_internal_loopback_host)}"
    xray_agent_apply_trusted_x_forwarded_for "${target_path}" "${trusted_source}"
}

manageSockopt() {
    if [[ "${coreInstallType}" == "1" ]]; then
        current_tcpMptcp=$(jq '.inbounds[].streamSettings.sockopt.tcpMptcp' "${configPath}${frontingType}.json")
        current_tcpNoDelay=$(jq '.inbounds[].streamSettings.sockopt.tcpNoDelay' "${configPath}${frontingType}.json")
        current_tcpFastOpen=$(jq '.inbounds[].streamSettings.sockopt.tcpFastOpen' "${configPath}${frontingType}.json")
    elif [[ "${coreInstallType}" == "2" ]]; then
        current_tcpMptcp=$(jq '.inbounds[].streamSettings.sockopt.tcpMptcp' "${configPath}${RealityfrontingType}.json")
        current_tcpNoDelay=$(jq '.inbounds[].streamSettings.sockopt.tcpNoDelay' "${configPath}${RealityfrontingType}.json")
        current_tcpFastOpen=$(jq '.inbounds[].streamSettings.sockopt.tcpFastOpen' "${configPath}${RealityfrontingType}.json")
    else
        current_tcpMptcp=$(jq -s '.[0].inbounds[].streamSettings.sockopt.tcpMptcp and .[1].inbounds[].streamSettings.sockopt.tcpMptcp' "${configPath}${frontingType}.json" "${configPath}${RealityfrontingType}.json")
        current_tcpNoDelay=$(jq -s '.[0].inbounds[].streamSettings.sockopt.tcpNoDelay and .[1].inbounds[].streamSettings.sockopt.tcpNoDelay' "${configPath}${frontingType}.json" "${configPath}${RealityfrontingType}.json")
        current_tcpFastOpen=$(jq -s '.[0].inbounds[].streamSettings.sockopt.tcpFastOpen and .[1].inbounds[].streamSettings.sockopt.tcpFastOpen' "${configPath}${frontingType}.json" "${configPath}${RealityfrontingType}.json")
    fi
    echoContent yellow "1. $( [[ "${current_tcpMptcp}" == "true" ]] && echo "关闭" || echo "开启" ) tcpMptcp"
    echoContent yellow "2. $( [[ "${current_tcpNoDelay}" == "true" ]] && echo "关闭" || echo "开启" ) tcpNoDelay"
    echoContent yellow "3. $( [[ "${current_tcpFastOpen}" == "true" ]] && echo "关闭" || echo "开启" ) tcpFastOpen"
    read -r -p "请按照上面示例输入:" sockopttype
    case ${sockopttype} in
        1)
            find "${configPath}" -name "*_inbounds.json" | while read -r configfile; do
                if [[ "${current_tcpMptcp}" == "true" ]]; then
                    xray_agent_json_update_file "${configfile}" '.inbounds[].streamSettings.sockopt.tcpMptcp = false'
                else
                    xray_agent_json_update_file "${configfile}" '.inbounds[].streamSettings.sockopt.tcpMptcp = true'
                fi
            done
            ;;
        2)
            find "${configPath}" -name "*_inbounds.json" | while read -r configfile; do
                if [[ "${current_tcpNoDelay}" == "true" ]]; then
                    xray_agent_json_update_file "${configfile}" '.inbounds[].streamSettings.sockopt.tcpNoDelay = false'
                else
                    xray_agent_json_update_file "${configfile}" '.inbounds[].streamSettings.sockopt.tcpNoDelay = true'
                fi
            done
            ;;
        3)
            find "${configPath}" -name "*_inbounds.json" | while read -r configfile; do
                if [[ "${current_tcpFastOpen}" == "true" ]]; then
                    xray_agent_json_update_file "${configfile}" '.inbounds[].streamSettings.sockopt.tcpFastOpen = false'
                    sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf
                else
                    xray_agent_json_update_file "${configfile}" '.inbounds[].streamSettings.sockopt.tcpFastOpen = true'
                    sed -i '$a net.ipv4.tcp_fastopen=3' /etc/sysctl.conf
                fi
            done
            sysctl -p
            ;;
    esac
    reloadCore
}

unInstall() {
    read -r -p "是否确认卸载安装内容？[y/n]:" unInstallStatus
    if [[ "${unInstallStatus}" != "y" ]]; then
        echoContent green " ---> 放弃卸载"
        return 0
    fi
    handleNginx stop
    if [[ -n "${coreInstallType}" ]]; then
        handleXray stop
        rm -rf /etc/systemd/system/xray.service
    fi
    crontab -l | grep -v 'auto_update_geodata.sh' | crontab -
    crontab -l | grep -v 'install.sh RenewTLS' | crontab -
    /bin/bash "${XRAY_AGENT_PROJECT_ROOT}/packaging/uninstall.sh"
    rm -rf "${nginxConfigPath}alone.conf"
    rm -rf "${nginxConfigPath}alone.stream"
    rm -rf /usr/bin/vasma
    rm -rf /usr/sbin/vasma
}

updateXRayAgent() {
    local temp_dir archive_path layout_script
    xray_agent_blank
    echoContent skyBlue "进度  $1/${totalProgress} : 更新xray-agent脚本"

    temp_dir="$(mktemp -d)"
    archive_path="${temp_dir}/xray-agent.tar.gz"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${XRAY_AGENT_PROJECT_ARCHIVE_URL}" -o "${archive_path}"
    elif wget --help | grep -q show-progress; then
        wget -c -q --show-progress -O "${archive_path}" --no-check-certificate "${XRAY_AGENT_PROJECT_ARCHIVE_URL}"
    else
        wget -c -q -O "${archive_path}" --no-check-certificate "${XRAY_AGENT_PROJECT_ARCHIVE_URL}"
    fi

    tar -xzf "${archive_path}" -C "${temp_dir}"
    layout_script="$(find "${temp_dir}" -mindepth 3 -maxdepth 4 -path "*/packaging/install-layout.sh" -print -quit)"
    if [[ -z "${layout_script}" ]]; then
        xray_agent_error " ---> 更新包缺少 packaging/install-layout.sh"
    fi

    bash "${layout_script}" /etc/xray-agent
    chmod 700 /etc/xray-agent/install.sh
    rm -rf "${temp_dir}"
}
