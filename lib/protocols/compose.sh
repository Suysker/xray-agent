if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_reset_install_profile() {
    XRAY_AGENT_INSTALL_PROFILE_NAME=
    XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS=
    XRAY_AGENT_INSTALL_PROFILE_ENTRY=
}

xray_agent_load_install_profile() {
    local profile_path="${XRAY_AGENT_PROFILE_DIR}/install/$1.profile"
    local key value
    if [[ ! -r "${profile_path}" ]]; then
        return 1
    fi

    xray_agent_reset_install_profile
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        case "${key}" in
            name) XRAY_AGENT_INSTALL_PROFILE_NAME="${value}" ;;
            protocols) XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS="${value}" ;;
            entry) XRAY_AGENT_INSTALL_PROFILE_ENTRY="${value}" ;;
        esac
    done <"${profile_path}"
}

xray_agent_run_install_profile() {
    xray_agent_load_install_profile "$1" || return 1
    "${XRAY_AGENT_INSTALL_PROFILE_ENTRY}"
}

xray_agent_render_common_xray_configs() {
    local keepconfigstatus="n"
    if [[ -f "${configPath}10_ipv4_outbounds.json" ]] || [[ -f "${configPath}09_routing.json" ]]; then
        read -r -p "是否保留路由和分流规则 ？[y/n]:" keepconfigstatus
    fi
    if [[ "${keepconfigstatus}" == "y" ]]; then
        return 0
    fi
    export XRAY_LOG_ERROR_PATH="/etc/xray-agent/xray/error.log"
    export XRAY_LOG_LEVEL="warning"
    export XRAY_POLICY_HANDSHAKE=$((RANDOM % 4 + 2))
    export XRAY_POLICY_CONN_IDLE=$(((RANDOM % 11) * 30 + 300))
    export XRAY_OUTBOUNDS_JSON
    export XRAY_ROUTING_RULES_JSON
    export XRAY_ROUTING_DOMAIN_STRATEGY="AsIs"
    export XRAY_DNS_SERVERS_JSON
    export XRAY_DNS_QUERY_STRATEGY="UseIP"
    XRAY_OUTBOUNDS_JSON="$(xray_agent_default_outbounds_json)"
    XRAY_ROUTING_RULES_JSON="$(xray_agent_default_routing_rules_json)"
    XRAY_DNS_SERVERS_JSON="$(xray_agent_default_dns_servers_json)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/00_log.json.tpl" "${configPath}00_log.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/01_policy.json.tpl" "${configPath}01_policy.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/09_routing.json.tpl" "${configPath}09_routing.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/10_outbounds.json.tpl" "${configPath}10_ipv4_outbounds.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/11_dns.json.tpl" "${configPath}11_dns.json"
}

xray_agent_render_tls_bundle() {
    xray_agent_prepare_uuid
    xray_agent_render_common_xray_configs
    local accept_proxy_protocol="false"
    local vless_tcp_clients_json vless_xhttp_clients_json vmess_clients_json sniffing_json
    if [[ "${reuse443}" == "y" ]]; then
        accept_proxy_protocol="true"
    fi
    vless_tcp_clients_json="$(xray_agent_generate_clients_json "VLESS_TCP" "${UUID}")"
    vless_xhttp_clients_json="$(xray_agent_generate_clients_json "VLESS_XHTTP" "${UUID}")"
    vmess_clients_json="$(xray_agent_generate_clients_json "VMESS_WS" "${UUID}")"
    sniffing_json="$(xray_agent_default_sniffing_json)"
    xray_agent_render_vless_tcp_tls_inbound "${vless_tcp_clients_json}" "${accept_proxy_protocol}" "${sniffing_json}"
    xray_agent_render_vless_ws_legacy_config "${vless_xhttp_clients_json}" "${sniffing_json}"
    xray_agent_render_vmess_ws_legacy_config "${vmess_clients_json}" "${sniffing_json}"
    xray_agent_render_vless_xhttp_inbound "${vless_xhttp_clients_json}" "31305" "${sniffing_json}"
    if declare -F xray_agent_apply_tls_feature_patches >/dev/null 2>&1; then
        xray_agent_apply_tls_feature_patches "${configPath}02_VLESS_TCP_inbounds.json" "${configPath}08_VLESS_XHTTP_inbounds.json"
    fi
}

xray_agent_render_reality_bundle() {
    xray_agent_prepare_reality_keys
    xray_agent_prepare_uuid
    xray_agent_render_common_xray_configs
    local accept_proxy_protocol="false"
    local reality_clients_json xhttp_clients_json sniffing_json
    if [[ "${reuse443}" == "y" ]]; then
        accept_proxy_protocol="true"
    fi
    reality_clients_json="$(xray_agent_generate_clients_json "VLESS_TCP" "${UUID}")"
    xhttp_clients_json="$(xray_agent_generate_clients_json "VLESS_XHTTP" "${UUID}")"
    sniffing_json="$(xray_agent_default_sniffing_json)"
    xray_agent_render_vless_reality_tcp_inbound "${reality_clients_json}" "${accept_proxy_protocol}" "${sniffing_json}"
    xray_agent_render_vless_xhttp_inbound "${xhttp_clients_json}" "31305" "${sniffing_json}"
    if declare -F xray_agent_apply_reality_feature_patches >/dev/null 2>&1; then
        xray_agent_apply_reality_feature_patches "${configPath}07_VLESS_Reality_TCP_inbounds.json" "${configPath}08_VLESS_XHTTP_inbounds.json"
    fi
}

initXrayRealityConfig() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 初始化 Xray-core Reality配置"
    xray_agent_render_reality_bundle
}

initXrayConfig() {
    echoContent skyBlue "\n进度 $1/${totalProgress} : 初始化Xray配置"
    xray_agent_render_tls_bundle
}

xrayCoreInstall() {
    totalProgress=11
    installTools 1
    initTLSNginxConfig 2
    handleXray stop
    installTLS 3 0
    installXray 4
    installXrayService 5
    randomPathFunction 6
    customPortFunction "Vision"
    updateRedirectNginxConf "Vision" 7
    xray_agent_render_tls_bundle
    installCronTLS 9
    reloadCore
    auto_update_geodata
    checkGFWStatue 10
    showAccounts 11
}

xrayCoreInstall_Reality() {
    totalProgress=8
    installTools 1
    handleXray stop
    installXray 2
    installXrayService 3
    initTLSRealityConfig 4
    xray_agent_tls_warning_for_target "${RealityDestDomain}"
    randomPathFunction 5
    customPortFunction "Reality"
    xray_agent_tls_warning_for_xhttp_port "${RealityPort}"
    updateRedirectNginxConf "Reality" 5.5
    xray_agent_render_reality_bundle
    reloadCore
    auto_update_geodata
    checkGFWStatue 7
    showAccounts 8
}
