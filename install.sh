#!/usr/bin/env bash

export LANG=en_US.UTF-8

SCRIPT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/env.sh"
source "${SCRIPT_DIR}/lib/profiles.sh"

for module_file in \
    "${SCRIPT_DIR}/lib/system.sh" \
    "${SCRIPT_DIR}/lib/firewall.sh" \
    "${SCRIPT_DIR}/lib/tls.sh" \
    "${SCRIPT_DIR}/lib/nginx.sh" \
    "${SCRIPT_DIR}/lib/xray_core.sh" \
    "${SCRIPT_DIR}/lib/users.sh" \
    "${SCRIPT_DIR}/lib/routing.sh" \
    "${SCRIPT_DIR}/lib/sniffing.sh" \
    "${SCRIPT_DIR}/lib/sockopt.sh"; do
    source "${module_file}"
done

for feature_file in "${SCRIPT_DIR}/lib/features/"*.sh; do
    source "${feature_file}"
done

xrayAgentExperimentalMenu() {
    echoContent skyBlue "\n实验特性"
    echoContent red "\n=============================================================="
    echoContent yellow "1.Finalmask: ${XRAY_AGENT_ENABLE_FINALMASK:-false}"
    echoContent yellow "2.TLS ECH: ${XRAY_AGENT_ENABLE_ECH:-false}"
    echoContent yellow "3.VLESS Encryption: ${XRAY_AGENT_ENABLE_VLESS_ENCRYPTION:-false}"
    echoContent yellow "4.Browser Headers: ${XRAY_AGENT_BROWSER_HEADERS:-chrome}"
    echoContent yellow "5.trustedXForwardedFor: ${XRAY_AGENT_TRUSTED_X_FORWARDED_FOR:-127.0.0.1}"
    echoContent red "=============================================================="
    read -r -p "请选择要切换的项目[回车退出]:" selectExperimentalType
    case "${selectExperimentalType}" in
        1)
            [[ "${XRAY_AGENT_ENABLE_FINALMASK}" == "true" ]] && XRAY_AGENT_ENABLE_FINALMASK=false || XRAY_AGENT_ENABLE_FINALMASK=true
            ;;
        2)
            [[ "${XRAY_AGENT_ENABLE_ECH}" == "true" ]] && XRAY_AGENT_ENABLE_ECH=false || XRAY_AGENT_ENABLE_ECH=true
            ;;
        3)
            [[ "${XRAY_AGENT_ENABLE_VLESS_ENCRYPTION}" == "true" ]] && XRAY_AGENT_ENABLE_VLESS_ENCRYPTION=false || XRAY_AGENT_ENABLE_VLESS_ENCRYPTION=true
            ;;
        4)
            read -r -p "请输入 browser headers[chrome/firefox/edge]:" XRAY_AGENT_BROWSER_HEADERS
            ;;
        5)
            read -r -p "请输入 trustedXForwardedFor 来源IP/网段:" XRAY_AGENT_TRUSTED_X_FORWARDED_FOR
            ;;
        *)
            return 0
            ;;
    esac
    xrayAgentPersistFeatureFlags
}

xrayAgentLocalModeMenu() {
    echoContent skyBlue "\n本地模式"
    echoContent red "\n=============================================================="
    echoContent yellow "1.生成 local_tun 配置"
    echoContent yellow "2.Browser Dialer 说明"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectLocalModeType
    case "${selectLocalModeType}" in
        1)
            installTools 1
            installXray 2
            installXrayService 3
            xray_agent_render_local_tun_profile
            reloadCore
            echoContent green " ---> 已生成 local_tun 配置: ${configPath}20_TUN_inbounds.json"
            echoContent yellow " ---> TUN 模式不会自动改系统路由表，请手动配置并注意避免回环"
            ;;
        2)
            xray_agent_browser_dialer_message
            ;;
    esac
}

xrayAgentProfileBuilderMenu() {
    echoContent skyBlue "\n模块化 Profile 菜单"
    echoContent red "\n=============================================================="
    echoContent yellow "1.server_tls_vision + ws/vmess/xhttp"
    echoContent yellow "2.server_reality_vision + xhttp"
    echoContent yellow "3.server_tls_xhttp"
    echoContent yellow "4.server_reality_xhttp"
    echoContent yellow "5.server_hysteria2"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectProfileBuilderType
    case "${selectProfileBuilderType}" in
        1)
            xrayCoreInstall
            ;;
        2)
            xrayCoreInstall_Reality
            ;;
        3)
            xrayCoreInstall
            ;;
        4)
            xrayCoreInstall_Reality
            ;;
        5)
            xray_agent_install_hysteria2_native
            ;;
    esac
}

runExternalTool() {
    case "$1" in
        warp)
            wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh
            ;;
        kernel)
            wget -N https://raw.githubusercontent.com/jinwyp/one_click_script/master/install_kernel.sh && bash install_kernel.sh
            ;;
        hysteria)
            bash <(curl -fsSL https://get.hy2.sh)
            ;;
        bench)
            bash <(curl -Lso- https://bench.im/hyperspeed)
            ;;
        backtrace)
            bash <(curl https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh -sSf)
            ;;
        unlock)
            bash <(curl -L -s check.unlock.media)
            ;;
        vps)
            wget -q https://github.com/Aniverse/A/raw/i/a && bash a
            ;;
    esac
}

menu() {
    cd "$HOME" || exit
    echoContent red "\n=============================================================="
    echoContent green "项目:xray-agent"
    echoContent green "维护者:${XRAY_AGENT_PROJECT_OWNER}"
    echoContent green "当前版本:${XRAY_AGENT_VERSION}"
    echoContent green "Github:${XRAY_AGENT_PROJECT_REPO}"
    echoContent green "描述:Xray profile 构建脚本\c"
    showInstallStatus
    echoContent red "\n=============================================================="
    if [[ "${coreInstallType}" == "1" || "${coreInstallType}" == "3" ]]; then
        echoContent yellow "1.重新安装TLS套餐(VLESS-TCP/VLESS-WS/VMess-WS/XHTTP)"
    else
        echoContent yellow "1.安装TLS套餐(VLESS-TCP/VLESS-WS/VMess-WS/XHTTP)"
    fi
    if [[ "${coreInstallType}" == "2" || "${coreInstallType}" == "3" ]]; then
        echoContent yellow "2.重新安装Reality套餐(VLESS-TCP/XHTTP)"
    else
        echoContent yellow "2.安装Reality套餐(VLESS-TCP/XHTTP)"
    fi
    echoContent skyBlue "-------------------------工具管理-----------------------------"
    echoContent yellow "3.账号管理"
    echoContent yellow "4.更换伪装站"
    echoContent yellow "5.证书管理"
    echoContent yellow "6.IPv6分流"
    echoContent yellow "7.阻止访问黑名单及中国大陆IP"
    echoContent yellow "8.WARP分流及中国大陆域名+IP"
    echoContent yellow "9.添加新端口"
    echoContent yellow "10.流量嗅探管理"
    echoContent yellow "11.sockopt进阶管理"
    echoContent skyBlue "-------------------------版本管理-----------------------------"
    echoContent yellow "12.core管理"
    echoContent yellow "13.更新脚本"
    echoContent skyBlue "-------------------------脚本管理-----------------------------"
    echoContent yellow "14.查看日志"
    echoContent yellow "15.卸载脚本"
    echoContent skyBlue "-------------------------其他功能-----------------------------"
    echoContent yellow "16.Adguardhome"
    echoContent yellow "17.WARP"
    echoContent yellow "18.内核管理及BBR优化"
    echoContent yellow "19.Hysteria一键"
    echoContent yellow "20.五网测速+IPV6"
    echoContent yellow "21.三网回程路由测试"
    echoContent yellow "22.流媒体解锁检测"
    echoContent yellow "23.VPS基本信息"
    echoContent yellow "24.模块化 Profile 菜单"
    echoContent yellow "25.本地模式菜单"
    echoContent yellow "26.实验特性开关"
    echoContent red "=============================================================="
    mkdirTools
    aliasInstall
    read -r -p "请选择:" selectInstallType
    case ${selectInstallType} in
        1)
            xrayCoreInstall
            ;;
        2)
            xrayCoreInstall_Reality
            ;;
        3)
            manageAccount 1
            ;;
        4)
            updateNginxBlog 1
            ;;
        5)
            manageCert 1
            ;;
        6)
            ipv6Routing 1
            ;;
        7)
            blacklist 1
            ;;
        8)
            warpRouting 1
            ;;
        9)
            addCorePort 1
            ;;
        10)
            manageSniffing 1
            ;;
        11)
            manageSockopt 1
            ;;
        12)
            xrayVersionManageMenu 1
            ;;
        13)
            updateXRayAgent 1
            ;;
        14)
            checkLog 1
            ;;
        15)
            unInstall 1
            ;;
        16)
            AdguardManageMenu 1
            ;;
        17)
            runExternalTool warp
            ;;
        18)
            runExternalTool kernel
            ;;
        19)
            runExternalTool hysteria
            ;;
        20)
            runExternalTool bench
            ;;
        21)
            runExternalTool backtrace
            ;;
        22)
            runExternalTool unlock
            ;;
        23)
            runExternalTool vps
            ;;
        24)
            xrayAgentProfileBuilderMenu
            ;;
        25)
            xrayAgentLocalModeMenu
            ;;
        26)
            xrayAgentExperimentalMenu
            ;;
    esac
}

main() {
    initVar
    checkSystem
    checkCPUVendor
    xray_agent_bootstrap_state

    if [[ "$1" == "RenewTLS" ]]; then
        renewalTLS "all"
        exit 0
    fi

    menu
}

main "$@"
