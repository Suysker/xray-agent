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

xray_agent_extra_port_files() {
    find "${configPath}" -maxdepth 1 -type f -name "02_dokodemodoor_inbounds_*.json" 2>/dev/null | sort
}

xray_agent_extra_port_summary() {
    local port_file port
    echoContent skyBlue "-------------------------额外端口-----------------------------"
    if ! xray_agent_extra_port_files | grep -q .; then
        echoContent yellow "暂无额外端口"
        return 0
    fi
    while IFS= read -r port_file; do
        port="${port_file##*_}"
        port="${port%.json}"
        echoContent yellow "端口: ${port} -> 后端 ${Port:-未检测}"
    done < <(xray_agent_extra_port_files)
}

addCorePort() {
    if [[ "${coreInstallType}" != "1" ]] && [[ "${coreInstallType}" != "3" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 0
    fi
    xray_agent_tool_status_header "添加新端口"
    xray_agent_extra_port_summary
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
                if ! xray_agent_validate_port "${port}"; then
                    echoContent red " ---> 跳过非法端口: ${port}"
                    continue
                fi
                if [[ "${port}" == "${Port}" ]]; then
                    echoContent yellow " ---> 跳过主端口: ${port}"
                    continue
                fi
                checkPort "${port}"
                echoContent yellow "将新增公开端口 ${port}，转发到 TLS Vision 后端 ${Port}。"
                xray_agent_confirm "确认继续？[y/N]:" "n" || continue
                rm -f "${configPath}02_dokodemodoor_inbounds_${port}.json"
                allowPort "${port}"
                xray_agent_render_dokodemo_port "${port}"
            done < <(echo "${newPort}" | tr ',' '\n')
            reloadCore
        fi
    elif [[ "${selectNewPortType}" == "2" ]]; then
        mapfile -t dokoFiles < <(xray_agent_extra_port_files)
        if [[ "${#dokoFiles[@]}" -eq 0 ]]; then
            echoContent yellow " ---> 暂无可删除额外端口"
            return 0
        fi
        for i in "${!dokoFiles[@]}"; do
            echo "$((i + 1)): ${dokoFiles[$i]##*/}"
        done
        read -r -p "请输入要删除的端口编号:" portIndex
        if [[ "${portIndex}" =~ ^[0-9]+$ && "${portIndex}" -ge 1 && "${portIndex}" -le "${#dokoFiles[@]}" ]]; then
            echoContent yellow "将删除 ${dokoFiles[$((portIndex - 1))]##*/}"
            xray_agent_confirm "确认继续？[y/N]:" "n" || return 0
            rm -f "${dokoFiles[$((portIndex - 1))]}"
            reloadCore
        else
            echoContent red " ---> 选择错误"
        fi
    else
        xray_agent_extra_port_summary
    fi
}

xray_agent_default_sniffing_json() {
    jq -nc '{enabled:true,destOverride:["http","tls","quic"],metadataOnly:false,routeOnly:false}'
}

xray_agent_inbound_config_files() {
    find "${configPath}" -maxdepth 1 -type f -name "*_inbounds.json" 2>/dev/null | sort
}

xray_agent_prompt_inbound_config_file() {
    local prompt_title="$1"
    local selected_index
    mapfile -t inboundConfigFiles < <(xray_agent_inbound_config_files)
    if [[ "${#inboundConfigFiles[@]}" -eq 0 ]]; then
        echoContent red " ---> 未找到 inbound 配置文件"
        selectedInboundConfigFile=
        return 1
    fi
    echoContent yellow "${prompt_title}"
    for i in "${!inboundConfigFiles[@]}"; do
        echo "$((i + 1)): ${inboundConfigFiles[$i]##*/}"
    done
    read -r -p "请选择编号:" selected_index
    if ! [[ "${selected_index}" =~ ^[0-9]+$ ]] || [[ "${selected_index}" -lt 1 || "${selected_index}" -gt "${#inboundConfigFiles[@]}" ]]; then
        echoContent red " ---> 选择错误"
        selectedInboundConfigFile=
        return 1
    fi
    selectedInboundConfigFile="${inboundConfigFiles[$((selected_index - 1))]}"
}

xray_agent_sniffing_status_matrix() {
    local configfile tag enabled route_only
    echoContent skyBlue "-------------------------嗅探状态-----------------------------"
    if ! xray_agent_inbound_config_files | grep -q .; then
        echoContent yellow "未找到 inbound 配置文件"
        return 0
    fi
    while IFS= read -r configfile; do
        tag="$(jq -r '.inbounds[0].tag // empty' "${configfile}" 2>/dev/null | tr -d '\r')"
        enabled="$(jq -r '.inbounds[0].sniffing.enabled // false' "${configfile}" 2>/dev/null | tr -d '\r')"
        route_only="$(jq -r '.inbounds[0].sniffing.routeOnly // false' "${configfile}" 2>/dev/null | tr -d '\r')"
        echoContent yellow "${configfile##*/}: tag=${tag:-无} enabled=${enabled} routeOnly=${route_only}"
    done < <(xray_agent_inbound_config_files)
}

manageSniffing() {
    if [[ -z "${coreInstallType}" ]]; then
        xray_agent_error " ---> 未安装，请使用脚本安装"
    fi
    xray_agent_tool_status_header "流量嗅探管理"
    xray_agent_sniffing_status_matrix
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
    echoContent yellow "1.全部$( [[ "${current_sniffing}" == "true" ]] && echo "关闭" || echo "开启" )流量嗅探"
    echoContent yellow "2.全部$( [[ "${current_routeOnly}" == "true" ]] && echo "关闭" || echo "开启" )流量嗅探仅供路由"
    echoContent yellow "3.按协议切换流量嗅探"
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
        3)
            xray_agent_prompt_inbound_config_file "请选择要切换嗅探的协议" || return 0
            local selected_sniffing
            selected_sniffing="$(jq -r '.inbounds[0].sniffing.enabled // false' "${selectedInboundConfigFile}" | tr -d '\r')"
            if [[ "${selected_sniffing}" == "true" ]]; then
                xray_agent_json_update_file "${selectedInboundConfigFile}" '.inbounds[].sniffing.enabled = false'
            else
                xray_agent_json_update_file "${selectedInboundConfigFile}" '.inbounds[].sniffing.enabled = true'
            fi
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

xray_agent_sockopt_status_matrix() {
    local configfile tag mptcp nodelay fastopen
    echoContent skyBlue "-------------------------sockopt状态-----------------------------"
    if ! xray_agent_inbound_config_files | grep -q .; then
        echoContent yellow "未找到 inbound 配置文件"
        return 0
    fi
    while IFS= read -r configfile; do
        tag="$(jq -r '.inbounds[0].tag // empty' "${configfile}" 2>/dev/null | tr -d '\r')"
        mptcp="$(jq -r '.inbounds[0].streamSettings.sockopt.tcpMptcp // false' "${configfile}" 2>/dev/null | tr -d '\r')"
        nodelay="$(jq -r '.inbounds[0].streamSettings.sockopt.tcpNoDelay // false' "${configfile}" 2>/dev/null | tr -d '\r')"
        fastopen="$(jq -r '.inbounds[0].streamSettings.sockopt.tcpFastOpen // false' "${configfile}" 2>/dev/null | tr -d '\r')"
        echoContent yellow "${configfile##*/}: tag=${tag:-无} tcpMptcp=${mptcp} tcpNoDelay=${nodelay} tcpFastOpen=${fastopen}"
    done < <(xray_agent_inbound_config_files)
}

manageSockopt() {
    if [[ -z "${coreInstallType}" ]]; then
        xray_agent_error " ---> 未安装，请使用脚本安装"
    fi
    xray_agent_tool_status_header "sockopt进阶管理"
    xray_agent_sockopt_status_matrix
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
    echoContent yellow "4.按协议切换 tcpNoDelay"
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
        4)
            xray_agent_prompt_inbound_config_file "请选择要切换 tcpNoDelay 的协议" || return 0
            local selected_tcp_no_delay
            selected_tcp_no_delay="$(jq -r '.inbounds[0].streamSettings.sockopt.tcpNoDelay // false' "${selectedInboundConfigFile}" | tr -d '\r')"
            if [[ "${selected_tcp_no_delay}" == "true" ]]; then
                xray_agent_json_update_file "${selectedInboundConfigFile}" '.inbounds[].streamSettings.sockopt.tcpNoDelay = false'
            else
                xray_agent_json_update_file "${selectedInboundConfigFile}" '.inbounds[].streamSettings.sockopt.tcpNoDelay = true'
            fi
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

    if declare -F xray_agent_download_url_to_file >/dev/null 2>&1; then
        if ! xray_agent_download_url_to_file "${XRAY_AGENT_PROJECT_ARCHIVE_URL}" "${archive_path}" "xray-agent 更新包"; then
            rm -rf "${temp_dir}"
            return 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        echoContent yellow " ---> 下载 xray-agent 更新包"
        if ! curl -fL --progress-bar "${XRAY_AGENT_PROJECT_ARCHIVE_URL}" -o "${archive_path}"; then
            echoContent red " ---> xray-agent 更新包下载失败"
            rm -rf "${temp_dir}"
            return 1
        fi
    elif wget --help | grep -q show-progress; then
        echoContent yellow " ---> 下载 xray-agent 更新包"
        if ! wget -q --show-progress -O "${archive_path}" --no-check-certificate "${XRAY_AGENT_PROJECT_ARCHIVE_URL}"; then
            echoContent red " ---> xray-agent 更新包下载失败"
            rm -rf "${temp_dir}"
            return 1
        fi
    else
        echoContent yellow " ---> 下载 xray-agent 更新包"
        if ! wget -O "${archive_path}" --no-check-certificate "${XRAY_AGENT_PROJECT_ARCHIVE_URL}"; then
            echoContent red " ---> xray-agent 更新包下载失败"
            rm -rf "${temp_dir}"
            return 1
        fi
    fi

    echoContent yellow " ---> 解压 xray-agent 更新包"
    if ! tar -m -xzf "${archive_path}" -C "${temp_dir}"; then
        echoContent red " ---> xray-agent 更新包解压失败"
        rm -rf "${temp_dir}"
        return 1
    fi
    layout_script="$(find "${temp_dir}" -mindepth 3 -maxdepth 4 -path "*/packaging/install-layout.sh" -print -quit)"
    if [[ -z "${layout_script}" ]]; then
        echoContent red " ---> 更新包缺少 packaging/install-layout.sh"
        rm -rf "${temp_dir}"
        return 1
    fi

    echoContent yellow " ---> 安装 xray-agent 脚本"
    if ! bash "${layout_script}" /etc/xray-agent; then
        echoContent red " ---> xray-agent 脚本安装失败"
        rm -rf "${temp_dir}"
        return 1
    fi
    chmod 700 /etc/xray-agent/install.sh
    rm -rf "${temp_dir}"
    echoContent green " ---> xray-agent 脚本更新完成"
    echoContent yellow " ---> 请重新执行 vasma 以加载新版本"
}
