#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_download_geodata() {
    local version
    version=$(curl -s https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases | jq -r '.[]|.tag_name' | head -1)
    rm /etc/xray-agent/xray/geo* >/dev/null 2>&1
    wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geosite.dat"
    wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geoip.dat"
}

getPublicIP() {
    local currentIP=
    currentIP=$(curl -s -4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${currentIP}" ]]; then
        currentIP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    fi
    echo "${currentIP}"
}

checkGFWStatue() {
    readInstallType
    xray_agent_blank
    echoContent skyBlue "进度 $1/${totalProgress} : 验证服务启动状态"
    if [[ -n "${coreInstallType}" ]] && [[ -n $(pgrep -f xray/xray) ]]; then
        echoContent green " ---> 服务启动成功"
    else
        xray_agent_error " ---> 服务启动失败，请检查终端是否有日志打印"
    fi
}

xrayVersionManageMenu() {
    xray_agent_blank
    echoContent skyBlue "进度  $1/${totalProgress} : Xray版本管理"
    if [[ ! -d "/etc/xray-agent/xray/" ]]; then
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        menu
        exit 0
    fi
    xray_agent_blank
    echoContent red "=============================================================="
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
            echoContent yellow "1.只可以回退最近的五个版本"
            echoContent yellow "2.不保证回退后一定可以正常使用"
            echoContent yellow "3.如果回退的版本不支持当前的config，则会无法连接，谨慎操作"
            echoContent skyBlue "------------------------Version-------------------------------"
            curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -5 | awk '{print ""NR""":"$0}'
            echoContent skyBlue "--------------------------------------------------------------"
            read -r -p "请输入要回退的版本:" selectXrayVersionType
            version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -5 | awk '{print ""NR""":"$0}' | grep "${selectXrayVersionType}:" | awk -F "[:]" '{print $2}')
            if [[ -n "${version}" ]]; then
                updateXray "${version}"
            else
                echoContent red " ---> 输入有误，请重新输入"
                xrayVersionManageMenu 1
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

installXray() {
    readInstallType
    xray_agent_blank
    echoContent skyBlue "进度  $1/${totalProgress} : 安装Xray"
    if [[ -z "${coreInstallType}" ]]; then
        version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -1)
        echoContent green " ---> Xray-core版本:${version}"
        if wget --help | grep -q show-progress; then
            wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
        else
            wget -c -P /etc/xray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip" >/dev/null 2>&1
        fi
        if [[ ! -f "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip" ]]; then
            echoContent red " ---> 核心下载失败，请重新尝试安装"
            exit 0
        fi
        unzip -o "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip" -d /etc/xray-agent/xray >/dev/null
        if [[ ! -f "/etc/xray-agent/xray/xray" ]]; then
            echoContent red "下载或解压新版本Xray失败，请重试"
            return 1
        fi
        rm -rf "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip"
        xray_agent_download_geodata
        chmod 655 "${ctlPath}"
    else
        read -r -p "是否更新、升级？[y/n]:" reInstallXrayStatus
        if [[ "${reInstallXrayStatus}" == "y" ]]; then
            rm -f "${ctlPath}"
            installXray "$1"
        fi
    fi
}

reloadCore() {
    handleXray stop
    handleXray start
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
        echoContent green " ---> Xray-core版本:${version}"
        if wget --help | grep -q show-progress; then
            wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"
        else
            wget -c -P /etc/xray-agent/xray/ "https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip" >/dev/null 2>&1
        fi
        unzip -o "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip" -d /etc/xray-agent/xray >/dev/null
        if [[ ! -f "/etc/xray-agent/xray/xray" ]]; then
            echoContent red "下载或解压新版本Xray失败，请重试"
            return 1
        fi
        rm -rf "/etc/xray-agent/xray/${xrayCoreCPUVendor}.zip"
        chmod 655 "${ctlPath}"
        handleXray stop
        handleXray start
    else
        echoContent green " ---> 当前Xray-core版本:$(${ctlPath} --version | awk '{print $2}' | head -1)"
        if [[ -n "$1" ]]; then
            read -r -p "回退版本为${version}，是否继续？[y/n]:" rollbackXrayStatus
            if [[ "${rollbackXrayStatus}" == "y" ]]; then
                echoContent green " ---> 当前Xray-core版本:$(${ctlPath} --version | awk '{print $2}' | head -1)"
                handleXray stop
                rm -f "${ctlPath}"
                updateXray "${version}"
            else
                echoContent green " ---> 放弃回退版本"
            fi
        elif [[ "${version}" == "v$(${ctlPath} --version | awk '{print $2}' | head -1)" ]]; then
            read -r -p "当前版本与最新版相同，是否重新安装？[y/n]:" reInstallXrayStatus
            if [[ "${reInstallXrayStatus}" == "y" ]]; then
                handleXray stop
                rm -f "${ctlPath}"
                updateXray
            else
                echoContent green " ---> 放弃重新安装"
            fi
        else
            read -r -p "最新版本为:${version}，是否更新？[y/n]:" installXrayStatus
            if [[ "${installXrayStatus}" == "y" ]]; then
                rm -f "${ctlPath}"
                updateXray
            else
                echoContent green " ---> 放弃更新"
            fi
        fi
    fi
}
