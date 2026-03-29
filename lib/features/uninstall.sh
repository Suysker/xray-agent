if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

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
