if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

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
