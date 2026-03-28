xray_agent_tls_warning_for_target() {
    local target="$1"
    if [[ "${target}" != *":443" ]]; then
        echoContent yellow " ---> 提示: REALITY 目标未使用 443，后续兼容性可能较差"
    fi
}

xray_agent_tls_warning_for_xhttp_port() {
    local target_port="$1"
    if [[ -n "${target_port}" ]] && [[ "${target_port}" != "443" ]]; then
        echoContent yellow " ---> 提示: 当前端口不是 443，部分 XHTTP/REALITY 组合可能触发客户端兼容告警"
    fi
}

initTLSRealityConfig() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 初始化Reality证书配置"
    while true; do
        if [[ -n "${RealityDestDomain}" ]]; then
            read -r -p "读取到上次安装记录，是否使用上次安装时的域名 ？[y/n]:" historyDestStatus
            if [[ "${historyDestStatus}" != "y" ]]; then
                echoContent skyBlue "\n ---> 生成配置回落的域名 例如: addons.mozilla.org:443\n"
                read -r -p '请输入:' RealityDestDomain
            else
                echoContent green "\n ---> 使用成功"
            fi
        else
            echoContent skyBlue "\n ---> 生成配置回落的域名 例如: addons.mozilla.org:443\n"
            read -r -p '请输入:' RealityDestDomain
        fi

        if [[ -z "${RealityDestDomain}" ]]; then
            echoContent red "域名不可为空"
        elif [[ "${RealityDestDomain}" != *:* ]]; then
            echoContent red "\n ---> 域名不合规范，请重新输入 (示例: addons.mozilla.org:443)"
        else
            break
        fi
    done

    echoContent skyBlue "\n >配置客户端可用的serverNames\n"
    if [[ "${historyDestStatus}" == "y" ]] && [[ -n "${RealityServerNames}" ]]; then
        RealityServerNames="\"${RealityServerNames//,/\",\"}\""
    else
        tlsPingResult=$(${ctlPath} tls ping "${RealityDestDomain%%:*}")
        echoContent yellow "\n ---> 可以输入的域名: ${tlsPingResult}\n"
        read -r -p "请输入:" RealityServerNames
        if [[ -z "${RealityServerNames}" ]]; then
            RealityServerNames="\"${RealityDestDomain%%:*}\""
        else
            RealityServerNames="\"${RealityServerNames//,/\",\"}\""
        fi
    fi
}

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

switchSSLType() {
    if [[ -z "${sslType}" ]]; then
        echoContent red "\n=============================================================="
        echoContent yellow "1.letsencrypt[默认]"
        echoContent yellow "2.zerossl"
        echoContent yellow "3.HiCA"
        echoContent red "=============================================================="
        read -r -p "请选择[回车]使用默认:" selectSSLType
        case ${selectSSLType} in
            2)
                sslType="zerossl"
                ;;
            3)
                sslType="https://acme.hi.cn/directory"
                ;;
            *)
                sslType="letsencrypt"
                ;;
        esac
    fi
}

acmeInstallSSL() {
    currentIPv6IP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)
    if [[ -z "${currentIPv6IP}" ]]; then
        installSSLIPv6=""
    else
        installSSLIPv6="--listen-v6"
    fi

    echoContent red "\n=============================================================="
    echoContent yellow "1. 密钥（通配证书）"
    echoContent yellow "2. DNS（通配证书）"
    echoContent yellow "3. 普通证书【默认】"
    read -r -p "申请SSL证书的方式 [默认: 3]：" installSSLType
    installSSLType=${installSSLType:-3}

    if [[ "${installSSLType}" == "1" ]]; then
        echoContent red "\n=============================================================="
        echoContent yellow "1. Cloudflare [默认]"
        echoContent yellow "2. DNSPod"
        echoContent yellow "3. Aliyun"
        echoContent yellow "4. 其他"
        echoContent red "=============================================================="
        read -r -p "请选择DNS服务商 [默认: 1]：" selectDNS
        selectDNS=${selectDNS:-1}
        if [[ "${selectDNS}" == "1" ]]; then
            read -r -p "请输入Cloudflare API Token:" CF_Token
            dnsEnvVars="CF_Token='${CF_Token}'"
            dnsType="dns_cf"
        elif [[ "${selectDNS}" == "2" ]]; then
            read -r -p "请输入DNSPod API Key:" DP_Key
            read -r -p "请输入DNSPod API ID:" DP_Id
            dnsEnvVars="DP_Key='${DP_Key}' DP_Id='${DP_Id}'"
            dnsType="dns_dp"
        elif [[ "${selectDNS}" == "3" ]]; then
            read -r -p "请输入Aliyun API Key:" Ali_Key
            read -r -p "请输入Aliyun Secret:" Ali_Secret
            dnsEnvVars="Ali_Key='${Ali_Key}' Ali_Secret='${Ali_Secret}'"
            dnsType="dns_ali"
        else
            read -r -p "请输入DNS服务商:" dnsType
        fi

        if [[ "${sslType}" == "zerossl" ]]; then
            read -r -p "请输入ZeroSSL后台控制面板拿到的API Key:" ZeroSSL_API
            ZeroSSL_Result=$(curl -s -X POST "https://api.zerossl.com/acme/eab-credentials?access_key=${ZeroSSL_API}")
            eab_kid=$(echo "$ZeroSSL_Result" | jq -r .eab_kid)
            eab_hmac_key=$(echo "$ZeroSSL_Result" | jq -r .eab_hmac_key)
            sudo "$HOME/.acme.sh/acme.sh" --register-account --server zerossl --eab-kid "${eab_kid}" --eab-hmac-key "${eab_hmac_key}"
        fi
        eval "${dnsEnvVars}" sudo -E "$HOME/.acme.sh/acme.sh" --issue -d "${TLSDomain}" -d "*.${TLSDomain}" --dns "${dnsType}" -k ec-256 --server "${sslType}" ${installSSLIPv6} --force 2>&1 | tee -a /etc/xray-agent/tls/acme.log >/dev/null
    elif [[ "${installSSLType}" == "2" ]]; then
        sudo "$HOME/.acme.sh/acme.sh" --issue -d "${TLSDomain}" -d "*.${TLSDomain}" --dns --yes-I-know-dns-manual-mode-enough-go-ahead-please -k ec-256 --server "${sslType}" ${installSSLIPv6} --force 2>&1 | tee -a /etc/xray-agent/tls/acme.log >/dev/null
        txtValue=$(tail -n 10 /etc/xray-agent/tls/acme.log | grep "TXT value" | awk -F "'" '{print $2}')
        if [[ -n "${txtValue}" ]]; then
            echoContent green " --->  name：_acme-challenge"
            echoContent green " --->  value：${txtValue}"
            read -r -p "是否添加完成[y/n]:" addDNSTXTRecordStatus
            if [[ "${addDNSTXTRecordStatus}" == "y" ]]; then
                txtAnswer=$(dig @1.1.1.1 +nocmd "_acme-challenge.${TLSDomain}" txt +noall +answer | awk -F "[\"]" '{print $2}')
                if [[ "${txtAnswer}" == "${txtValue}" ]]; then
                    sudo "$HOME/.acme.sh/acme.sh" --renew -d "${TLSDomain}" -d "*.${TLSDomain}" --yes-I-know-dns-manual-mode-enough-go-ahead-please --ecc --server "${sslType}" ${installSSLIPv6} --force 2>&1 | tee -a /etc/xray-agent/tls/acme.log >/dev/null
                else
                    exit 1
                fi
            else
                exit 0
            fi
        fi
    else
        allowPort 80
        allowPort 443
        TLSDomain=${domain}
        sudo "$HOME/.acme.sh/acme.sh" --issue -d "${TLSDomain}" --standalone -k ec-256 --server "${sslType}" ${installSSLIPv6} --force 2>&1 | tee -a /etc/xray-agent/tls/acme.log >/dev/null
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

customSSLEmail() {
    if echo "$1" | grep -q "validate email"; then
        read -r -p "是否重新输入邮箱地址[y/n]:" sslEmailStatus
        if [[ "${sslEmailStatus}" == "y" ]]; then
            sed '/ACCOUNT_EMAIL/d' /root/.acme.sh/account.conf >/root/.acme.sh/account.conf_tmp && mv /root/.acme.sh/account.conf_tmp /root/.acme.sh/account.conf
        else
            exit 0
        fi
    fi
    if [[ -d "/root/.acme.sh" && -f "/root/.acme.sh/account.conf" ]]; then
        if ! grep -q "ACCOUNT_EMAIL" <"/root/.acme.sh/account.conf" && ! echo "${sslType}" | grep -q "letsencrypt"; then
            read -r -p "请输入邮箱地址:" sslEmail
            if echo "${sslEmail}" | grep -q "@"; then
                echo "ACCOUNT_EMAIL='${sslEmail}'" >>/root/.acme.sh/account.conf
            else
                customSSLEmail
            fi
        fi
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
            for i in {1..4}; do
                path+="${chars:RANDOM%${#chars}:1}"
            done
        elif [[ "${path: -2}" == "ws" ]]; then
            randomPathFunction "$1"
        fi
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

installCronTLS() {
    if [[ -f "/etc/xray-agent/install.sh" ]]; then
        crontab -l >/etc/xray-agent/backup_crontab.cron
        historyCrontab=$(sed '/install.sh/d;/acme.sh/d' /etc/xray-agent/backup_crontab.cron)
        echo "${historyCrontab}" >/etc/xray-agent/backup_crontab.cron
        echo "30 1 * * * /bin/bash /etc/xray-agent/install.sh RenewTLS >> /etc/xray-agent/crontab_tls.log 2>&1" >>/etc/xray-agent/backup_crontab.cron
        crontab /etc/xray-agent/backup_crontab.cron
    else
        crontab -l | grep -v 'install.sh RenewTLS' | crontab -
    fi
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
