if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

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
