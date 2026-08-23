#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_external_backtrace() {
    bash <(curl https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh -sSf)
}

xray_agent_external_hyperspeed() {
    bash <(curl -Lso- https://bench.im/hyperspeed)
}

xray_agent_external_kernel_bbr() {
    wget -N https://raw.githubusercontent.com/jinwyp/one_click_script/master/install_kernel.sh && bash install_kernel.sh
}

xray_agent_external_unlock_media() {
    bash <(curl -L -s check.unlock.media)
}

xray_agent_external_vps_info() {
    wget -q https://github.com/Aniverse/A/raw/i/a && bash a
}

xray_agent_external_record_warp_interface() {
    local interface_name="$1"
    local state_path temp_path
    [[ -n "${interface_name}" ]] || return 1
    state_path="$(xray_agent_warp_provider_state_path)"
    mkdir -p "$(dirname "${state_path}")"
    temp_path="${state_path}.tmp"
    jq -nc --arg interface "${interface_name}" --arg provider "fscarmen/warp" '{schemaVersion:1,provider:$provider,interface:$interface}' >"${temp_path}" || return 1
    mv "${temp_path}" "${state_path}"
}

xray_agent_external_warp_menu() {
    local before_interfaces after_interfaces new_interfaces status detected_interface
    before_interfaces="$(xray_agent_wireguard_interfaces | sort -u)"
    status=0
    wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh || status=$?
    after_interfaces="$(xray_agent_wireguard_interfaces | sort -u)"
    new_interfaces="$(comm -13 <(printf '%s\n' "${before_interfaces}") <(printf '%s\n' "${after_interfaces}") | sed '/^$/d')"
    if [[ "$(printf '%s\n' "${new_interfaces}" | sed '/^$/d' | wc -l | tr -d ' ')" == "1" ]]; then
        xray_agent_external_record_warp_interface "${new_interfaces}" || true
    fi
    networkDetected=false
    xray_agent_detect_network_capabilities --refresh || true
    detected_interface="${warpInterface:-}"
    if [[ -n "${detected_interface}" ]]; then
        xray_agent_external_record_warp_interface "${detected_interface}" || true
    fi
    xray_agent_network_summary
    if declare -F xray_agent_egress_catalog_json >/dev/null 2>&1; then
        xray_agent_egress_catalog_json | jq -r '.egresses[] | [.id,(if .available then "可用" else "不可用: " + .reason end)] | @tsv'
    fi
    if declare -F xray_agent_egress_policy_read >/dev/null 2>&1 && xray_agent_egress_policy_read >/dev/null 2>&1; then
        if ! xray_agent_egress_policy_validate_json "$(xray_agent_egress_policy_read)"; then
            echoContent yellow " ---> WARP 状态变化后，当前 Xray 出口策略包含不可用出口；旧配置未自动回退，请从菜单6或8调整"
        fi
    fi
    return "${status}"
}
