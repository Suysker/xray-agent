if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

initTLSNginxConfig() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 初始化Nginx申请证书配置"
    if [[ -n "${domain}" ]]; then
        read -r -p "读取到上次安装记录，是否使用上次安装时的域名 ？[y/n]:" historyDomainStatus
        if [[ "${historyDomainStatus}" != "y" ]]; then
            echoContent yellow "请输入要配置的域名 例: www.xray-agent.com --->"
            read -r -p "域名:" domain
        else
            echoContent yellow "\n ---> 域名: ${domain}"
        fi
    else
        echoContent yellow "请输入要配置的域名 例: www.xray-agent.com --->"
        read -r -p "域名:" domain
    fi
    if [[ -z ${domain} ]]; then
        echoContent red "域名不可为空"
        initTLSNginxConfig 3
    fi
}

randomPathFunction() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 生成随机路径"
    if [[ -n "${path}" ]]; then
        read -r -p "读取到上次安装记录，是否使用上次安装时的path路径 ？[y/n]:" historyPathStatus
    fi
    if [[ "${historyPathStatus}" != "y" ]]; then
        echoContent yellow "请输入自定义路径[例: alone]，不需要斜杠，[回车]随机路径"
        read -r -p '路径:' path
        if [[ -z "${path}" ]]; then
            local chars="abcdefghijklmnopqrtuxyz"
            for _i in {1..4}; do
                path+="${chars:RANDOM%${#chars}:1}"
            done
        elif [[ "${path: -2}" == "ws" ]]; then
            randomPathFunction "$1"
        fi
    fi
}

installTLS() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 申请TLS证书\n"
    if [[ -f "/etc/xray-agent/tls/${domain}.crt" && -f "/etc/xray-agent/tls/${domain}.key" && -s "/etc/xray-agent/tls/${domain}.crt" ]] || [[ -d "$HOME/.acme.sh/${domain}_ecc" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" ]]; then
        TLSDomain="${domain}"
    else
        TLSDomain=$(echo "${domain}" | awk -F "." '{print $(NF-1)"."$NF}')
        if [[ "${TLSDomain}" == "eu.org" ]]; then
            TLSDomain=$(echo "${domain}" | awk -F "." '{print $(NF-2)"."$(NF-1)"."$NF}')
        fi
    fi

    if [[ -f "/etc/xray-agent/tls/${TLSDomain}.crt" && -f "/etc/xray-agent/tls/${TLSDomain}.key" && -s "/etc/xray-agent/tls/${TLSDomain}.crt" ]] || [[ -d "$HOME/.acme.sh/${TLSDomain}_ecc" && -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.key" && -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.cer" ]]; then
        renewalTLS "${TLSDomain}"
        if [[ ! -f "/etc/xray-agent/tls/${TLSDomain}.crt" || ! -f "/etc/xray-agent/tls/${TLSDomain}.key" || ! -s "/etc/xray-agent/tls/${TLSDomain}.crt" ]]; then
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${TLSDomain}" --fullchainpath "/etc/xray-agent/tls/${TLSDomain}.crt" --keypath "/etc/xray-agent/tls/${TLSDomain}.key" --ecc >/dev/null
        else
            read -r -p "是否重新安装？[y/n]:" reInstallStatus
            if [[ "${reInstallStatus}" == "y" ]]; then
                find /etc/xray-agent/tls/ -type f -name "*${TLSDomain}*" -exec rm -f {} \;
                installTLS "$1" 0
            fi
        fi
    elif [[ -d "$HOME/.acme.sh" ]]; then
        handleNginx stop
        switchSSLType
        customSSLEmail
        acmeInstallSSL
        sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${TLSDomain}" --fullchainpath "/etc/xray-agent/tls/${TLSDomain}.crt" --keypath "/etc/xray-agent/tls/${TLSDomain}.key" --ecc >/dev/null
        handleNginx start
        if [[ ! -f "/etc/xray-agent/tls/${TLSDomain}.crt" || ! -f "/etc/xray-agent/tls/${TLSDomain}.key" ]] || [[ ! -s "/etc/xray-agent/tls/${TLSDomain}.key" || ! -s "/etc/xray-agent/tls/${TLSDomain}.crt" ]]; then
            if [[ "$2" == "1" ]]; then
                exit 0
            fi
            if grep -q "Could not validate email address as valid" /etc/xray-agent/tls/acme.log; then
                customSSLEmail "validate email"
                installTLS "$1" 1
            else
                installTLS "$1" 1
            fi
        fi
    else
        exit 0
    fi
}

renewalTLS() {
    if [[ "$1" == "all" ]]; then
        local TLSDomain
        for certFile in /etc/xray-agent/tls/*.crt; do
            TLSDomain=$(basename "$certFile" .crt)
            updateTLSCertificate "${TLSDomain}"
        done
    else
        TLSDomain=$1
        updateTLSCertificate "${TLSDomain}"
    fi
}

updateTLSCertificate() {
    local TLSDomain=$1
    if [[ -d "$HOME/.acme.sh/${TLSDomain}_ecc" && -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.key" && -f "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.cer" ]]; then
        modifyTime=$(stat --format=%z "$HOME/.acme.sh/${TLSDomain}_ecc/${TLSDomain}.cer")
        modifyTime=$(date +%s -d "${modifyTime}")
        currentTime=$(date +%s)
        ((stampDiff = currentTime - modifyTime))
        ((days = stampDiff / 86400))
        sslRenewalDays=90
        ((remainingDays = sslRenewalDays - days))
        if [[ ${remainingDays} -le 14 ]]; then
            handleNginx stop
            handleXray stop
            sudo "$HOME/.acme.sh/acme.sh" --cron --home "$HOME/.acme.sh" -d "${TLSDomain}"
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${TLSDomain}" --fullchainpath /etc/xray-agent/tls/"${TLSDomain}.crt" --keypath /etc/xray-agent/tls/"${TLSDomain}.key" --ecc
            reloadCore
            handleNginx start
        fi
    fi
}

removeCert() {
    mapfile -t certificates < <(for certFile in /etc/xray-agent/tls/*.crt; do basename "$certFile" .crt; done)
    for i in "${!certificates[@]}"; do
        echo "$((i + 1)): ${certificates[$i]}"
    done
    read -r -p "请选择要删除的证书编号[仅支持单个删除]:" delCertificateIndex
    delCertificateIndex=$((delCertificateIndex - 1))
    if [[ ${delCertificateIndex} -lt 0 || ${delCertificateIndex} -ge ${#certificates[@]} ]]; then
        echoContent red " ---> 选择错误"
    else
        sudo rm -f "/etc/xray-agent/tls/${certificates[$delCertificateIndex]}.crt" "/etc/xray-agent/tls/${certificates[$delCertificateIndex]}.key"
    fi
}

manageCert() {
    if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
        xray_agent_error " ---> 未安装，请使用脚本安装"
    fi
    echoContent skyBlue "\n功能 1/${totalProgress} : 证书管理"
    echoContent red "\n=============================================================="
    echoContent yellow "1.申请证书"
    echoContent yellow "2.更新证书"
    echoContent yellow "3.删除证书"
    echoContent red "=============================================================="
    read -r -p "请输入:" manageCertStatus
    case "${manageCertStatus}" in
        1)
            read -r -p "域名:" domain
            installTLS 1 0
            installCronTLS 1
            ;;
        2)
            renewalTLS "all"
            ;;
        3)
            removeCert
            ;;
    esac
}

xray_agent_apply_tls_feature_patches() {
    local tls_vision_path="$1"
    local tls_xhttp_path="$2"
    if declare -F xray_agent_apply_ech_patch >/dev/null 2>&1; then
        xray_agent_apply_ech_patch "${tls_vision_path}"
    fi
    if declare -F xray_agent_apply_browser_headers_patch >/dev/null 2>&1; then
        xray_agent_apply_browser_headers_patch "${tls_xhttp_path}"
    fi
    if declare -F xray_agent_apply_trusted_xff_patch >/dev/null 2>&1; then
        xray_agent_apply_trusted_xff_patch "${tls_xhttp_path}"
    fi
    if declare -F xray_agent_apply_vless_encryption_patch >/dev/null 2>&1; then
        xray_agent_apply_vless_encryption_patch "${tls_vision_path}"
        xray_agent_apply_vless_encryption_patch "${tls_xhttp_path}"
    fi
}

xray_agent_apply_reality_feature_patches() {
    local reality_vision_path="$1"
    local reality_xhttp_path="$2"
    if declare -F xray_agent_apply_finalmask_patch >/dev/null 2>&1; then
        xray_agent_apply_finalmask_patch "${reality_vision_path}"
        xray_agent_apply_finalmask_patch "${reality_xhttp_path}"
    fi
    if declare -F xray_agent_apply_browser_headers_patch >/dev/null 2>&1; then
        xray_agent_apply_browser_headers_patch "${reality_xhttp_path}"
    fi
    if declare -F xray_agent_apply_trusted_xff_patch >/dev/null 2>&1; then
        xray_agent_apply_trusted_xff_patch "${reality_xhttp_path}"
    fi
    if declare -F xray_agent_apply_vless_encryption_patch >/dev/null 2>&1; then
        xray_agent_apply_vless_encryption_patch "${reality_vision_path}"
        xray_agent_apply_vless_encryption_patch "${reality_xhttp_path}"
    fi
}
