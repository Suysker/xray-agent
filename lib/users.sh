xray_agent_profile_name_from_legacy_type() {
    case "$1" in
        vlesstcp)
            echo "server_tls_vision"
            ;;
        vlesstcpreality)
            echo "server_reality_vision"
            ;;
        vlessxhttp)
            if [[ "${coreInstallType}" == "2" ]]; then
                echo "server_reality_xhttp"
            else
                echo "server_tls_xhttp"
            fi
            ;;
    esac
}

xray_agent_build_clash_meta_vless() {
    local profile_name="$1"
    local id="$2"
    if ! xray_agent_load_profile "${profile_name}"; then
        return 1
    fi
    local address port sni path_value
    address="$(xray_agent_profile_address)"
    port="$(xray_agent_profile_port)"
    sni="$(xray_agent_profile_sni)"
    path_value="$(xray_agent_profile_path)"
    jq -nc \
        --arg name "${id}" \
        --arg server "${address}" \
        --argjson port "${port}" \
        --arg uuid "${id}" \
        --arg network "${XRAY_AGENT_PROFILE_TRANSPORT}" \
        --arg tlsSecurity "${XRAY_AGENT_PROFILE_SECURITY}" \
        --arg sni "${sni}" \
        --arg flow "${XRAY_AGENT_PROFILE_FLOW}" \
        --arg path "${path_value}" \
        --arg pbk "${RealityPublicKey}" \
        --arg sid "${RealityShortID}" \
        '{
          name: $name,
          type: "vless",
          server: $server,
          port: $port,
          uuid: $uuid,
          tls: ($tlsSecurity != "none"),
          servername: $sni,
          network: $network,
          udp: true
        }
        + (if $flow != "" then {flow: $flow} else {} end)
        + (if $network == "xhttp" then {xhttp_opts: {path: $path}} else {} end)
        + (if $tlsSecurity == "reality" then {"reality-opts": {"public-key": $pbk, "short-id": $sid}} else {} end)'
}

xray_agent_build_sing_box_vless() {
    local profile_name="$1"
    local id="$2"
    if ! xray_agent_load_profile "${profile_name}"; then
        return 1
    fi
    local address port sni path_value
    address="$(xray_agent_profile_address)"
    port="$(xray_agent_profile_port)"
    sni="$(xray_agent_profile_sni)"
    path_value="$(xray_agent_profile_path)"
    jq -nc \
        --arg type "vless" \
        --arg tag "${id}" \
        --arg server "${address}" \
        --argjson server_port "${port}" \
        --arg uuid "${id}" \
        --arg flow "${XRAY_AGENT_PROFILE_FLOW}" \
        --arg transport "${XRAY_AGENT_PROFILE_TRANSPORT}" \
        --arg security "${XRAY_AGENT_PROFILE_SECURITY}" \
        --arg server_name "${sni}" \
        --arg path "${path_value}" \
        --arg public_key "${RealityPublicKey}" \
        --arg short_id "${RealityShortID}" \
        '{
          type: $type,
          tag: $tag,
          server: $server,
          server_port: $server_port,
          uuid: $uuid
        }
        + (if $flow != "" then {flow: $flow} else {} end)
        + (if $security == "tls" then {tls: {enabled: true, server_name: $server_name}} else {} end)
        + (if $security == "reality" then {tls: {enabled: true, server_name: $server_name, reality: {enabled: true, public_key: $public_key, short_id: $short_id}}} else {} end)
        + (if $transport == "xhttp" then {transport: {type: "xhttp", path: $path}} else {transport: {type: "tcp"}} end)'
}

xray_agent_print_share_bundle() {
    local profile_name="$1"
    local id="$2"
    local uri clash sing_box
    uri="$(xray_agent_build_vless_uri "${profile_name}" "${id}")"
    clash="$(xray_agent_build_clash_meta_vless "${profile_name}" "${id}")"
    sing_box="$(xray_agent_build_sing_box_vless "${profile_name}" "${id}")"
    echoContent yellow " ---> VLESS URL"
    echoContent green "${uri}\n"
    echoContent yellow " ---> Clash Meta"
    echoContent green "${clash}\n"
    echoContent yellow " ---> sing-box"
    echoContent green "${sing_box}\n"
}

defaultBase64Code() {
    local type="$1"
    local id="$2"
    case "${type}" in
        vlesstcp)
            xray_agent_print_share_bundle "server_tls_vision" "${id}"
            ;;
        vlesstcpreality)
            xray_agent_print_share_bundle "server_reality_vision" "${id}"
            ;;
        vlessxhttp)
            if [[ "${coreInstallType}" == "1" || "${coreInstallType}" == "3" ]]; then
                xray_agent_print_share_bundle "server_tls_xhttp" "${id}"
            fi
            if [[ "${coreInstallType}" == "2" || "${coreInstallType}" == "3" ]]; then
                xray_agent_print_share_bundle "server_reality_xhttp" "${id}"
            fi
            ;;
        vlessws)
            local ws_port="${Port}"
            if [[ "${reuse443}" == "y" ]]; then
                ws_port=443
            fi
            echoContent green "vless://${id}@${domain}:${ws_port}?encryption=none&security=tls&sni=${domain}&alpn=h2%2Chttp%2F1.1&fp=chrome&type=ws&host=${domain}&path=%2F${path}ws#${id}\n"
            ;;
        vmessws)
            local vmess_port="${Port}"
            if [[ "${reuse443}" == "y" ]]; then
                vmess_port=443
            fi
            qrCodeBase64Default=$(echo -n "{\"port\":${vmess_port},\"tls\":\"tls\",\"id\":\"${id}\",\"aid\":0,\"v\":2,\"host\":\"${domain}\",\"type\":\"none\",\"path\":\"/${path}vws\",\"net\":\"ws\",\"method\":\"none\",\"peer\":\"${domain}\",\"sni\":\"${domain}\",\"alpn\":\"h2,http/1.1\",\"fp\":\"chrome\"}" | base64 -w 0)
            echoContent green "vmess://${qrCodeBase64Default}\n"
            ;;
    esac
}

showAccounts() {
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    echoContent skyBlue "\n进度 $1/${totalProgress} : 账号"
    if echo "${currentInstallProtocolType}" | grep -q 0; then
        jq .inbounds[0].settings.clients "${configPath}${frontingType}.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            echoContent skyBlue "\n ---> 账号:${uuid}"
            defaultBase64Code vlesstcp "${uuid}"
        done
    fi
    if echo "${currentInstallProtocolType}" | grep -q 1; then
        jq .inbounds[0].settings.clients "${configPath}03_VLESS_WS_inbounds.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            echoContent skyBlue "\n ---> 账号:${uuid}"
            defaultBase64Code vlessws "${uuid}"
        done
    fi
    if echo "${currentInstallProtocolType}" | grep -q 2; then
        jq .inbounds[0].settings.clients "${configPath}05_VMess_WS_inbounds.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            echoContent skyBlue "\n ---> 账号:${uuid}"
            defaultBase64Code vmessws "${uuid}"
        done
    fi
    if echo "${currentInstallProtocolType}" | grep -q 7; then
        jq .inbounds[0].settings.clients "${configPath}${RealityfrontingType}.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            echoContent skyBlue "\n ---> 账号:${uuid}"
            defaultBase64Code vlesstcpreality "${uuid}"
        done
    fi
    if echo "${currentInstallProtocolType}" | grep -q 8; then
        jq .inbounds[0].settings.clients "${configPath}08_VLESS_XHTTP_inbounds.json" | jq -c '.[]' | while read -r user; do
            uuid=$(echo "${user}" | jq -r .id)
            echoContent skyBlue "\n ---> 账号:${uuid}"
            defaultBase64Code vlessxhttp "${uuid}"
        done
    fi
    if echo "${currentInstallProtocolType}" | grep -q 9; then
        jq .inbounds[0].settings.users "${configPath}12_HYSTERIA2_inbounds.json" | jq -c '.[]' | while read -r user; do
            password=$(echo "${user}" | jq -r .password)
            echoContent green "协议类型: Hysteria2，地址: ${domain}，端口: ${Port}，密码: ${password}\n"
        done
    fi
}

customUUID() {
    read -r -p "请输入合法的UUID，[回车]随机UUID:" currentCustomUUID
    if [[ -z "${currentCustomUUID}" ]]; then
        currentCustomUUID=$(${ctlPath} uuid)
    fi
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
            vlessUsers="${users//\,\"alterId\":0/}"
            jq -r ".inbounds[0].settings.clients += [${vlessUsers}]" "${configPath}${frontingType}.json" | jq . >"${configPath}${frontingType}.json"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 1; then
            vlessUsers="${users//\,\"alterId\":0/}"
            vlessUsers="${vlessUsers//\"flow\":\"xtls-rprx-vision\"\,/}"
            jq -r ".inbounds[0].settings.clients += [${vlessUsers}]" "${configPath}03_VLESS_WS_inbounds.json" | jq . >"${configPath}03_VLESS_WS_inbounds.json"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 2; then
            vmessUsers="${users//\"flow\":\"xtls-rprx-vision\"\,/}"
            jq -r ".inbounds[0].settings.clients += [${vmessUsers}]" "${configPath}05_VMess_WS_inbounds.json" | jq . >"${configPath}05_VMess_WS_inbounds.json"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 7; then
            vlessUsers="${users//\,\"alterId\":0/}"
            jq -r ".inbounds[0].settings.clients += [${vlessUsers}]" "${configPath}${RealityfrontingType}.json" | jq . >"${configPath}${RealityfrontingType}.json"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 8; then
            vlessUsers="${users//\"flow\":\"xtls-rprx-vision\",/}"
            vlessUsers="${users//\,\"alterId\":0/}"
            jq -r ".inbounds[0].settings.clients += [${vlessUsers}]" "${configPath}08_VLESS_XHTTP_inbounds.json" | jq . >"${configPath}08_VLESS_XHTTP_inbounds.json"
        fi
    done
    reloadCore
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
            jq --arg uid "${userIdToDelete}" -r '(.inbounds[0].settings.clients|=. - map(select(.id == $uid)))' "${configPath}${frontingType}.json" | jq . >"${configPath}${frontingType}.json"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 1; then
            jq --arg uid "${userIdToDelete}" -r '(.inbounds[0].settings.clients|=. - map(select(.id == $uid)))' "${configPath}03_VLESS_WS_inbounds.json" | jq . >"${configPath}03_VLESS_WS_inbounds.json"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 2; then
            jq --arg uid "${userIdToDelete}" -r '(.inbounds[0].settings.clients|=. - map(select(.id == $uid)))' "${configPath}05_VMess_WS_inbounds.json" | jq . >"${configPath}05_VMess_WS_inbounds.json"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 7; then
            jq --arg uid "${userIdToDelete}" -r '(.inbounds[0].settings.clients|=. - map(select(.id == $uid)))' "${configPath}${RealityfrontingType}.json" | jq . >"${configPath}${RealityfrontingType}.json"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 8; then
            jq --arg uid "${userIdToDelete}" -r '(.inbounds[0].settings.clients|=. - map(select(.id == $uid)))' "${configPath}08_VLESS_XHTTP_inbounds.json" | jq . >"${configPath}08_VLESS_XHTTP_inbounds.json"
        fi
        reloadCore
    fi
}

manageAccount() {
    echoContent skyBlue "\n功能 1/${totalProgress} : 账号管理"
    echoContent red "\n=============================================================="
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

manageUser() {
    manageAccount "$@"
}

addCorePort() {
    echoContent yellow "# 只给TLS+VISION添加新端口，永远不会支持Reality(Reality只建议用443)\n"
    echoContent yellow "1.添加端口"
    echoContent yellow "2.删除端口"
    echoContent yellow "3.查看已添加端口"
    read -r -p "请选择:" selectNewPortType
    if [[ "${selectNewPortType}" == "1" ]]; then
        read -r -p "请输入端口号:" newPort
        if [[ -n "${newPort}" ]]; then
            while read -r port; do
                if [[ "${port}" == "${Port}" ]]; then
                    continue
                fi
                rm -rf "$(find ${configPath}* | grep "${port}")"
                fileName="${configPath}02_dokodemodoor_inbounds_${port}.json"
                allowPort "${port}"
                cat <<EOF >"${fileName}"
{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${port},
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1",
        "port": ${Port},
        "network": "raw",
        "followRedirect": false
      },
      "tag": "dokodemo-door-newPort-${port}"
    }
  ]
}
EOF
            done < <(echo "${newPort}" | tr ',' '\n')
            reloadCore
        fi
    elif [[ "${selectNewPortType}" == "2" ]]; then
        find "${configPath}" -name "*dokodemodoor*" | awk -F "[c][o][n][f][/]" '{print ""NR""":"$2}'
        read -r -p "请输入要删除的端口编号:" portIndex
        dokoConfig=$(find "${configPath}" -name "*dokodemodoor*" | awk -F "[c][o][n][f][/]" '{print ""NR""":"$2}' | grep "${portIndex}:")
        if [[ -n "${dokoConfig}" ]]; then
            rm "${configPath}/$(echo "${dokoConfig}" | awk -F "[:]" '{print $2}')"
            reloadCore
        fi
    else
        find "${configPath}" -name "*dokodemodoor*" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}'
    fi
}
