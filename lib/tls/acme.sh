if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

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
