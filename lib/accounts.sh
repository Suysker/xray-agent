#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

customUUID() {
    read -r -p "请输入合法的UUID，[回车]随机UUID:" currentCustomUUID
    if [[ -z "${currentCustomUUID}" ]]; then
        currentCustomUUID=$(${ctlPath} uuid)
    fi
}

xray_agent_append_client_to_inbound() {
    local target_file="$1"
    local client_json="$2"
    jq -r ".inbounds[0].settings.clients += [${client_json}]" "${target_file}" | jq . >"${target_file}"
}

addUser() {
    read -r -p "请输入要添加的用户数量:" userNum
    if [[ -z ${userNum} || ${userNum} -le 0 ]]; then
        exit 0
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
            local xhttp_user="${users//\"flow\":\"xtls-rprx-vision\",/}"
            xhttp_user="${xhttp_user//\,\"alterId\":0/}"
            xray_agent_append_client_to_inbound "${configPath}08_VLESS_XHTTP_inbounds.json" "${xhttp_user}"
        fi
    done
    reloadCore
}

xray_agent_remove_client_from_inbound() {
    local target_file="$1"
    local user_id="$2"
    jq --arg uid "${user_id}" -r '(.inbounds[0].settings.clients|=. - map(select(.id == $uid)))' "${target_file}" | jq . >"${target_file}"
}

removeUser() {
    if [[ "${coreInstallType}" == "3" ]]; then
        userIds=$(jq -r -c .inbounds[0].settings.clients[].id "${configPath}${frontingType}.json" "${configPath}${RealityfrontingType}.json" | sort | uniq)
    elif [[ "${coreInstallType}" == "2" ]]; then
        userIds=$(jq -r -c .inbounds[0].settings.clients[].id "${configPath}${RealityfrontingType}.json" | sort | uniq)
    else
        userIds=$(jq -r -c .inbounds[0].settings.clients[].id "${configPath}${frontingType}.json" | sort | uniq)
    fi
    echo "${userIds}" | awk '{print NR""":"$0}'
    read -r -p "请选择要删除的用户编号[仅支持单个删除]:" delUserIndex
    mapfile -t userIdsArray <<< "${userIds}"
    userIdToDelete=${userIdsArray[$((delUserIndex-1))]}
    if [[ -n "${userIdToDelete}" ]]; then
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
        reloadCore
    fi
}

manageUser() {
    manageAccount "$@"
}

showAccounts() {
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    xray_agent_blank
    echoContent skyBlue "进度 $1/${totalProgress} : 账号"
    if echo "${currentInstallProtocolType}" | grep -q 0; then
        jq .inbounds[0].settings.clients "${configPath}${frontingType}.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            xray_agent_blank
            echoContent skyBlue " ---> 账号:${uuid}"
            defaultBase64Code vlesstcp "${uuid}"
        done
    fi
    if echo "${currentInstallProtocolType}" | grep -q 1; then
        jq .inbounds[0].settings.clients "${configPath}03_VLESS_WS_inbounds.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            xray_agent_blank
            echoContent skyBlue " ---> 账号:${uuid}"
            defaultBase64Code vlessws "${uuid}"
        done
    fi
    if echo "${currentInstallProtocolType}" | grep -q 2; then
        jq .inbounds[0].settings.clients "${configPath}05_VMess_WS_inbounds.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            xray_agent_blank
            echoContent skyBlue " ---> 账号:${uuid}"
            defaultBase64Code vmessws "${uuid}"
        done
    fi
    if echo "${currentInstallProtocolType}" | grep -q 7; then
        jq .inbounds[0].settings.clients "${configPath}${RealityfrontingType}.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            xray_agent_blank
            echoContent skyBlue " ---> 账号:${uuid}"
            defaultBase64Code vlesstcpreality "${uuid}"
        done
    fi
    if echo "${currentInstallProtocolType}" | grep -q 8; then
        jq .inbounds[0].settings.clients "${configPath}08_VLESS_XHTTP_inbounds.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            xray_agent_blank
            echoContent skyBlue " ---> 账号:${uuid}"
            defaultBase64Code vlessxhttp "${uuid}"
        done
    fi
}

manageAccount() {
    xray_agent_blank
    echoContent skyBlue "功能 1/${totalProgress} : 账号管理"
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
            addUser
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

xray_agent_print_vless_profile_share() {
    local profile_name="$1"
    local id="$2"
    local variant="${3:-}"
    local rendered
    xray_agent_load_protocol_profile "${profile_name}" || return 1
    local address port sni share_path security
    address="$(xray_agent_protocol_address_value "${variant}")"
    port="$(xray_agent_protocol_port_value "${variant}")"
    sni="$(xray_agent_protocol_sni_value "${variant}")"
    share_path="$(xray_agent_protocol_path_value)"
    security="$(xray_agent_protocol_security_value "${variant}")"
    local XRAY_SHARE_UUID="${id}"
    local XRAY_SHARE_ADDRESS="${address}"
    local XRAY_SHARE_PORT="${port}"
    local XRAY_SHARE_SNI="${sni}"
    local XRAY_SHARE_PATH="${share_path#/}"
    local XRAY_SHARE_SECURITY="${security}"
    local XRAY_SHARE_PUBLIC_KEY="${RealityPublicKey}"
    local XRAY_SHARE_NAME="${id}"
    rendered="$(xray_agent_render_share_template_text "${XRAY_AGENT_PROTOCOL_SHARE_TEMPLATE}")"
    echoContent green "${rendered}"
    xray_agent_blank
}

xray_agent_build_vless_uri() {
    local profile_name="$1"
    local id="$2"
    local variant="${3:-}"
    xray_agent_load_protocol_profile "${profile_name}" || return 1

    local address port sni path_value security query
    address="$(xray_agent_protocol_address_value "${variant}")"
    port="$(xray_agent_protocol_port_value "${variant}")"
    sni="$(xray_agent_protocol_sni_value "${variant}")"
    path_value="$(xray_agent_protocol_path_value)"
    security="$(xray_agent_protocol_security_value "${variant}")"

    query="encryption=none"
    if [[ -n "${XRAY_AGENT_PROTOCOL_FLOW}" ]]; then
        query="${query}&flow=${XRAY_AGENT_PROTOCOL_FLOW}"
    fi
    query="${query}&security=${security}"

    if [[ "${security}" == "tls" ]]; then
        query="${query}&sni=${sni}&alpn=$(xray_agent_urlencode "${XRAY_AGENT_PROTOCOL_ALPN}")&fp=${XRAY_AGENT_PROTOCOL_FP}"
    elif [[ "${security}" == "reality" ]]; then
        query="${query}&sni=${sni}&fp=${XRAY_AGENT_PROTOCOL_FP}&pbk=${RealityPublicKey}"
        if [[ -n "${RealityShortID}" ]]; then
            query="${query}&sid=${RealityShortID}"
        fi
    fi

    case "${XRAY_AGENT_PROTOCOL_TRANSPORT}" in
        tcp)
            query="${query}&type=tcp&headerType=none"
            ;;
        ws)
            query="${query}&type=ws&host=${sni}&path=$(xray_agent_urlencode "${path_value}")"
            ;;
        xhttp)
            query="${query}&type=xhttp"
            if [[ -n "${path_value}" ]]; then
                query="${query}&path=$(xray_agent_urlencode "${path_value}")"
            fi
            if [[ -n "${XRAY_AGENT_PROTOCOL_MODE}" ]]; then
                query="${query}&mode=${XRAY_AGENT_PROTOCOL_MODE}"
            fi
            ;;
    esac

    echo "vless://${id}@${address}:${port}?${query}#${id}"
}

defaultBase64Code() {
    local type="$1"
    local id="$2"
    case "${type}" in
        vlesstcp)
            xray_agent_print_vless_profile_share "vless_tcp_tls" "${id}"
            ;;
        vlessws)
            xray_agent_print_vless_profile_share "vless_ws_tls" "${id}"
            ;;
        vmessws)
            xray_agent_print_vmess_share "${id}"
            ;;
        vlesstcpreality)
            xray_agent_print_vless_profile_share "vless_reality_tcp" "${id}"
            ;;
        vlessxhttp)
            if [[ "${coreInstallType}" == "1" || "${coreInstallType}" == "3" ]]; then
                xray_agent_print_vless_profile_share "vless_xhttp" "${id}" "tls"
            fi
            if [[ "${coreInstallType}" == "2" || "${coreInstallType}" == "3" ]]; then
                xray_agent_print_vless_profile_share "vless_xhttp" "${id}" "reality"
            fi
            ;;
    esac
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
    local encoded_json
    encoded_json="$(xray_agent_render_share_template_text "${XRAY_AGENT_PROTOCOL_SHARE_TEMPLATE}" | base64 -w 0)"
    echoContent green "vmess://${encoded_json}"
    xray_agent_blank
}
