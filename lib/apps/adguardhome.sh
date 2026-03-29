if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

AdguardManageMenu() {
    echoContent skyBlue "\nAdguardhome管理"
    echoContent red "\n=============================================================="
    echoContent yellow "1.安装Adguardhome"
    echoContent yellow "2.升级Adguardhome"
    echoContent yellow "3.卸载Adguardhome"
    echoContent yellow "4.关闭Adguardhome"
    echoContent yellow "5.打开Adguardhome"
    echoContent yellow "6.重启Adguardhome"
    echoContent red "=============================================================="
    if [[ "${xrayCoreCPUVendor}" == "Xray-linux-64" ]]; then
        adgCoreCPUVendor="AdGuardHome_linux_amd64"
    elif [[ "${xrayCoreCPUVendor}" == "Xray-linux-arm64-v8a" ]]; then
        adgCoreCPUVendor="AdGuardHome_linux_arm64"
    fi
    read -r -p "请选择:" selectADGType
    if [[ "${selectADGType}" == "1" ]]; then
        if [[ -f "/opt/AdGuardHome/AdGuardHome" ]]; then
            xray_agent_error " ---> 检测到安装目录，请执行脚本卸载操作"
        fi
        curl -sSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh
    fi
    if [[ ! -f "/opt/AdGuardHome/AdGuardHome" ]]; then
        xray_agent_error " ---> 没有检测到安装目录，请先安装Adguardhome"
    else
        if ! grep -q "DNSStubListener=no" /etc/systemd/resolved.conf; then
            sudo sed -i '/\[Resolve\]/a DNSStubListener=no' /etc/systemd/resolved.conf
            sudo systemctl restart systemd-resolved
        fi
        systemctl start AdGuardHome
        systemctl enable AdGuardHome
    fi
    case "${selectADGType}" in
        2)
            wget -O '/tmp/AdGuardHome_linux_amd64.tar.gz' "https://static.adguard.com/adguardhome/release/${adgCoreCPUVendor}.tar.gz"
            tar -C /tmp/ -f /tmp/AdGuardHome_linux_amd64.tar.gz -x -v -z
            systemctl stop AdGuardHome
            cp /tmp/AdGuardHome/AdGuardHome /opt/AdGuardHome/AdGuardHome
            systemctl start AdGuardHome
            systemctl enable AdGuardHome
            ;;
        3)
            /opt/AdGuardHome/AdGuardHome -s uninstall
            rm -rf /opt/AdGuardHome
            ;;
        4)
            systemctl stop AdGuardHome
            systemctl disable AdGuardHome
            ;;
        5)
            systemctl start AdGuardHome
            systemctl enable AdGuardHome
            ;;
        6)
            systemctl restart AdGuardHome
            systemctl enable AdGuardHome
            ;;
    esac
}
