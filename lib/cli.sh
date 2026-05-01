#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_print_banner() {
    xray_agent_blank
    echoContent red "=============================================================="
    echoContent green "项目:xray-agent"
    echoContent green "维护者:${XRAY_AGENT_PROJECT_OWNER}"
    echoContent green "当前版本:${XRAY_AGENT_VERSION}"
    echoContent green "Github:${XRAY_AGENT_PROJECT_REPO}"
    xray_agent_print_inline green "描述:Xray profile 构建脚本"
    showInstallStatus
    xray_agent_blank
    echoContent red "=============================================================="
}

xray_agent_print_install_menu_items() {
    if [[ "${coreInstallType}" == "1" || "${coreInstallType}" == "3" ]]; then
        echoContent yellow "1.重新安装TLS套餐(VLESS-TCP/VLESS-WS/VMess-WS/XHTTP/Hysteria2)"
    else
        echoContent yellow "1.安装TLS套餐(VLESS-TCP/VLESS-WS/VMess-WS/XHTTP/Hysteria2)"
    fi
    if [[ "${coreInstallType}" == "2" || "${coreInstallType}" == "3" ]]; then
        echoContent yellow "2.重新安装Reality套餐(VLESS-TCP/XHTTP，可选Hysteria2)"
    else
        echoContent yellow "2.安装Reality套餐(VLESS-TCP/XHTTP，可选Hysteria2)"
    fi
}

xray_agent_print_management_menu_items() {
    echoContent skyBlue "-------------------------工具管理-----------------------------"
    echoContent yellow "3.账号管理"
    echoContent yellow "4.网站/反代管理"
    echoContent yellow "5.证书管理"
    echoContent yellow "6.IPv4/IPv6出站策略"
    echoContent yellow "7.阻止访问黑名单及中国大陆IP"
    echoContent yellow "8.WARP分流及中国大陆域名+IP"
    echoContent yellow "9.添加新端口"
    echoContent yellow "10.流量嗅探管理"
    echoContent yellow "11.sockopt进阶管理"
    echoContent yellow "12.Hysteria2管理"
}

xray_agent_print_version_menu_items() {
    echoContent skyBlue "-------------------------版本管理-----------------------------"
    echoContent yellow "13.订阅管理"
    echoContent yellow "14.core管理"
    echoContent yellow "15.更新脚本"
}

xray_agent_print_script_menu_items() {
    echoContent skyBlue "-------------------------脚本管理-----------------------------"
    echoContent yellow "16.备份与恢复管理"
    echoContent yellow "17.查看日志"
    echoContent yellow "18.卸载脚本"
}

xray_agent_print_external_menu_items() {
    echoContent skyBlue "-------------------------其他功能-----------------------------"
    echoContent yellow "19.Adguardhome"
    echoContent yellow "20.WARP"
    echoContent yellow "21.内核管理及BBR优化"
    echoContent yellow "22.五网测速+IPV6"
    echoContent yellow "23.三网回程路由测试"
    echoContent yellow "24.流媒体解锁检测"
    echoContent yellow "25.VPS基本信息"
    echoContent red "=============================================================="
}

xray_agent_render_menu() {
    xray_agent_print_banner
    xray_agent_print_install_menu_items
    xray_agent_print_management_menu_items
    xray_agent_print_version_menu_items
    xray_agent_print_script_menu_items
    xray_agent_print_external_menu_items
}

xray_agent_dispatch_menu_selection() {
    local selected_item="$1"
    case "${selected_item}" in
        1) xray_agent_run_install_profile tls_vision_xhttp ;;
        2) xray_agent_run_install_profile reality_vision_xhttp ;;
        3) manageAccount 1 ;;
        4) updateNginxBlog 1 ;;
        5) manageCert 1 ;;
        6) ipv6Routing 1 ;;
        7) blacklist 1 ;;
        8) warpRouting 1 ;;
        9) addCorePort 1 ;;
        10) manageSniffing 1 ;;
        11) manageSockopt 1 ;;
        12) xray_agent_hysteria2_manage_menu ;;
        13) xray_agent_subscription_menu ;;
        14) xrayVersionManageMenu 1 ;;
        15) updateXRayAgent 1 ;;
        16) xray_agent_backup_menu ;;
        17) checkLog 1 ;;
        18) unInstall 1 ;;
        19) AdguardManageMenu 1 ;;
        20) xray_agent_external_warp_menu ;;
        21) xray_agent_external_kernel_bbr ;;
        22) xray_agent_external_hyperspeed ;;
        23) xray_agent_external_backtrace ;;
        24) xray_agent_external_unlock_media ;;
        25) xray_agent_external_vps_info ;;
    esac
}

menu() {
    local selected_item
    cd "$HOME" || exit
    xray_agent_render_menu
    mkdirTools
    aliasInstall
    read -r -p "请选择:" selected_item
    xray_agent_dispatch_menu_selection "${selected_item}"
}

xray_agent_route_args() {
    case "${1:-}" in
        RenewTLS)
            renewalTLS "all"
            exit 0
            ;;
    esac
}

xray_agent_main() {
    initVar
    checkSystem
    checkCPUVendor
    xray_agent_bootstrap_state
    xray_agent_route_args "$@"
    menu
}
