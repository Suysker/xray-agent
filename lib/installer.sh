#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_prepare_uuid() {
    if [[ -n "${UUID}" ]]; then
        read -r -p "读取到上次安装记录，是否使用上次安装时的UUID ？[y/n]:" historyUUIDStatus
        if [[ "${historyUUIDStatus}" != "y" ]]; then
            echoContent yellow "请输入自定义UUID[需合法](支持以逗号为分割输入多个)，[回车]随机UUID"
            read -r -p 'UUID:' UUID
        else
            echoContent green " ---> 使用成功"
        fi
    else
        echoContent yellow "请输入自定义UUID[需合法](支持以逗号为分割输入多个)，[回车]随机UUID"
        read -r -p 'UUID:' UUID
    fi
    if [[ -z "${UUID}" ]]; then
        echoContent red " ---> uuid读取错误，重新生成"
        UUID=$(${ctlPath} uuid)
    fi
    echoContent yellow " ${UUID}"
}

xray_agent_prepare_reality_keys() {
    echoContent skyBlue "========================== 生成key =========================="
    if [[ -n "${RealityPrivateKey}" || -n "${RealityPublicKey}" ]]; then
        read -r -p "读取到上次安装记录，是否使用上次安装时的PublicKey/PrivateKey ？[y/n]:" historyKeyStatus
        if [[ "${historyKeyStatus}" == "y" && -n "${RealityPrivateKey}" ]]; then
            xray_agent_ensure_reality_public_key || true
            echoContent green " ---> 使用成功"
        else
            if ! xray_agent_generate_reality_keypair; then
                echoContent red " ---> Reality key 生成失败"
                return 1
            fi
        fi
    else
        echoContent yellow "请输入自定义PrivateKey[需合法],[回车]随机"
        read -r -p 'PrivateKey:' RealityPrivateKey
        echoContent yellow "请输入自定义PublicKey[需合法],[回车]随机"
        read -r -p 'PublicKey:' RealityPublicKey
        if [[ -n "${RealityPrivateKey}" ]]; then
            local derived_public_key
            derived_public_key="$(xray_agent_reality_public_key_from_private "${RealityPrivateKey}" || true)"
            if [[ -n "${derived_public_key}" ]]; then
                if [[ -n "${RealityPublicKey}" && "${RealityPublicKey}" != "${derived_public_key}" ]]; then
                    echoContent yellow " ---> PublicKey 与 PrivateKey 不匹配，已按 PrivateKey 重新计算"
                fi
                RealityPublicKey="${derived_public_key}"
            fi
        fi
        if [[ -z "${RealityPrivateKey}" || -z "${RealityPublicKey}" ]]; then
            if ! xray_agent_generate_reality_keypair; then
                echoContent red " ---> Reality key 生成失败"
                return 1
            fi
        fi
    fi
    if [[ -z "${RealityShortID}" ]]; then
        RealityShortID=$(openssl rand -hex 4 2>/dev/null)
    fi
    echoContent green " privateKey:${RealityPrivateKey}"
    echoContent green " publicKey:${RealityPublicKey}"
    echoContent skyBlue "========================== 生成UUID =========================="
}

xray_agent_reset_install_profile() {
    XRAY_AGENT_INSTALL_PROFILE_NAME=
    XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS=
    XRAY_AGENT_INSTALL_PROFILE_ENTRY=
    XRAY_AGENT_INSTALL_PROFILE_STEPS=
}

xray_agent_default_install_profile_steps() {
    local entry_name="$1"
    case "${entry_name}" in
        xrayCoreInstall)
            echo "install_tools,init_tls_nginx,stop_xray,install_tls,install_xray,install_service,random_path,custom_port_vision,update_nginx_vision,render_tls_bundle,install_cron_tls,reload_core,update_geodata,check_gfw,show_accounts"
            ;;
        xrayCoreInstall_Reality)
            echo "install_tools,stop_xray,install_xray,install_service,init_reality,warning_reality_target,random_path,custom_port_reality,warning_xhttp_port,update_nginx_reality,optional_hysteria2,render_reality_bundle,reload_core,update_geodata,check_gfw,show_accounts"
            ;;
    esac
}

xray_agent_set_install_profile_defaults() {
    local entry_name="$1"
    case "${entry_name}" in
        xrayCoreInstall)
            XRAY_AGENT_INSTALL_PROFILE_NAME="${XRAY_AGENT_INSTALL_PROFILE_NAME:-tls_vision_xhttp}"
            XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS="${XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS:-vless_tcp_tls,vless_ws_tls,vmess_ws_tls,vless_xhttp,hysteria2}"
            XRAY_AGENT_INSTALL_PROFILE_ENTRY="xrayCoreInstall"
            XRAY_AGENT_INSTALL_PROFILE_STEPS="${XRAY_AGENT_INSTALL_PROFILE_STEPS:-$(xray_agent_default_install_profile_steps "xrayCoreInstall")}"
            ;;
        xrayCoreInstall_Reality)
            XRAY_AGENT_INSTALL_PROFILE_NAME="${XRAY_AGENT_INSTALL_PROFILE_NAME:-reality_vision_xhttp}"
            XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS="${XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS:-vless_reality_tcp,vless_xhttp}"
            XRAY_AGENT_INSTALL_PROFILE_ENTRY="xrayCoreInstall_Reality"
            XRAY_AGENT_INSTALL_PROFILE_STEPS="${XRAY_AGENT_INSTALL_PROFILE_STEPS:-$(xray_agent_default_install_profile_steps "xrayCoreInstall_Reality")}"
            ;;
    esac
}

xray_agent_ensure_install_profile_for_entry() {
    local entry_name="$1"
    if [[ -z "${XRAY_AGENT_INSTALL_PROFILE_ENTRY:-}" ]] || [[ "${XRAY_AGENT_INSTALL_PROFILE_ENTRY:-}" == "${entry_name}" && ( -z "${XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS:-}" || -z "${XRAY_AGENT_INSTALL_PROFILE_STEPS:-}" ) ]]; then
        xray_agent_set_install_profile_defaults "${entry_name}"
    fi
}

xray_agent_validate_install_profile() {
    local profile_name="$1"
    local missing_fields=()
    [[ -n "${XRAY_AGENT_INSTALL_PROFILE_NAME}" ]] || missing_fields+=("name")
    [[ -n "${XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS}" ]] || missing_fields+=("protocols")
    [[ -n "${XRAY_AGENT_INSTALL_PROFILE_ENTRY}" ]] || missing_fields+=("entry")
    [[ -n "${XRAY_AGENT_INSTALL_PROFILE_STEPS}" ]] || missing_fields+=("steps")

    if ((${#missing_fields[@]} > 0)); then
        echoContent red " ---> install profile [${profile_name}] 缺少字段: $(xray_agent_join_by "," "${missing_fields[@]}")"
        return 1
    fi

    case "${XRAY_AGENT_INSTALL_PROFILE_ENTRY}" in
        xrayCoreInstall | xrayCoreInstall_Reality)
            ;;
        *)
            echoContent red " ---> install profile [${profile_name}] entry 不支持: ${XRAY_AGENT_INSTALL_PROFILE_ENTRY}"
            return 1
            ;;
    esac
}

xray_agent_load_install_profile() {
    local profile_name="$1"
    local profile_path="${XRAY_AGENT_PROFILE_DIR}/install/${profile_name}.profile"
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
            steps) XRAY_AGENT_INSTALL_PROFILE_STEPS="${value}" ;;
        esac
    done <"${profile_path}"

    xray_agent_validate_install_profile "${profile_name}"
}

xray_agent_dispatch_install_profile_step() {
    local step_name="$1"
    local progress_index="$2"
    case "${step_name}" in
        install_tools) installTools "${progress_index}" ;;
        init_tls_nginx) initTLSNginxConfig "${progress_index}" ;;
        stop_xray) handleXray stop ;;
        install_tls) installTLS "${progress_index}" 0 ;;
        install_xray) installXray "${progress_index}" ;;
        install_service) installXrayService "${progress_index}" ;;
        init_reality) initTLSRealityConfig "${progress_index}" ;;
        warning_reality_target) xray_agent_tls_warning_for_target "${RealityDestDomain}" ;;
        random_path) randomPathFunction "${progress_index}" ;;
        custom_port_vision) customPortFunction "Vision" ;;
        custom_port_reality) customPortFunction "Reality" ;;
        warning_xhttp_port) xray_agent_tls_warning_for_xhttp_port "${RealityPort}" ;;
        update_nginx_vision) updateRedirectNginxConf "Vision" "${progress_index}" ;;
        update_nginx_reality) updateRedirectNginxConf "Reality" "${progress_index}" ;;
        optional_hysteria2) xray_agent_offer_optional_hysteria2 "${progress_index}" ;;
        render_tls_bundle) xray_agent_render_tls_bundle ;;
        render_reality_bundle) xray_agent_render_reality_bundle ;;
        install_cron_tls) installCronTLS "${progress_index}" ;;
        reload_core) reloadCore ;;
        update_geodata) auto_update_geodata ;;
        check_gfw) checkGFWStatue "${progress_index}" ;;
        show_accounts) showAccounts "${progress_index}" ;;
        *)
            echoContent red " ---> 未知安装步骤: ${step_name}"
            return 1
            ;;
    esac
}

xray_agent_install_profile_append_protocol() {
    local protocol_name="$1"
    case ",${XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS}," in
        *",${protocol_name},"*) ;;
        *) XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS="${XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS},${protocol_name}" ;;
    esac
}

xray_agent_offer_optional_hysteria2() {
    local progress_index="$1"
    local default_answer="n"
    local answer prompt
    xray_agent_blank
    echoContent skyBlue "进度 ${progress_index}/${totalProgress} : Hysteria2可选安装"
    if [[ -f "${configPath}09_Hysteria2_inbounds.json" ]]; then
        default_answer="y"
        prompt="检测到已有 Hysteria2 配置，是否保留并重配到本次 Reality 套餐？[Y/n]:"
    else
        prompt="是否同时安装 Hysteria2？[y/N]:"
    fi
    read -r -p "${prompt}" answer
    answer="${answer:-${default_answer}}"
    if [[ "${answer}" == "y" || "${answer}" == "Y" ]]; then
        xray_agent_install_profile_append_protocol "hysteria2"
    fi
}

xray_agent_run_install_profile_steps() {
    local progress_index=0
    local step_name
    local install_profile_steps="${XRAY_AGENT_INSTALL_PROFILE_STEPS:-}"
    local install_profile_step_list=()

    [[ -n "${install_profile_steps}" ]] || return 1

    IFS=',' read -r -a install_profile_step_list <<<"${install_profile_steps}"
    totalProgress="${#install_profile_step_list[@]}"

    for step_name in "${install_profile_step_list[@]}"; do
        progress_index=$((progress_index + 1))
        xray_agent_dispatch_install_profile_step "${step_name}" "${progress_index}" || return 1
    done
}

xray_agent_execute_install_profile() {
    if [[ -n "${XRAY_AGENT_INSTALL_PROFILE_STEPS:-}" ]]; then
        xray_agent_run_install_profile_steps
        return $?
    fi
    "${XRAY_AGENT_INSTALL_PROFILE_ENTRY}"
}

xray_agent_run_install_profile() {
    xray_agent_load_install_profile "$1" || return 1
    xray_agent_execute_install_profile
}

xray_agent_install_profile_has_protocol() {
    local protocol_name="$1"
    case ",${XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS}," in
        *",${protocol_name},"*) return 0 ;;
        *) return 1 ;;
    esac
}

xray_agent_clients_json_for_protocol_profile() {
    local profile_name="$1"
    xray_agent_load_protocol_profile "${profile_name}" || return 1
    xray_agent_generate_clients_json "${XRAY_AGENT_PROTOCOL_CLIENT_KIND}" "${UUID}"
}

xray_agent_render_install_profile_protocol() {
    local protocol_name="$1"
    local accept_proxy_protocol="$2"
    local sniffing_json="$3"
    local clients_json rendered_path=

    case "${protocol_name}" in
        vless_tcp_tls)
            clients_json="$(xray_agent_clients_json_for_protocol_profile "${protocol_name}")" || return 1
            xray_agent_render_vless_tcp_tls_inbound "${clients_json}" "${accept_proxy_protocol}" "${sniffing_json}"
            rendered_path="${configPath}02_VLESS_TCP_inbounds.json"
            ;;
        vless_ws_tls)
            clients_json="$(xray_agent_clients_json_for_protocol_profile "${protocol_name}")" || return 1
            xray_agent_render_vless_ws_legacy_config "${clients_json}" "${sniffing_json}"
            rendered_path="${configPath}03_VLESS_WS_inbounds.json"
            ;;
        vmess_ws_tls)
            clients_json="$(xray_agent_clients_json_for_protocol_profile "${protocol_name}")" || return 1
            xray_agent_render_vmess_ws_legacy_config "${clients_json}" "${sniffing_json}"
            rendered_path="${configPath}05_VMess_WS_inbounds.json"
            ;;
        vless_reality_tcp)
            clients_json="$(xray_agent_clients_json_for_protocol_profile "${protocol_name}")" || return 1
            xray_agent_render_vless_reality_tcp_inbound "${clients_json}" "${accept_proxy_protocol}" "${sniffing_json}"
            rendered_path="${configPath}07_VLESS_Reality_TCP_inbounds.json"
            ;;
        vless_xhttp)
            clients_json="$(xray_agent_clients_json_for_protocol_profile "${protocol_name}")" || return 1
            xray_agent_render_vless_xhttp_inbound "${clients_json}" "31305" "${sniffing_json}"
            rendered_path="${configPath}08_VLESS_XHTTP_inbounds.json"
            ;;
        hysteria2)
            clients_json="$(xray_agent_clients_json_for_protocol_profile "${protocol_name}")" || return 1
            xray_agent_render_hysteria2_inbound "${clients_json}" "${sniffing_json}"
            rendered_path="${configPath}09_Hysteria2_inbounds.json"
            ;;
        *)
            echoContent red " ---> 未知协议 profile: ${protocol_name}"
            return 1
            ;;
    esac

    printf '%s\n' "${rendered_path}"
}

xray_agent_apply_install_profile_trusted_xff_patches() {
    declare -F xray_agent_apply_trusted_xff_patch >/dev/null 2>&1 || return 0
    local target_path
    for target_path in "$@"; do
        [[ -f "${target_path}" ]] || continue
        xray_agent_apply_trusted_xff_patch "${target_path}"
    done
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
    export XRAY_ROUTING_DOMAIN_STRATEGY
    export XRAY_DNS_SERVERS_JSON
    export XRAY_DNS_QUERY_STRATEGY
    XRAY_OUTBOUNDS_JSON="$(xray_agent_default_outbounds_json)"
    XRAY_ROUTING_RULES_JSON="$(xray_agent_default_routing_rules_json)"
    XRAY_DNS_SERVERS_JSON="$(xray_agent_default_dns_servers_json)"
    XRAY_ROUTING_DOMAIN_STRATEGY="$(xray_agent_default_routing_domain_strategy)"
    XRAY_DNS_QUERY_STRATEGY="$(xray_agent_default_dns_query_strategy)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/00_log.json.tpl" "${configPath}00_log.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/01_policy.json.tpl" "${configPath}01_policy.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/09_routing.json.tpl" "${configPath}09_routing.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/10_outbounds.json.tpl" "${configPath}10_ipv4_outbounds.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/11_dns.json.tpl" "${configPath}11_dns.json"
}

xray_agent_render_install_bundle() {
    local entry_name="$1"
    local key_prepare_fn="$2"
    local accept_proxy_protocol="false"
    local sniffing_json protocol_name rendered_path
    local rendered_paths=()

    xray_agent_ensure_install_profile_for_entry "${entry_name}"
    if [[ -n "${key_prepare_fn}" ]]; then
        "${key_prepare_fn}"
    fi
    xray_agent_prepare_uuid
    xray_agent_render_common_xray_configs

    if [[ "${reuse443}" == "y" ]]; then
        accept_proxy_protocol="true"
    fi

    sniffing_json="$(xray_agent_default_sniffing_json)"
    IFS=',' read -r -a XRAY_AGENT_INSTALL_PROFILE_PROTOCOL_LIST <<<"${XRAY_AGENT_INSTALL_PROFILE_PROTOCOLS}"
    for protocol_name in "${XRAY_AGENT_INSTALL_PROFILE_PROTOCOL_LIST[@]}"; do
        if [[ "${protocol_name}" == "hysteria2" ]]; then
            xray_agent_hysteria2_prepare_runtime || return 1
        fi
        rendered_path="$(xray_agent_render_install_profile_protocol "${protocol_name}" "${accept_proxy_protocol}" "${sniffing_json}")" || return 1
        [[ -n "${rendered_path}" ]] || continue
        rendered_paths+=("${rendered_path}")
    done
    xray_agent_apply_install_profile_trusted_xff_patches "${rendered_paths[@]}"
}

xray_agent_render_tls_bundle() {
    xray_agent_render_install_bundle "xrayCoreInstall" ""
}

xray_agent_render_reality_bundle() {
    xray_agent_render_install_bundle "xrayCoreInstall_Reality" "xray_agent_prepare_reality_keys"
}

initXrayRealityConfig() {
    xray_agent_blank
    echoContent skyBlue "进度 $1/${totalProgress} : 初始化 Xray-core Reality配置"
    xray_agent_render_reality_bundle
}

initXrayConfig() {
    xray_agent_blank
    echoContent skyBlue "进度 $1/${totalProgress} : 初始化Xray配置"
    xray_agent_render_tls_bundle
}

xrayCoreInstall() {
    xray_agent_ensure_install_profile_for_entry "xrayCoreInstall"
    xray_agent_run_install_profile_steps
}

xrayCoreInstall_Reality() {
    xray_agent_ensure_install_profile_for_entry "xrayCoreInstall_Reality"
    xray_agent_run_install_profile_steps
}
