#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_adguard_restore_dns() {
    if [[ -d /etc/resolvconf/resolv.conf.d ]]; then
        sudo sed -i '/^nameserver 127.0.0.1/d' /etc/resolvconf/resolv.conf.d/head
        sudo sed -i '/^nameserver ::1/d' /etc/resolvconf/resolv.conf.d/head
        sudo resolvconf -u
    else
        sudo chattr -i /etc/resolv.conf 2>/dev/null || true
        if [[ -f /etc/resolv.conf.bak ]]; then
            sudo mv /etc/resolv.conf.bak /etc/resolv.conf
        else
            printf 'nameserver %s\n' "$(xray_agent_fallback_public_dns)" | sudo tee /etc/resolv.conf >/dev/null
        fi
    fi
}

xray_agent_adguard_use_local_dns() {
    local nameserver
    nameserver="$(xray_agent_adguard_nameserver)"
    if [[ -d /etc/resolvconf/resolv.conf.d ]]; then
        sudo sed -i '/^nameserver 127.0.0.1/d' /etc/resolvconf/resolv.conf.d/head
        sudo sed -i '/^nameserver ::1/d' /etc/resolvconf/resolv.conf.d/head
        if ! grep -q "^nameserver ${nameserver}$" /etc/resolvconf/resolv.conf.d/head; then
            sudo sed -i "1inameserver ${nameserver}" /etc/resolvconf/resolv.conf.d/head
        fi
        sudo resolvconf -u
    else
        if [[ -L /etc/resolv.conf ]]; then
            sudo rm -f /etc/resolv.conf
        fi
        if [[ ! -f /etc/resolv.conf.bak ]]; then
            sudo cp /etc/resolv.conf /etc/resolv.conf.bak
        fi
        printf 'nameserver %s\n' "${nameserver}" | sudo tee /etc/resolv.conf >/dev/null
        sudo chattr +i /etc/resolv.conf 2>/dev/null || true
    fi
}

xray_agent_adguard_arch() {
    case "${xrayCoreCPUVendor}" in
        Xray-linux-arm64-v8a) printf 'AdGuardHome_linux_arm64\n' ;;
        *) printf 'AdGuardHome_linux_amd64\n' ;;
    esac
}

xray_agent_adguard_prepare_systemd_resolved() {
    if [[ -f /etc/systemd/resolved.conf ]] && ! grep -q "DNSStubListener=no" /etc/systemd/resolved.conf; then
        sudo sed -i '/\[Resolve\]/a DNSStubListener=no' /etc/systemd/resolved.conf
        sudo systemctl restart systemd-resolved
    fi
}

xray_agent_adguard_install_or_repair() {
    curl -sSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh
}

xray_agent_adguard_print_status() {
    echoContent yellow "状态: $(xray_agent_adguard_status_label)"
    if xray_agent_adguard_installed; then
        echoContent yellow "安装目录: $(xray_agent_adguard_home_dir)"
        if xray_agent_adguard_configured; then
            echoContent yellow "配置文件: $(xray_agent_adguard_config_path)"
        else
            echoContent yellow "配置文件: 未检测到，请完成 Web 初始化后再设为系统 DNS"
        fi
    fi
}

xray_agent_adguard_print_menu() {
    xray_agent_blank
    echoContent skyBlue "AdGuardHome管理"
    xray_agent_adguard_print_status
    xray_agent_blank
    echoContent red "=============================================================="
    if xray_agent_adguard_installed; then
        echoContent yellow "1.重新安装/修复AdGuardHome"
        echoContent yellow "2.升级AdGuardHome"
        echoContent yellow "3.卸载AdGuardHome"
        if xray_agent_adguard_running; then
            echoContent yellow "4.关闭AdGuardHome"
            echoContent yellow "6.重启AdGuardHome"
        else
            echoContent yellow "5.打开AdGuardHome"
            echoContent yellow "6.重启AdGuardHome"
        fi
    else
        echoContent yellow "1.安装AdGuardHome"
    fi
    echoContent yellow "0.返回"
    echoContent red "=============================================================="
}

xray_agent_adguard_apply_runtime_status() {
    sleep 0.8
    xray_agent_adguard_installed || return 0
    if xray_agent_adguard_running; then
        echoContent green " ---> AdGuardHome运行中"
        if xray_agent_adguard_configured; then
            xray_agent_adguard_use_local_dns
            echoContent green " ---> AdGuardHome已成功设置为DNS服务器"
        else
            echoContent red " ---> 未检测到AdGuardHome配置文件，请完成初始化配置后再设为系统DNS"
        fi
    else
        echoContent red " ---> AdGuardHome未运行"
        xray_agent_adguard_restore_dns
        echoContent green " ---> 已恢复原始DNS配置"
    fi
}

AdguardManageMenu() {
    local selectADGType adgCoreCPUVendor adguard_binary adguard_dir
    adgCoreCPUVendor="$(xray_agent_adguard_arch)"
    adguard_binary="$(xray_agent_adguard_binary_path)"
    adguard_dir="$(xray_agent_adguard_home_dir)"

    xray_agent_adguard_print_menu
    read -r -p "请选择:" selectADGType
    [[ "${selectADGType}" != "0" ]] || return 0

    if ! xray_agent_adguard_installed && [[ "${selectADGType}" != "1" ]]; then
        echoContent red " ---> 没有检测到安装目录，请先安装AdGuardHome"
        return 0
    fi

    case "${selectADGType}" in
        1)
            xray_agent_adguard_install_or_repair
            ;;
        2)
            wget -O '/tmp/AdGuardHome.tar.gz' "https://static.adguard.com/adguardhome/release/${adgCoreCPUVendor}.tar.gz"
            tar -C /tmp/ -f /tmp/AdGuardHome.tar.gz -x -v -z
            systemctl stop AdGuardHome
            cp /tmp/AdGuardHome/AdGuardHome "${adguard_binary}"
            systemctl start AdGuardHome
            systemctl enable AdGuardHome
            ;;
        3)
            "${adguard_binary}" -s uninstall
            rm -rf "${adguard_dir}"
            xray_agent_adguard_restore_dns
            ;;
        4)
            systemctl stop AdGuardHome
            systemctl disable AdGuardHome
            xray_agent_adguard_restore_dns
            ;;
        5)
            xray_agent_adguard_prepare_systemd_resolved
            systemctl start AdGuardHome
            systemctl enable AdGuardHome
            ;;
        6)
            xray_agent_adguard_prepare_systemd_resolved
            systemctl restart AdGuardHome
            systemctl enable AdGuardHome
            ;;
        *)
            echoContent red " ---> 选择错误"
            return 0
            ;;
    esac
    xray_agent_adguard_apply_runtime_status
}
