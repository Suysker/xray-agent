if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_apply_hysteria2_feature_patches() {
    local target_path="$1"

    if declare -F xray_agent_apply_finalmask_patch >/dev/null 2>&1; then
        xray_agent_apply_finalmask_patch "${target_path}"
    fi
}

xray_agent_render_hysteria2_profile() {
    xray_agent_prepare_uuid
    xray_agent_render_common_xray_configs
    export XRAY_INBOUND_PORT="${Port:-8443}"
    export XRAY_INBOUND_TAG="HYSTERIA2"
    export XRAY_TLS_DOMAIN="${TLSDomain}"
    export XRAY_HYSTERIA_USERS_JSON
    export XRAY_HYSTERIA_SETTINGS_JSON
    export XRAY_SOCKOPT_JSON
    export XRAY_SNIFFING_JSON
    XRAY_HYSTERIA_USERS_JSON="$(xray_agent_generate_hysteria_users_json "${UUID}")"
    XRAY_HYSTERIA_SETTINGS_JSON="$(jq -nc '{password: "", up_mbps: 200, down_mbps: 1000}')"
    XRAY_SOCKOPT_JSON="$(xray_agent_default_sockopt_json)"
    XRAY_SNIFFING_JSON="$(xray_agent_default_sniffing_json)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/12_hysteria2.json.tpl" "${configPath}12_HYSTERIA2_inbounds.json"
    xray_agent_apply_hysteria2_feature_patches "${configPath}12_HYSTERIA2_inbounds.json"
}

xray_agent_install_hysteria2_native() {
    totalProgress=9
    installTools 1
    initTLSNginxConfig 2
    handleXray stop
    installTLS 3 0
    installXray 4
    installXrayService 5
    echoContent yellow "请输入 Hysteria2 监听端口[回车默认 8443]"
    read -r -p "端口:" Port
    if [[ -z "${Port}" ]]; then
        Port=8443
    fi
    checkPort "${Port}"
    allowPort "${Port}" udp
    allowPort "${Port}" tcp
    xray_agent_render_hysteria2_profile
    reloadCore
    auto_update_geodata
    checkGFWStatue 8
}
