#!/usr/bin/env bash

export LANG=en_US.UTF-8

SCRIPT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export XRAY_AGENT_PROJECT_ROOT="${SCRIPT_DIR}"

XRAY_AGENT_PROJECT_REPO="${XRAY_AGENT_PROJECT_REPO:-https://github.com/Suysker/xray-agent}"
XRAY_AGENT_BOOTSTRAP_BRANCH="${XRAY_AGENT_BOOTSTRAP_BRANCH:-master}"
XRAY_AGENT_BOOTSTRAP_TARGET_ROOT="${XRAY_AGENT_BOOTSTRAP_TARGET_ROOT:-/etc/xray-agent}"
XRAY_AGENT_BOOTSTRAP_ARCHIVE_URL="${XRAY_AGENT_BOOTSTRAP_ARCHIVE_URL:-${XRAY_AGENT_PROJECT_REPO}/archive/refs/heads/${XRAY_AGENT_BOOTSTRAP_BRANCH}.tar.gz}"

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

xray_agent_runtime_layout_complete() {
    [[ -f "${SCRIPT_DIR}/lib/common.sh" ]] &&
        [[ -f "${SCRIPT_DIR}/lib/runtime.sh" ]] &&
        [[ -f "${SCRIPT_DIR}/lib/system.sh" ]] &&
        [[ -f "${SCRIPT_DIR}/lib/tls.sh" ]] &&
        [[ -f "${SCRIPT_DIR}/lib/core.sh" ]] &&
        [[ -f "${SCRIPT_DIR}/lib/nginx.sh" ]] &&
        [[ -f "${SCRIPT_DIR}/lib/protocols.sh" ]] &&
        [[ -f "${SCRIPT_DIR}/lib/accounts.sh" ]] &&
        [[ -f "${SCRIPT_DIR}/lib/routing.sh" ]] &&
        [[ -f "${SCRIPT_DIR}/lib/features.sh" ]] &&
        [[ -f "${SCRIPT_DIR}/lib/apps.sh" ]] &&
        [[ -f "${SCRIPT_DIR}/lib/external.sh" ]] &&
        [[ -d "${SCRIPT_DIR}/profiles/install" ]] &&
        [[ -d "${SCRIPT_DIR}/templates/xray" ]] &&
        [[ -d "${SCRIPT_DIR}/templates/nginx" ]] &&
        [[ -d "${SCRIPT_DIR}/templates/systemd" ]] &&
        [[ -d "${SCRIPT_DIR}/templates/share" ]] &&
        [[ -d "${SCRIPT_DIR}/packaging" ]]
}

xray_agent_download_bootstrap_archive() {
    local archive_path="$1"
    local archive_source="${XRAY_AGENT_BOOTSTRAP_ARCHIVE:-}"

    if [[ -n "${archive_source}" && -f "${archive_source}" ]]; then
        cp "${archive_source}" "${archive_path}"
        return 0
    fi

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${archive_source:-${XRAY_AGENT_BOOTSTRAP_ARCHIVE_URL}}" -o "${archive_path}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "${archive_path}" "${archive_source:-${XRAY_AGENT_BOOTSTRAP_ARCHIVE_URL}}"
    else
        echo "curl or wget is required to bootstrap xray-agent" >&2
        return 1
    fi
}

xray_agent_bootstrap_full_layout() {
    local temp_dir archive_path layout_script target_root
    target_root="${XRAY_AGENT_BOOTSTRAP_TARGET_ROOT}"
    temp_dir="$(mktemp -d)"
    archive_path="${temp_dir}/xray-agent.tar.gz"

    xray_agent_download_bootstrap_archive "${archive_path}" || return 1
    tar -xzf "${archive_path}" -C "${temp_dir}"

    layout_script="$(find "${temp_dir}" -mindepth 3 -maxdepth 4 -path "*/packaging/install-layout.sh" -print -quit)"
    if [[ -z "${layout_script}" ]]; then
        echo "Downloaded xray-agent archive does not contain packaging/install-layout.sh" >&2
        return 1
    fi

    bash "${layout_script}" "${target_root}"
    chmod 700 "${target_root}/install.sh"
    if [[ "${XRAY_AGENT_BOOTSTRAP_NO_EXEC:-false}" == "true" ]]; then
        rm -rf "${temp_dir}"
        exit 0
    fi
    rm -rf "${temp_dir}"
    exec bash "${target_root}/install.sh" "$@"
}

if ! xray_agent_runtime_layout_complete; then
    if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
        echo "xray-agent runtime layout is incomplete; execute install.sh to bootstrap the full layout" >&2
        return 1
    fi
    xray_agent_bootstrap_full_layout "$@"
fi

xray_agent_ensure_jq_on_path

for module_file in \
    "${SCRIPT_DIR}/lib/common.sh" \
    "${SCRIPT_DIR}/lib/runtime.sh" \
    "${SCRIPT_DIR}/lib/system.sh" \
    "${SCRIPT_DIR}/lib/tls.sh" \
    "${SCRIPT_DIR}/lib/core.sh" \
    "${SCRIPT_DIR}/lib/nginx.sh" \
    "${SCRIPT_DIR}/lib/features.sh" \
    "${SCRIPT_DIR}/lib/apps.sh" \
    "${SCRIPT_DIR}/lib/external.sh" \
    "${SCRIPT_DIR}/lib/routing.sh" \
    "${SCRIPT_DIR}/lib/protocols.sh" \
    "${SCRIPT_DIR}/lib/accounts.sh"; do
    source "${module_file}"
done

menu() {
    cd "$HOME" || exit
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
