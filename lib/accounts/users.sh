if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
