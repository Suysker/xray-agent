#!/usr/bin/env bash

export LANG=en_US.UTF-8

SCRIPT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export XRAY_AGENT_PROJECT_ROOT="${SCRIPT_DIR}"

xray_agent_prepend_path_once() {
    local candidate="$1"
    [[ -d "${candidate}" ]] || return 0
    case ":${PATH}:" in
        *":${candidate}:"*) ;;
        *) export PATH="${candidate}:${PATH}" ;;
    esac
}

xray_agent_to_unix_path() {
    local raw_path="$1"
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "${raw_path}"
        return 0
    fi
    raw_path="${raw_path//\\//}"
    if [[ "${raw_path}" =~ ^([A-Za-z]):(/.*)?$ ]]; then
        printf '/mnt/%s%s\n' "$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')" "${BASH_REMATCH[2]}"
        return 0
    fi
    printf '%s\n' "${raw_path}"
}

xray_agent_ensure_jq_on_path() {
    command -v jq >/dev/null 2>&1 && return 0

    local local_app_data unix_local_app_data winget_links_dir candidate_dir
    local_app_data="${LOCALAPPDATA:-}"
    if [[ -z "${local_app_data}" && -n "${USERPROFILE:-}" ]]; then
        local_app_data="${USERPROFILE}\\AppData\\Local"
    fi

    if [[ -n "${local_app_data}" ]]; then
        unix_local_app_data="$(xray_agent_to_unix_path "${local_app_data}")"
        winget_links_dir="${unix_local_app_data}/Microsoft/WinGet/Links"
        xray_agent_prepend_path_once "${winget_links_dir}"

        for candidate_dir in "${unix_local_app_data}"/Microsoft/WinGet/Packages/jqlang.jq_*/; do
            xray_agent_prepend_path_once "${candidate_dir%/}"
        done
    fi

    for winget_links_dir in /mnt/c/Users/*/AppData/Local/Microsoft/WinGet/Links /c/Users/*/AppData/Local/Microsoft/WinGet/Links; do
        xray_agent_prepend_path_once "${winget_links_dir}"
    done

    for candidate_dir in /mnt/c/Users/*/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_*/ /c/Users/*/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_*/; do
        xray_agent_prepend_path_once "${candidate_dir%/}"
    done
}

xray_agent_ensure_jq_on_path

for module_group in \
    "${SCRIPT_DIR}/lib/common/"*.sh \
    "${SCRIPT_DIR}/lib/runtime/"*.sh \
    "${SCRIPT_DIR}/lib/system/"*.sh \
    "${SCRIPT_DIR}/lib/tls/"*.sh \
    "${SCRIPT_DIR}/lib/core/"*.sh \
    "${SCRIPT_DIR}/lib/nginx/"*.sh \
    "${SCRIPT_DIR}/lib/features/"*.sh \
    "${SCRIPT_DIR}/lib/apps/"*.sh \
    "${SCRIPT_DIR}/lib/external/"*.sh \
    "${SCRIPT_DIR}/lib/experimental/"*.sh; do
    source "${module_group}"
done

for protocol_module in \
    "${SCRIPT_DIR}/lib/protocols/shared.sh" \
    "${SCRIPT_DIR}/lib/protocols/vless_tcp_tls.sh" \
    "${SCRIPT_DIR}/lib/protocols/vless_ws_tls.sh" \
    "${SCRIPT_DIR}/lib/protocols/vmess_ws_tls.sh" \
    "${SCRIPT_DIR}/lib/protocols/vless_reality_tcp.sh" \
    "${SCRIPT_DIR}/lib/protocols/vless_xhttp.sh" \
    "${SCRIPT_DIR}/lib/protocols/compose.sh"; do
    source "${protocol_module}"
done

for account_module in \
    "${SCRIPT_DIR}/lib/accounts/users.sh" \
    "${SCRIPT_DIR}/lib/accounts/show.sh" \
    "${SCRIPT_DIR}/lib/accounts/export_vless.sh" \
    "${SCRIPT_DIR}/lib/accounts/export_vmess.sh" \
    "${SCRIPT_DIR}/lib/accounts/export_matrix.sh"; do
    source "${account_module}"
done

for routing_module in \
    "${SCRIPT_DIR}/lib/routing/base.sh" \
    "${SCRIPT_DIR}/lib/routing/ipv6.sh" \
    "${SCRIPT_DIR}/lib/routing/warp.sh" \
    "${SCRIPT_DIR}/lib/routing/blacklist.sh" \
    "${SCRIPT_DIR}/lib/routing/outbounds.sh" \
    "${SCRIPT_DIR}/lib/routing/rules.sh"; do
    source "${routing_module}"
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
            xray_agent_run_install_profile tls_vision_xhttp
            ;;
        2)
            xray_agent_run_install_profile reality_vision_xhttp
            ;;
        3)
            xray_agent_run_install_profile tls_vision_xhttp
            ;;
        4)
            xray_agent_run_install_profile reality_vision_xhttp
            ;;
        5)
            xray_agent_install_hysteria2_native
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
            xray_agent_run_install_profile tls_vision_xhttp
            ;;
        2)
            xray_agent_run_install_profile reality_vision_xhttp
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
            xray_agent_external_warp_menu
            ;;
        18)
            xray_agent_external_kernel_bbr
            ;;
        19)
            xray_agent_external_hysteria_oneclick
            ;;
        20)
            xray_agent_external_hyperspeed
            ;;
        21)
            xray_agent_external_backtrace
            ;;
        22)
            xray_agent_external_unlock_media
            ;;
        23)
            xray_agent_external_vps_info
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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
