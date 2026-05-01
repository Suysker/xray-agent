#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_cert_normalize_domain() {
    local raw_domain="$1"
    raw_domain="${raw_domain#http://}"
    raw_domain="${raw_domain#https://}"
    raw_domain="${raw_domain%%/*}"
    raw_domain="${raw_domain%%:*}"
    raw_domain="${raw_domain#.}"
    if [[ "${raw_domain}" == \*.* ]]; then
        raw_domain="${raw_domain#\*.}"
    fi
    printf '%s\n' "${raw_domain}"
}

xray_agent_cert_base_domain() {
    local input_domain
    input_domain="$(xray_agent_cert_normalize_domain "$1")"
    local base_domain
    base_domain="$(echo "${input_domain}" | awk -F "." '{print $(NF-1)"."$NF}')"
    if [[ "${base_domain}" == "eu.org" ]]; then
        base_domain="$(echo "${input_domain}" | awk -F "." '{print $(NF-2)"."$(NF-1)"."$NF}')"
    fi
    printf '%s\n' "${base_domain}"
}

xray_agent_cert_acme_dir() {
    local cert_domain="$1"
    if [[ -d "$HOME/.acme.sh/${cert_domain}_ecc" ]]; then
        printf '%s\n' "$HOME/.acme.sh/${cert_domain}_ecc"
    fi
}

xray_agent_cert_days_left() {
    local cert_file="$1"
    local end_date end_epoch now_epoch
    [[ -f "${cert_file}" ]] || return 1
    command -v openssl >/dev/null 2>&1 || return 1
    end_date="$(openssl x509 -in "${cert_file}" -noout -enddate 2>/dev/null | awk -F= '{print $2}')"
    [[ -n "${end_date}" ]] || return 1
    end_epoch="$(date -d "${end_date}" +%s 2>/dev/null || true)"
    [[ -n "${end_epoch}" ]] || return 1
    now_epoch="$(date +%s)"
    printf '%s\n' "$(((end_epoch - now_epoch) / 86400))"
}

xray_agent_cert_key_match_status() {
    local cert_file="$1"
    local key_file="$2"
    local cert_pub key_pub
    [[ -f "${cert_file}" && -f "${key_file}" ]] || {
        printf '缺失\n'
        return 0
    }
    command -v openssl >/dev/null 2>&1 || {
        printf '未检测(openssl缺失)\n'
        return 0
    }
    cert_pub="$(openssl x509 -in "${cert_file}" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform PEM 2>/dev/null | sha256sum 2>/dev/null | awk '{print $1}')"
    key_pub="$(openssl pkey -in "${key_file}" -pubout -outform PEM 2>/dev/null | sha256sum 2>/dev/null | awk '{print $1}')"
    if [[ -n "${cert_pub}" && "${cert_pub}" == "${key_pub}" ]]; then
        printf '匹配\n'
    else
        printf '不匹配\n'
    fi
}

xray_agent_cert_inventory_domains() {
    local cert_file acme_dir
    {
        for cert_file in "${XRAY_AGENT_TLS_DIR}"/*.crt; do
            [[ -f "${cert_file}" ]] && basename "${cert_file}" .crt
        done
        for acme_dir in "$HOME/.acme.sh"/*_ecc; do
            [[ -d "${acme_dir}" ]] && basename "${acme_dir}" _ecc
        done
    } | sed '/^\*$/d;/^$/d' | sort -u
}

xray_agent_cert_inventory() {
    local cert_domain cert_file key_file acme_dir days_left match_status acme_status has_cert=false
    echoContent skyBlue "-------------------------证书库存-----------------------------"
    while IFS= read -r cert_domain; do
        [[ -n "${cert_domain}" ]] || continue
        has_cert=true
        cert_file="${XRAY_AGENT_TLS_DIR}/${cert_domain}.crt"
        key_file="${XRAY_AGENT_TLS_DIR}/${cert_domain}.key"
        acme_dir="$(xray_agent_cert_acme_dir "${cert_domain}")"
        if days_left="$(xray_agent_cert_days_left "${cert_file}" 2>/dev/null)"; then
            :
        else
            days_left="未知"
        fi
        match_status="$(xray_agent_cert_key_match_status "${cert_file}" "${key_file}")"
        acme_status="$([[ -n "${acme_dir}" ]] && printf '存在' || printf '缺失')"
        echoContent yellow "${cert_domain}: 到期剩余=${days_left}天 文件=$([[ -f "${cert_file}" && -f "${key_file}" ]] && printf '完整' || printf '缺失') 私钥=${match_status} acme记录=${acme_status}"
    done < <(xray_agent_cert_inventory_domains)
    if [[ "${has_cert}" != "true" ]]; then
        echoContent yellow "暂无证书文件或 acme 记录"
    fi
}

xray_agent_cert_primary_domain() {
    if [[ -n "${TLSDomain:-}" ]]; then
        printf '%s\n' "${TLSDomain}"
    elif [[ -n "${domain:-}" ]]; then
        printf '%s\n' "$(xray_agent_cert_normalize_domain "${domain}")"
    fi
}

xray_agent_cert_primary_status() {
    local cert_domain cert_file days_left match_status
    cert_domain="$(xray_agent_cert_primary_domain)"
    [[ -n "${cert_domain}" ]] || {
        printf '无证书域名\n'
        return 0
    }
    cert_file="${XRAY_AGENT_TLS_DIR}/${cert_domain}.crt"
    if [[ ! -f "${cert_file}" ]]; then
        printf '%s 缺失\n' "${cert_domain}"
        return 0
    fi
    if days_left="$(xray_agent_cert_days_left "${cert_file}" 2>/dev/null)"; then
        match_status="$(xray_agent_cert_key_match_status "${cert_file}" "${XRAY_AGENT_TLS_DIR}/${cert_domain}.key")"
        if [[ "${days_left}" =~ ^-?[0-9]+$ && "${days_left}" -le 14 ]]; then
            printf '%s 临期(%s天) 私钥%s\n' "${cert_domain}" "${days_left}" "${match_status}"
        else
            printf '%s 正常(%s天) 私钥%s\n' "${cert_domain}" "${days_left}" "${match_status}"
        fi
    else
        printf '%s 存在，到期未知\n' "${cert_domain}"
    fi
}

xray_agent_cert_resolved_records() {
    local record_type="$1"
    local cert_domain="$2"
    command -v dig >/dev/null 2>&1 || return 0
    dig +short "${record_type}" "${cert_domain}" 2>/dev/null | sed '/^$/d' | sort -u
}

xray_agent_cert_csv_contains() {
    local csv="$1"
    local value="$2"
    xray_agent_csv_to_lines "${csv}" | grep -Fxq "${value}"
}

xray_agent_cert_records_match_public() {
    local records="$1"
    local csv="$2"
    local record
    while IFS= read -r record; do
        [[ -n "${record}" ]] || continue
        if xray_agent_cert_csv_contains "${csv}" "${record}"; then
            return 0
        fi
    done <<<"${records}"
    return 1
}

xray_agent_cert_port_owner() {
    local port="$1"
    xray_agent_port_owner TCP "${port}"
}

xray_agent_cert_preflight() {
    local input_domain="$1"
    local want_wildcard="${2:-false}"
    local normalized_domain base_domain a_records aaaa_records port80_owner port443_owner
    normalized_domain="$(xray_agent_cert_normalize_domain "${input_domain}")"
    if ! xray_agent_validate_domain "${normalized_domain}"; then
        echoContent red " ---> 域名不合法: ${input_domain}"
        return 1
    fi

    domain="${normalized_domain}"
    if [[ "${want_wildcard}" == "true" ]]; then
        base_domain="$(xray_agent_cert_base_domain "${normalized_domain}")"
        TLSDomain="${base_domain}"
    else
        TLSDomain="${normalized_domain}"
    fi

    xray_agent_detect_network_capabilities --refresh
    a_records="$(xray_agent_cert_resolved_records A "${normalized_domain}")"
    aaaa_records="$(xray_agent_cert_resolved_records AAAA "${normalized_domain}")"
    port80_owner="$(xray_agent_cert_port_owner 80)"
    port443_owner="$(xray_agent_cert_port_owner 443)"

    echoContent skyBlue "-------------------------申请前预检-----------------------------"
    echoContent yellow "申请域名: ${domain}  证书域名: ${TLSDomain}"
    echoContent yellow "网络栈: $(xray_agent_route_mode_label)"
    echoContent yellow "公网IPv4: ${publicIPv4CSV:-未检测到}"
    echoContent yellow "公网IPv6: ${publicIPv6CSV:-未检测到}"
    echoContent yellow "DNS A: ${a_records:-未解析到}"
    echoContent yellow "DNS AAAA: ${aaaa_records:-未解析到}"
    echoContent yellow "端口: TCP/80=${port80_owner} TCP/443=${port443_owner}"
    if xray_agent_xray_supports_tls_ech; then
        echoContent green "TLS ECH: 当前 Xray-core 支持，证书安装后可生成 echServerKeys 和分享 ech。"
    else
        echoContent yellow "TLS ECH: 当前 Xray-core 不支持，升级正式版后才会启用。"
    fi
    if [[ "${warpDefaultIPv4}" == "true" || "${warpDefaultIPv6}" == "true" ]]; then
        echoContent yellow "提示: 系统默认路由存在 WARP 接管，公网探测结果可能是 WARP 出口。"
    fi

    xray_agent_cert_recommend_method "${want_wildcard}" "${a_records}" "${aaaa_records}" "${port80_owner}"
}

xray_agent_cert_recommend_method() {
    local want_wildcard="$1"
    local a_records="$2"
    local aaaa_records="$3"
    local port80_owner="$4"
    certRecommendMethod="dns"
    certRecommendReason="DNS 解析或端口条件不适合 standalone"

    if [[ "${want_wildcard}" == "true" ]]; then
        certRecommendMethod="dns"
        certRecommendReason="通配证书必须使用 DNS-01"
    elif [[ "${routeIPv4}" != "true" && "${routeIPv6}" != "true" ]]; then
        certRecommendMethod="dns"
        certRecommendReason="当前没有可用默认路由，HTTP-01 不可靠"
    elif [[ -n "${a_records}${aaaa_records}" ]] &&
        { xray_agent_cert_records_match_public "${a_records}" "${publicIPv4CSV}" || xray_agent_cert_records_match_public "${aaaa_records}" "${publicIPv6CSV}"; }; then
        if [[ "${port80_owner}" == "空闲" || "${port80_owner}" == nginx/* ]]; then
            certRecommendMethod="http"
            certRecommendReason="解析匹配当前公网，80 端口可由脚本临时接管"
        else
            certRecommendMethod="dns"
            certRecommendReason="80 端口被 ${port80_owner} 占用，DNS-01 更稳"
        fi
    fi

    if [[ "${certRecommendMethod}" == "http" ]]; then
        echoContent green "推荐方式: HTTP-01 standalone。原因: ${certRecommendReason}"
    else
        echoContent yellow "推荐方式: DNS-01。原因: ${certRecommendReason}"
    fi
}

xray_agent_cert_explain_failure() {
    local log_file="${1:-${XRAY_AGENT_TLS_DIR}/acme.log}"
    if [[ ! -f "${log_file}" ]]; then
        echoContent yellow "暂无 acme 日志: ${log_file}"
        return 0
    fi
    echoContent skyBlue "-------------------------失败原因分析-----------------------------"
    if grep -qiE "validate email|Could not validate email" "${log_file}"; then
        echoContent red "邮箱错误: 重新输入可用邮箱，ZeroSSL/HiCA 尤其需要有效邮箱。"
    elif grep -qiE "rate limit|too many certificates|too many failed authorizations" "${log_file}"; then
        echoContent red "CA 限流: 等待限流窗口恢复，或切换 CA/减少重复申请。"
    elif grep -qiE "TXT value|No TXT record|dns manual" "${log_file}"; then
        echoContent yellow "TXT 未生效: 确认 _acme-challenge 记录和值一致，并等待 DNS 传播。"
    elif grep -qiE "Invalid status|unauthorized|Verify error|timeout|connection refused" "${log_file}"; then
        echoContent red "验证失败: 检查域名 A/AAAA 是否指向本机、公网 80 是否可达、防火墙和云安全组是否放行。"
    elif grep -qiE "eab|EAB|access_key|invalid api" "${log_file}"; then
        echoContent red "EAB/API 错误: 检查 ZeroSSL API Key 或 DNS 服务商 API 权限。"
    else
        echoContent yellow "未匹配到已知错误类型，最近日志如下:"
        tail -n 20 "${log_file}"
    fi
}

xray_agent_cert_select_apply_method() {
    local selected_method
    if [[ "${certRecommendMethod:-dns}" == "http" ]]; then
        read -r -p "使用推荐的 HTTP-01 standalone？[Y/n]:" selected_method
        selected_method="${selected_method:-y}"
        [[ "${selected_method}" == "y" ]] && {
            installSSLType=3
            return 0
        }
    else
        read -r -p "使用推荐的 DNS-01？[Y/n]:" selected_method
        selected_method="${selected_method:-y}"
        [[ "${selected_method}" == "y" ]] && {
            installSSLType=1
            return 0
        }
    fi

    echoContent yellow "1.HTTP-01 standalone"
    echoContent yellow "2.DNS-01 API"
    echoContent yellow "3.DNS-01 手动TXT"
    read -r -p "请选择申请方式:" selected_method
    case "${selected_method}" in
        1) installSSLType=3 ;;
        3) installSSLType=2 ;;
        *) installSSLType=1 ;;
    esac
}

xray_agent_cert_apply() {
    local input_domain="$1"
    local want_wildcard="${2:-false}"
    xray_agent_cert_preflight "${input_domain}" "${want_wildcard}" || return 1
    xray_agent_cert_select_apply_method
    echoContent yellow "即将申请/安装证书: ${TLSDomain}，方式: $([[ "${installSSLType}" == "3" ]] && printf 'HTTP-01' || printf 'DNS-01')"
    if ! xray_agent_confirm "确认继续？[y/N]:" "n"; then
        echoContent yellow " ---> 已取消"
        return 0
    fi
    installTLS 1 0
    installCronTLS 1
}

switchSSLType() {
    if [[ -z "${sslType}" ]]; then
        xray_agent_blank
        echoContent red "=============================================================="
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
    mkdir -p "${XRAY_AGENT_TLS_DIR}"
    xray_agent_detect_network_capabilities
    if [[ "${routeIPv6}" == "true" ]]; then
        installSSLIPv6="--listen-v6"
    else
        installSSLIPv6=""
    fi

    xray_agent_blank
    echoContent red "=============================================================="
    if [[ -z "${installSSLType:-}" ]]; then
        echoContent yellow "1. 密钥（通配证书）"
        echoContent yellow "2. DNS（通配证书）"
        echoContent yellow "3. 普通证书【默认】"
        read -r -p "申请SSL证书的方式 [默认: 3]：" installSSLType
        installSSLType=${installSSLType:-3}
    else
        echoContent yellow "申请方式: ${installSSLType}"
    fi

    if [[ "${installSSLType}" == "1" ]]; then
        xray_agent_blank
        echoContent red "=============================================================="
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
            echoContent yellow " --->  检测命令: dig @1.1.1.1 +short TXT _acme-challenge.${TLSDomain}"
            echoContent yellow " --->  TXT 生效可能需要几分钟，未生效时不要反复申请。"
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

initTLSNginxConfig() {
    xray_agent_blank
    echoContent skyBlue "进度  $1/${totalProgress} : 初始化Nginx申请证书配置"
    if [[ -n "${domain}" ]]; then
        read -r -p "读取到上次安装记录，是否使用上次安装时的域名 ？[y/n]:" historyDomainStatus
        if [[ "${historyDomainStatus}" != "y" ]]; then
            echoContent yellow "请输入要配置的域名 例: www.xray-agent.com --->"
            read -r -p "域名:" domain
        else
            xray_agent_blank
            echoContent yellow " ---> 域名: ${domain}"
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
    xray_agent_blank
    echoContent skyBlue "进度  $1/${totalProgress} : 生成随机路径"
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
    xray_agent_blank
    echoContent skyBlue "进度  $1/${totalProgress} : 申请TLS证书"
    xray_agent_blank
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
            [[ -f "${certFile}" ]] || continue
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

xray_agent_cert_force_renew_all() {
    local cert_domain
    if ! xray_agent_confirm "强制续签会触发 CA 频率限制风险，确认继续？[y/N]:" "n"; then
        echoContent yellow " ---> 已取消"
        return 0
    fi
    handleNginx stop
    handleXray stop
    while IFS= read -r cert_domain; do
        [[ -n "${cert_domain}" ]] || continue
        if [[ -d "$HOME/.acme.sh/${cert_domain}_ecc" ]]; then
            echoContent yellow " ---> 强制续签 ${cert_domain}"
            sudo "$HOME/.acme.sh/acme.sh" --renew -d "${cert_domain}" --force --ecc 2>&1 | tee -a "${XRAY_AGENT_TLS_DIR}/acme.log" >/dev/null
            sudo "$HOME/.acme.sh/acme.sh" --installcert -d "${cert_domain}" --fullchainpath "${XRAY_AGENT_TLS_DIR}/${cert_domain}.crt" --keypath "${XRAY_AGENT_TLS_DIR}/${cert_domain}.key" --ecc
        else
            echoContent yellow " ---> 跳过 ${cert_domain}: acme 记录缺失"
        fi
    done < <(xray_agent_cert_inventory_domains)
    reloadCore
    handleNginx start
}

removeCert() {
    mapfile -t certificates < <(for certFile in /etc/xray-agent/tls/*.crt; do [[ -f "${certFile}" ]] && basename "$certFile" .crt; done)
    if [[ "${#certificates[@]}" -eq 0 ]]; then
        echoContent yellow " ---> 暂无可删除证书"
        return 0
    fi
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
    if [[ ! -x "$HOME/.acme.sh/acme.sh" ]]; then
        xray_agent_error " ---> 未安装，请使用脚本安装"
    fi
    local manageCertStatus input_domain default_domain wildcard_status
    xray_agent_tool_status_header "证书管理"
    xray_agent_cert_inventory
    xray_agent_blank
    echoContent red "=============================================================="
    echoContent yellow "1.智能申请/重装证书"
    echoContent yellow "2.更新临期证书"
    echoContent yellow "3.强制续签全部证书"
    echoContent yellow "4.删除证书"
    echoContent yellow "5.解释最近一次申请失败"
    echoContent red "=============================================================="
    read -r -p "请输入:" manageCertStatus
    case "${manageCertStatus}" in
        1)
            default_domain="${domain:-${TLSDomain:-}}"
            if [[ -n "${default_domain}" ]]; then
                read -r -p "域名[回车使用 ${default_domain}]:" input_domain
                input_domain="${input_domain:-${default_domain}}"
            else
                read -r -p "域名:" input_domain
            fi
            read -r -p "是否申请通配证书(*.$(xray_agent_cert_base_domain "${input_domain}"))？[y/N]:" wildcard_status
            installSSLType=
            xray_agent_cert_apply "${input_domain}" "$([[ "${wildcard_status}" == "y" ]] && printf true || printf false)"
            ;;
        2)
            echoContent yellow "将只续签到期/14天内临期证书。"
            renewalTLS "all"
            ;;
        3)
            xray_agent_cert_force_renew_all
            ;;
        4)
            removeCert
            ;;
        5)
            xray_agent_cert_explain_failure "${XRAY_AGENT_TLS_DIR}/acme.log"
            ;;
    esac
}

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
    xray_agent_blank
    echoContent skyBlue "进度  $1/${totalProgress} : 初始化Reality证书配置"
    local default_reality_target default_reality_server_name historyDestStatus tlsPingResult inputRealityDestDomain
    if declare -F xray_agent_nginx_reality_default_target >/dev/null 2>&1; then
        default_reality_target="$(xray_agent_nginx_reality_default_target)"
        default_reality_server_name="$(xray_agent_nginx_reality_default_host)"
    fi
    while true; do
        if [[ -n "${RealityDestDomain}" ]]; then
            read -r -p "读取到上次安装记录，是否使用上次安装时的域名 ？[y/n]:" historyDestStatus
            if [[ "${historyDestStatus}" != "y" ]]; then
                xray_agent_blank
                if [[ -n "${default_reality_target:-}" ]]; then
                    echoContent skyBlue " ---> 检测到已注册真实网站，Reality target 默认使用 ${default_reality_target}"
                else
                    echoContent skyBlue " ---> 生成配置回落的域名 例如: addons.mozilla.org:443"
                fi
                xray_agent_blank
                read -r -p '请输入:' inputRealityDestDomain
                RealityDestDomain="${inputRealityDestDomain:-${default_reality_target:-}}"
            else
                xray_agent_blank
                echoContent green " ---> 使用成功"
            fi
        else
            xray_agent_blank
            if [[ -n "${default_reality_target:-}" ]]; then
                echoContent skyBlue " ---> 检测到已注册真实网站，Reality target 默认使用 ${default_reality_target}"
            else
                echoContent skyBlue " ---> 生成配置回落的域名 例如: addons.mozilla.org:443"
            fi
            xray_agent_blank
            read -r -p '请输入:' inputRealityDestDomain
            RealityDestDomain="${inputRealityDestDomain:-${default_reality_target:-}}"
        fi

        if [[ -z "${RealityDestDomain}" ]]; then
            echoContent red "域名不可为空"
        elif [[ "${RealityDestDomain}" != *:* ]]; then
            xray_agent_blank
            echoContent red " ---> 域名不合规范，请重新输入 (示例: addons.mozilla.org:443)"
        else
            break
        fi
    done

    xray_agent_blank
    echoContent skyBlue " >配置客户端可用的serverNames"
    xray_agent_blank
    if [[ "${historyDestStatus}" == "y" ]] && [[ -n "${RealityServerNames}" ]]; then
        RealityServerNames="\"${RealityServerNames//,/\",\"}\""
    else
        tlsPingResult=$(${ctlPath} tls ping "${RealityDestDomain%%:*}")
        xray_agent_blank
        echoContent yellow " ---> 可以输入的域名: ${tlsPingResult}"
        if [[ -n "${default_reality_server_name:-}" ]]; then
            echoContent yellow " ---> 已注册真实网站默认 serverNames: ${default_reality_server_name}"
        fi
        xray_agent_blank
        read -r -p "请输入:" RealityServerNames
        if [[ -z "${RealityServerNames}" ]]; then
            RealityServerNames="\"${default_reality_server_name:-${RealityDestDomain%%:*}}\""
        else
            RealityServerNames="\"${RealityServerNames//,/\",\"}\""
        fi
    fi
}
