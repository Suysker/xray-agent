#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_uuid_exists_anywhere() {
    local candidate_uuid="$1"
    local config_file
    while IFS= read -r config_file; do
        [[ -f "${config_file}" ]] || continue
        if jq -e --arg uuid "${candidate_uuid}" 'any(.inbounds[0].settings.clients[]?; (.id? == $uuid) or (.auth? == $uuid))' "${config_file}" >/dev/null 2>&1; then
            return 0
        fi
    done < <(find "${configPath}" -maxdepth 1 -type f -name "*_inbounds.json" 2>/dev/null)
    return 1
}

customUUID() {
    read -r -p "请输入合法的UUID，[回车]随机UUID:" currentCustomUUID
    if [[ -z "${currentCustomUUID}" ]]; then
        currentCustomUUID=$(${ctlPath} uuid)
        echoContent yellow "uuid：${currentCustomUUID}"
        return 0
    fi

    if ! xray_agent_validate_uuid "${currentCustomUUID}"; then
        echoContent red " ---> UUID格式不合法，请重新输入"
        currentCustomUUID=
        customUUID
        return 0
    fi

    if xray_agent_uuid_exists_anywhere "${currentCustomUUID}"; then
        echoContent red " ---> UUID已存在，请重新输入"
        currentCustomUUID=
        customUUID
        return 0
    fi
}

xray_agent_append_client_to_inbound() {
    local target_file="$1"
    local client_json="$2"
    xray_agent_json_update_file "${target_file}" '.inbounds[0].settings.clients += [$client]' --argjson client "${client_json}"
}

addUser() {
    read -r -p "请输入要添加的用户数量:" userNum
    if ! [[ "${userNum}" =~ ^[0-9]+$ ]] || [[ "${userNum}" -le 0 ]]; then
        echoContent red " ---> 用户数量必须是大于 0 的整数"
        return 0
    fi
    if [[ "${userNum}" == "1" ]]; then
        customUUID
    fi
    while [[ ${userNum} -gt 0 ]]; do
        ((userNum--)) || true
        if [[ -n "${currentCustomUUID}" ]]; then
            uuid=${currentCustomUUID}
        else
            uuid=$(${ctlPath} uuid)
        fi
        users="{\"id\":\"${uuid}\",\"flow\":\"xtls-rprx-vision\",\"alterId\":0}"
        if echo "${currentInstallProtocolType}" | grep -q 0; then
            local vless_tcp_user="${users//\,\"alterId\":0/}"
            xray_agent_append_client_to_inbound "${configPath}${frontingType}.json" "${vless_tcp_user}"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 1; then
            local vless_ws_user="${users//\,\"alterId\":0/}"
            vless_ws_user="${vless_ws_user//\"flow\":\"xtls-rprx-vision\"\,/}"
            xray_agent_append_client_to_inbound "${configPath}03_VLESS_WS_inbounds.json" "${vless_ws_user}"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 2; then
            local vmess_user="${users//\"flow\":\"xtls-rprx-vision\"\,/}"
            xray_agent_append_client_to_inbound "${configPath}05_VMess_WS_inbounds.json" "${vmess_user}"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 7; then
            local reality_user="${users//\,\"alterId\":0/}"
            xray_agent_append_client_to_inbound "${configPath}${RealityfrontingType}.json" "${reality_user}"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 8; then
            local xhttp_user
            if declare -F xray_agent_xhttp_vless_client_json >/dev/null 2>&1; then
                xhttp_user="$(xray_agent_xhttp_vless_client_json "${uuid}")"
            else
                xhttp_user="$(jq -nc --arg id "${uuid}" '{id:$id}')"
            fi
            xray_agent_append_client_to_inbound "${configPath}08_VLESS_XHTTP_inbounds.json" "${xhttp_user}"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 9; then
            local hysteria2_user
            hysteria2_user="$(jq -nc --arg auth "${uuid}" '{auth:$auth,level:0,email:$auth}')"
            xray_agent_append_client_to_inbound "${configPath}09_Hysteria2_inbounds.json" "${hysteria2_user}"
        fi
    done
    reloadCore
}

xray_agent_remove_client_from_inbound() {
    local target_file="$1"
    local user_id="$2"
    xray_agent_json_update_file "${target_file}" '(.inbounds[0].settings.clients|=. - map(select((.id? == $uid) or (.auth? == $uid))))' --arg uid "${user_id}"
}

removeUser() {
    if [[ "${coreInstallType}" == "3" ]]; then
        userIds=$(jq -r -c .inbounds[0].settings.clients[].id "${configPath}${frontingType}.json" "${configPath}${RealityfrontingType}.json" | sort | uniq)
    elif [[ "${coreInstallType}" == "2" ]]; then
        userIds=$(jq -r -c .inbounds[0].settings.clients[].id "${configPath}${RealityfrontingType}.json" | sort | uniq)
    else
        userIds=$(jq -r -c .inbounds[0].settings.clients[].id "${configPath}${frontingType}.json" | sort | uniq)
    fi
    if [[ -f "${configPath}09_Hysteria2_inbounds.json" ]]; then
        userIds=$({ printf '%s\n' "${userIds}"; jq -r -c '.inbounds[0].settings.clients[]?.auth' "${configPath}09_Hysteria2_inbounds.json" | tr -d '\r'; } | sed '/^$/d' | sort | uniq)
    fi
    if [[ -z "${userIds}" ]]; then
        echoContent yellow " ---> 当前没有可删除的用户"
        return 0
    fi
    echo "${userIds}" | awk '{print NR""":"$0}'
    read -r -p "请选择要删除的用户编号[仅支持单个删除]:" delUserIndex
    mapfile -t userIdsArray <<< "${userIds}"
    if ! [[ "${delUserIndex}" =~ ^[0-9]+$ ]] || [[ "${delUserIndex}" -lt 1 || "${delUserIndex}" -gt "${#userIdsArray[@]}" ]]; then
        echoContent red " ---> 选择错误"
        return 0
    fi
    userIdToDelete=${userIdsArray[$((delUserIndex-1))]}
    if [[ -n "${userIdToDelete}" ]]; then
        xray_agent_account_removal_impact "${userIdToDelete}"
        if ! xray_agent_confirm_danger "确认删除该用户？"; then
            echoContent yellow " ---> 已取消"
            return 0
        fi
        if echo "${currentInstallProtocolType}" | grep -q 0; then
            xray_agent_remove_client_from_inbound "${configPath}${frontingType}.json" "${userIdToDelete}"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 1; then
            xray_agent_remove_client_from_inbound "${configPath}03_VLESS_WS_inbounds.json" "${userIdToDelete}"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 2; then
            xray_agent_remove_client_from_inbound "${configPath}05_VMess_WS_inbounds.json" "${userIdToDelete}"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 7; then
            xray_agent_remove_client_from_inbound "${configPath}${RealityfrontingType}.json" "${userIdToDelete}"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 8; then
            xray_agent_remove_client_from_inbound "${configPath}08_VLESS_XHTTP_inbounds.json" "${userIdToDelete}"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 9; then
            xray_agent_remove_client_from_inbound "${configPath}09_Hysteria2_inbounds.json" "${userIdToDelete}"
        fi
        reloadCore
    fi
}

manageUser() {
    manageAccount "$@"
}

xray_agent_account_count_for_file() {
    local target_file="$1"
    [[ -f "${target_file}" ]] || {
        printf '未安装\n'
        return 0
    }
    jq -r '[.inbounds[0].settings.clients[]?] | length' "${target_file}" 2>/dev/null | tr -d '\r'
}

xray_agent_account_protocol_matrix() {
    echoContent skyBlue "-------------------------账号矩阵-----------------------------"
    echoContent yellow "VLESS TCP TLS: $(xray_agent_account_count_for_file "${configPath}${frontingType:-02_VLESS_TCP_inbounds}.json")"
    echoContent yellow "VLESS WS TLS: $(xray_agent_account_count_for_file "${configPath}03_VLESS_WS_inbounds.json")"
    echoContent yellow "VMess WS TLS: $(xray_agent_account_count_for_file "${configPath}05_VMess_WS_inbounds.json")"
    echoContent yellow "VLESS TCP Reality: $(xray_agent_account_count_for_file "${configPath}${RealityfrontingType:-07_VLESS_Reality_TCP_inbounds}.json")"
    echoContent yellow "VLESS XHTTP: $(xray_agent_account_count_for_file "${configPath}08_VLESS_XHTTP_inbounds.json")"
    echoContent yellow "Hysteria2: $(xray_agent_account_count_for_file "${configPath}09_Hysteria2_inbounds.json")"
}

xray_agent_account_user_exists_in_file() {
    local target_file="$1"
    local user_id="$2"
    [[ -f "${target_file}" ]] || return 1
    jq -e --arg uid "${user_id}" 'any(.inbounds[0].settings.clients[]?; (.id? == $uid) or (.auth? == $uid))' "${target_file}" >/dev/null 2>&1
}

xray_agent_account_removal_impact() {
    local user_id="$1"
    local affected=()
    xray_agent_account_user_exists_in_file "${configPath}${frontingType}.json" "${user_id}" && affected+=("VLESS TCP TLS")
    xray_agent_account_user_exists_in_file "${configPath}03_VLESS_WS_inbounds.json" "${user_id}" && affected+=("VLESS WS TLS")
    xray_agent_account_user_exists_in_file "${configPath}05_VMess_WS_inbounds.json" "${user_id}" && affected+=("VMess WS TLS")
    xray_agent_account_user_exists_in_file "${configPath}${RealityfrontingType}.json" "${user_id}" && affected+=("VLESS TCP Reality")
    xray_agent_account_user_exists_in_file "${configPath}08_VLESS_XHTTP_inbounds.json" "${user_id}" && affected+=("VLESS XHTTP")
    xray_agent_account_user_exists_in_file "${configPath}09_Hysteria2_inbounds.json" "${user_id}" && affected+=("Hysteria2")
    echoContent yellow "将删除用户: ${user_id}"
    if [[ "${#affected[@]}" -gt 0 ]]; then
        echoContent yellow "影响协议: $(xray_agent_join_by ', ' "${affected[@]}")"
    else
        echoContent yellow "影响协议: 未检测到"
    fi
}

showAccounts() {
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    local show=
    xray_agent_blank
    echoContent skyBlue "进度 $1/${totalProgress} : 账号"
    if echo "${currentInstallProtocolType}" | grep -q 0; then
        show=1
        echoContent skyBlue "===================== VLESS TCP TLS ======================"
        jq .inbounds[0].settings.clients "${configPath}${frontingType}.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            xray_agent_blank
            echoContent skyBlue " ---> 账号:${uuid}"
            defaultBase64Code vlesstcp "${uuid}"
        done
    fi
    if echo "${currentInstallProtocolType}" | grep -q 1; then
        show=1
        echoContent skyBlue "================================ VLESS WS TLS CDN ================================"
        jq .inbounds[0].settings.clients "${configPath}03_VLESS_WS_inbounds.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            xray_agent_blank
            echoContent skyBlue " ---> 账号:${uuid}"
            defaultBase64Code vlessws "${uuid}"
        done
    fi
    if echo "${currentInstallProtocolType}" | grep -q 2; then
        show=1
        echoContent skyBlue "================================ VMess WS TLS CDN ================================"
        jq .inbounds[0].settings.clients "${configPath}05_VMess_WS_inbounds.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            xray_agent_blank
            echoContent skyBlue " ---> 账号:${uuid}"
            defaultBase64Code vmessws "${uuid}"
        done
    fi
    if echo "${currentInstallProtocolType}" | grep -q 7; then
        show=1
        echoContent skyBlue "=============================== VLESS TCP Reality ==============================="
        jq .inbounds[0].settings.clients "${configPath}${RealityfrontingType}.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            xray_agent_blank
            echoContent skyBlue " ---> 账号:${uuid}"
            defaultBase64Code vlesstcpreality "${uuid}"
        done
    fi
    if echo "${currentInstallProtocolType}" | grep -q 8; then
        show=1
        echoContent skyBlue "=============================== VLESS XHTTP ==============================="
        jq .inbounds[0].settings.clients "${configPath}08_VLESS_XHTTP_inbounds.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            xray_agent_blank
            echoContent skyBlue " ---> 账号:${uuid}"
            defaultBase64Code vlessxhttp "${uuid}"
        done
    fi
    if echo "${currentInstallProtocolType}" | grep -q 9; then
        show=1
        echoContent skyBlue "=============================== Hysteria2 ==============================="
        jq .inbounds[0].settings.clients "${configPath}09_Hysteria2_inbounds.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .auth | tr -d '\r')
            xray_agent_blank
            echoContent skyBlue " ---> 账号:${uuid}"
            defaultBase64Code hysteria2 "${uuid}"
        done
    fi
    if [[ -z "${show}" ]]; then
        echoContent red " ---> 未安装"
    fi
}

manageAccount() {
    if [[ -z "${coreInstallType}" ]]; then
        echoContent red " ---> 未安装，请使用脚本安装"
        menu
        exit 0
    fi
    xray_agent_tool_status_header "账号管理"
    xray_agent_account_protocol_matrix
    xray_agent_blank
    echoContent red "=============================================================="
    echoContent yellow "1.查看账号"
    echoContent yellow "2.添加用户"
    echoContent yellow "3.删除用户"
    echoContent red "=============================================================="
    read -r -p "请输入:" manageAccountStatus
    case "${manageAccountStatus}" in
        1)
            showAccounts 1
            ;;
        2)
            echoContent yellow "添加用户会同步写入所有已安装协议，包括 Hysteria2 auth。"
            if xray_agent_confirm_action "确认继续？" "y"; then
                addUser
            fi
            ;;
        3)
            removeUser
            ;;
    esac
}

xray_agent_render_share_template_text() {
    local template_name="$1"
    local template_path="${XRAY_AGENT_PROJECT_ROOT}/templates/share/${template_name}"
    xray_agent_render_template_stdout "${template_path}"
}

xray_agent_reality_share_params() {
    local public_key sid spider_x pqv
    public_key="$(xray_agent_reality_public_key_value || true)"
    [[ -n "${public_key}" ]] || return 1
    spider_x="${RealitySpiderX:-/}"
    printf '&pbk=%s' "$(xray_agent_urlencode "${public_key}")"
    pqv="$(xray_agent_reality_mldsa65_verify_value || true)"
    if [[ -n "${pqv}" ]]; then
        printf '&pqv=%s' "$(xray_agent_urlencode "${pqv}")"
    fi
    if [[ -n "${RealityShortID}" ]]; then
        sid="${RealityShortID//\"/}"
        sid="${sid%%,*}"
        printf '&sid=%s' "$(xray_agent_urlencode "${sid}")"
    fi
    printf '&spx=%s' "$(xray_agent_urlencode "${spider_x}")"
}

xray_agent_share_encryption_for_profile() {
    local profile_name="$1"
    case "${profile_name}" in
        vless_ws_tls | vless_xhttp)
            if [[ -z "${VLESSEncryption:-}" && -n "${VLESSDecryption:-}" && "${VLESSDecryption}" != "none" ]]; then
                VLESSEncryption="$(xray_agent_vless_encryption_from_decryption "${VLESSDecryption}" || true)"
            fi
            printf '%s\n' "${VLESSEncryption:-none}"
            ;;
        *)
            printf 'none\n'
            ;;
    esac
}

xray_agent_tls_share_params() {
    local sni="$1"
    local ech_config_list cert_hash params=""
    ech_config_list="$(xray_agent_tls_ech_config_list_value || true)"
    if [[ -n "${ech_config_list}" ]]; then
        params="${params}&ech=$(xray_agent_urlencode "${ech_config_list}")"
    fi
    cert_hash="$(xray_agent_tls_leaf_sha256 "${TLSDomain:-${domain:-}}" || true)"
    if [[ -n "${cert_hash}" ]]; then
        params="${params}&pcs=$(xray_agent_urlencode "${cert_hash}")"
        params="${params}&vcn=$(xray_agent_urlencode "${sni}")"
    fi
    printf '%s\n' "${params}"
}

xray_agent_share_finalmask_param() {
    local profile_name="$1"
    local finalmask_value
    case "${profile_name}" in
        vless_xhttp)
            if declare -F xray_agent_xhttp_finalmask_share_value >/dev/null 2>&1 &&
                xray_agent_xray_supports_finalmask; then
                finalmask_value="$(xray_agent_xhttp_finalmask_share_value)"
                if [[ -n "${finalmask_value}" ]]; then
                    printf '&fm=%s\n' "$(xray_agent_urlencode "${finalmask_value}")"
                fi
            fi
            ;;
    esac
    return 0
}

xray_agent_vless_profile_share_uri() {
    local profile_name="$1"
    local id="$2"
    local variant="${3:-}"
    xray_agent_load_protocol_profile "${profile_name}" || return 1

    local address port sni share_path security mode reality_params
    local encryption tls_params finalmask_params flow_value
    address="$(xray_agent_protocol_address_value "${variant}")" || return 1
    [[ -n "${address}" ]] || return 1
    port="$(xray_agent_protocol_port_value "${variant}")"
    sni="$(xray_agent_protocol_sni_value "${variant}")"
    share_path="$(xray_agent_protocol_path_value)"
    security="$(xray_agent_protocol_security_value "${variant}")"
    mode="${XHTTPMode:-${XRAY_AGENT_PROTOCOL_MODE:-auto}}"
    [[ -n "${mode}" ]] || mode="auto"
    encryption="$(xray_agent_share_encryption_for_profile "${profile_name}")"

    local XRAY_SHARE_UUID
    local XRAY_SHARE_ADDRESS
    local XRAY_SHARE_PORT
    local XRAY_SHARE_SNI
    local XRAY_SHARE_ALPN
    local XRAY_SHARE_ALPN_PARAM=""
    local XRAY_SHARE_FP
    local XRAY_SHARE_HOST
    local XRAY_SHARE_PATH
    local XRAY_SHARE_MODE
    local XRAY_SHARE_SECURITY
    local XRAY_SHARE_REALITY_PARAMS=""
    local XRAY_SHARE_TLS_PARAMS=""
    local XRAY_SHARE_ENCRYPTION
    local XRAY_SHARE_FLOW_PARAM=""
    local XRAY_SHARE_FM_PARAM=""
    local XRAY_SHARE_NAME

    XRAY_SHARE_UUID="$(xray_agent_urlencode "${id}")"
    XRAY_SHARE_ADDRESS="$(xray_agent_uri_authority_host "${address}")"
    XRAY_SHARE_PORT="${port}"
    XRAY_SHARE_SNI="$(xray_agent_urlencode "${sni}")"
    XRAY_SHARE_ALPN="$(xray_agent_urlencode "${XRAY_AGENT_PROTOCOL_ALPN}")"
    XRAY_SHARE_FP="$(xray_agent_urlencode "${XRAY_AGENT_PROTOCOL_FP:-chrome}")"
    XRAY_SHARE_HOST="$(xray_agent_urlencode "${sni}")"
    XRAY_SHARE_PATH="$(xray_agent_urlencode "${share_path}")"
    XRAY_SHARE_MODE="$(xray_agent_urlencode "${mode}")"
    XRAY_SHARE_SECURITY="$(xray_agent_urlencode "${security}")"
    XRAY_SHARE_ENCRYPTION="$(xray_agent_urlencode "${encryption}")"
    XRAY_SHARE_NAME="$(xray_agent_urlencode "${id}")"

    if [[ "${profile_name}" == "vless_xhttp" ]] && declare -F xray_agent_xhttp_vision_flow_for_share >/dev/null 2>&1; then
        flow_value="$(xray_agent_xhttp_vision_flow_for_share)"
        if [[ -n "${flow_value}" ]]; then
            XRAY_SHARE_FLOW_PARAM="&flow=$(xray_agent_urlencode "${flow_value}")"
        fi
    fi

    if [[ "${security}" == "tls" && "${XRAY_AGENT_PROTOCOL_TRANSPORT}" == "xhttp" && -n "${XRAY_AGENT_PROTOCOL_ALPN}" ]]; then
        XRAY_SHARE_ALPN_PARAM="&alpn=${XRAY_SHARE_ALPN}"
    fi
    if [[ "${security}" == "reality" ]]; then
        reality_params="$(xray_agent_reality_share_params)" || return 1
        XRAY_SHARE_REALITY_PARAMS="${reality_params}"
    elif [[ "${security}" == "tls" ]]; then
        tls_params="$(xray_agent_tls_share_params "${sni}")"
        XRAY_SHARE_TLS_PARAMS="${tls_params}"
    fi
    finalmask_params="$(xray_agent_share_finalmask_param "${profile_name}")"
    if [[ -n "${finalmask_params}" ]]; then
        XRAY_SHARE_FM_PARAM="${finalmask_params}"
    fi

    xray_agent_render_share_template_text "${XRAY_AGENT_PROTOCOL_SHARE_TEMPLATE}"
}

xray_agent_print_vless_profile_share() {
    local profile_name="$1"
    local id="$2"
    local variant="${3:-}"
    local rendered
    if ! rendered="$(xray_agent_vless_profile_share_uri "${profile_name}" "${id}" "${variant}")"; then
        echoContent red " ---> 分享链接生成失败，请检查 Reality key 或协议配置"
        return 1
    fi
    echoContent green "${rendered}"
    xray_agent_blank
}

xray_agent_build_vless_uri() {
    local profile_name="$1"
    local id="$2"
    local variant="${3:-}"
    xray_agent_vless_profile_share_uri "${profile_name}" "${id}" "${variant}"
}

defaultBase64Code() {
    local type="$1"
    local id="$2"
    case "${type}" in
        vlesstcp)
            echoContent yellow " ---> 通用格式 (VLESS+TCP+TLS)"
            xray_agent_print_vless_profile_share "vless_tcp_tls" "${id}"
            echoContent yellow " ---> 格式化明文 (VLESS+TCP+TLS)"
            echoContent green "协议类型: VLESS，地址: ${domain}，端口: $(xray_agent_share_port_for_profile vless_tcp_tls)，用户ID: ${id}，安全: tls，传输方式: tcp，flow: xtls-rprx-vision，账户名: ${id}"
            ;;
        vlessws)
            echoContent yellow " ---> 通用格式 (VLESS+WS+TLS)"
            xray_agent_print_vless_profile_share "vless_ws_tls" "${id}"
            echoContent yellow " ---> 格式化明文 (VLESS+WS+TLS)"
            echoContent green "协议类型: VLESS，地址: ${domain}，伪装域名/SNI: ${domain}，端口: $(xray_agent_share_port_for_profile vless_ws_tls)，用户ID: ${id}，安全: tls，传输方式: ws，路径: /${path}ws，encryption: $(xray_agent_share_encryption_for_profile vless_ws_tls)，账户名: ${id}"
            ;;
        vmessws)
            xray_agent_print_vmess_share "${id}"
            ;;
        vlesstcpreality)
            echoContent yellow " ---> 通用格式 (VLESS+TCP+Reality)"
            if xray_agent_print_vless_profile_share "vless_reality_tcp" "${id}"; then
                local reality_address
                reality_address="$(xray_agent_select_public_ip_for_reality)" || return 1
                echoContent yellow " ---> 格式化明文 (VLESS+TCP+Reality)"
                echoContent green "协议类型: VLESS Reality，地址: ${reality_address}，publicKey: ${RealityPublicKey}，pqv: ${RealityMldsa65Verify:-无}，serverNames: ${RealityServerNames}，端口: $(xray_agent_share_port_for_profile vless_reality_tcp)，用户ID: ${id}，传输方式: tcp，账户名: ${id}"
            fi
            ;;
        vlessxhttp)
            if [[ "${coreInstallType}" == "1" || "${coreInstallType}" == "3" ]]; then
                echoContent yellow " ---> 通用格式 (VLESS+XHTTP+TLS)"
                xray_agent_print_vless_profile_share "vless_xhttp" "${id}" "tls"
                echoContent yellow " ---> 格式化明文 (VLESS+XHTTP+TLS)"
                echoContent green "协议类型: VLESS，地址: ${domain}，端口: $(xray_agent_share_port_for_profile vless_xhttp tls)，用户ID: ${id}，安全: tls，传输方式: XHTTP，encryption: $(xray_agent_share_encryption_for_profile vless_xhttp)，账户名: ${id}"
            fi
            if [[ "${coreInstallType}" == "2" || "${coreInstallType}" == "3" ]]; then
                echoContent yellow " ---> 通用格式 (VLESS+XHTTP+Reality)"
                if xray_agent_print_vless_profile_share "vless_xhttp" "${id}" "reality"; then
                    local reality_address
                    reality_address="$(xray_agent_select_public_ip_for_reality)" || return 1
                    echoContent yellow " ---> 格式化明文 (VLESS+XHTTP+Reality)"
                    echoContent green "协议类型: VLESS XHTTP，地址: ${reality_address}，publicKey: ${RealityPublicKey}，serverNames: ${RealityServerNames}，端口: $(xray_agent_share_port_for_profile vless_xhttp reality)，用户ID: ${id}，传输方式: XHTTP，client-fingerprint: chrome，encryption: $(xray_agent_share_encryption_for_profile vless_xhttp)，账户名: ${id}"
                fi
            fi
            ;;
        hysteria2)
            echoContent yellow " ---> 通用格式 (Hysteria2)"
            echoContent green "$(xray_agent_build_hysteria2_uri "${id}")"
            echoContent yellow " ---> 格式化明文 (Hysteria2)"
            echoContent green "协议类型: Hysteria2，地址: ${domain}，端口: $(xray_agent_hysteria2_display_ports)，SNI: ${domain}，auth: ${id}，账户名: ${id}"
            ;;
    esac
}

xray_agent_share_port_for_profile() {
    local profile_name="$1"
    local variant="${2:-}"
    xray_agent_load_protocol_profile "${profile_name}" || return 1
    xray_agent_protocol_port_value "${variant}"
}

xray_agent_print_vmess_share() {
    local id="$1"
    xray_agent_load_protocol_profile "vmess_ws_tls"
    local XRAY_SHARE_UUID="${id}"
    local XRAY_SHARE_ADDRESS="${domain}"
    local XRAY_SHARE_PORT="$(xray_agent_protocol_port_value)"
    local XRAY_SHARE_SNI="${domain}"
    local XRAY_SHARE_PATH="${path}vws"
    local XRAY_SHARE_NAME="${id}"
    local encoded_json rendered_json
    rendered_json="$(xray_agent_render_share_template_text "${XRAY_AGENT_PROTOCOL_SHARE_TEMPLATE}")"
    encoded_json="$(printf '%s' "${rendered_json}" | base64 -w 0)"
    echoContent yellow " ---> 通用json (VMess+WS+TLS)"
    echoContent green "    ${rendered_json}"
    echoContent green "vmess://${encoded_json}"
    echoContent yellow " ---> URI格式 (VMess+WS+TLS)"
    echoContent green "$(xray_agent_build_vmess_ws_uri "${id}")"
    xray_agent_blank
}

xray_agent_build_vmess_ws_uri() {
    local id="$1"
    xray_agent_load_protocol_profile "vmess_ws_tls" || return 1
    local address port sni share_path query
    address="$(xray_agent_uri_authority_host "$(xray_agent_protocol_address_value "tls")")"
    port="$(xray_agent_protocol_port_value "tls")"
    sni="$(xray_agent_protocol_sni_value "tls")"
    share_path="$(xray_agent_protocol_path_value)"
    query="security=tls"
    query="${query}&sni=$(xray_agent_urlencode "${sni}")"
    query="${query}&alpn=$(xray_agent_urlencode "${XRAY_AGENT_PROTOCOL_ALPN}")"
    query="${query}&fp=$(xray_agent_urlencode "${XRAY_AGENT_PROTOCOL_FP:-chrome}")"
    query="${query}&type=ws"
    query="${query}&host=$(xray_agent_urlencode "${sni}")"
    query="${query}&path=$(xray_agent_urlencode "${share_path}")"
    printf 'vmess://%s@%s:%s?%s#%s\n' \
        "$(xray_agent_urlencode "${id}")" \
        "${address}" \
        "${port}" \
        "${query}" \
        "$(xray_agent_urlencode "${id}")"
}

xray_agent_build_hysteria2_uri() {
    local auth="$1"
    xray_agent_load_protocol_profile "hysteria2" || return 1
    local address port sni XRAY_SHARE_AUTH XRAY_SHARE_ADDRESS XRAY_SHARE_PORT XRAY_SHARE_SNI XRAY_SHARE_MPORT_PARAM XRAY_SHARE_NAME
    address="$(xray_agent_protocol_address_value "tls")"
    port="$(xray_agent_protocol_port_value "tls")"
    sni="$(xray_agent_protocol_sni_value "tls")"
    XRAY_SHARE_AUTH="$(xray_agent_urlencode "${auth}")"
    XRAY_SHARE_ADDRESS="$(xray_agent_uri_authority_host "${address}")"
    XRAY_SHARE_PORT="${port}"
    XRAY_SHARE_SNI="$(xray_agent_urlencode "${sni}")"
    XRAY_SHARE_MPORT_PARAM="$(xray_agent_hysteria2_share_mport_param)"
    XRAY_SHARE_NAME="$(xray_agent_urlencode "${auth}")"
    xray_agent_render_share_template_text "${XRAY_AGENT_PROTOCOL_SHARE_TEMPLATE}"
}
