#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_adguard_restore_dns() {
    if [[ -d /etc/resolvconf/resolv.conf.d ]]; then
        sudo sed -i '/^nameserver 127.0.0.1/d' /etc/resolvconf/resolv.conf.d/head
        sudo resolvconf -u
    else
        sudo chattr -i /etc/resolv.conf 2>/dev/null || true
        if [[ -f /etc/resolv.conf.bak ]]; then
            sudo mv /etc/resolv.conf.bak /etc/resolv.conf
        else
            printf '%s\n' "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null
        fi
    fi
}

xray_agent_adguard_use_local_dns() {
    if [[ -d /etc/resolvconf/resolv.conf.d ]]; then
        if ! grep -q "^nameserver 127.0.0.1" /etc/resolvconf/resolv.conf.d/head; then
            sudo sed -i '1inameserver 127.0.0.1' /etc/resolvconf/resolv.conf.d/head
        fi
        sudo resolvconf -u
    else
        if [[ -L /etc/resolv.conf ]]; then
            sudo rm -f /etc/resolv.conf
        fi
        if [[ ! -f /etc/resolv.conf.bak ]]; then
            sudo cp /etc/resolv.conf /etc/resolv.conf.bak
        fi
        printf '%s\n' "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf >/dev/null
        sudo chattr +i /etc/resolv.conf 2>/dev/null || true
    fi
}

AdguardManageMenu() {
    xray_agent_blank
    echoContent skyBlue "Adguardhome管理"
    xray_agent_blank
    echoContent red "=============================================================="
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
            echoContent red " ---> 检测到安装目录，请执行脚本卸载操作"
            menu
            exit 0
        fi
        curl -sSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh
    fi
    if [[ ! -f "/opt/AdGuardHome/AdGuardHome" ]]; then
        echoContent red " ---> 没有检测到安装目录，请先安装Adguardhome"
        menu
        exit 0
    else
        if [[ -f /etc/systemd/resolved.conf ]] && ! grep -q "DNSStubListener=no" /etc/systemd/resolved.conf; then
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
            xray_agent_adguard_restore_dns
            ;;
        4)
            systemctl stop AdGuardHome
            systemctl disable AdGuardHome
            xray_agent_adguard_restore_dns
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
    sleep 0.8
    if [[ -f "/opt/AdGuardHome/AdGuardHome" ]]; then
        if systemctl is-active --quiet AdGuardHome; then
            echoContent green " ---> AdGuardhome运行中"
            xray_agent_adguard_use_local_dns
            echoContent green " ---> AdGuardhome已成功设置为DNS服务器"
            if [[ ! -f "/opt/AdGuardHome/AdGuardHome.yaml" ]]; then
                echoContent red " ---> 未检测到AdGuardhome配置文件，请尽快完成初始化配置，否则DNS将无法解析"
            fi
        else
            echoContent red " ---> AdGuardhome未运行"
            xray_agent_adguard_restore_dns
            echoContent green " ---> 已恢复原始DNS配置"
        fi
    fi
}
