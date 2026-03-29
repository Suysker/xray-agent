if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

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
