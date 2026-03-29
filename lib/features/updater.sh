if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

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
