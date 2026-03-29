if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

ipv6Routing() {
    currentIPv6IP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | cut -d "=" -f 2)
    if [[ -z "${currentIPv6IP}" ]]; then
        xray_agent_error " ---> 不支持ipv6"
    fi
    echoContent yellow "1.添加域名"
    echoContent yellow "2.卸载IPv6分流"
    echoContent yellow "3.查看已分流域名"
    echoContent yellow "4.全局IPv6优先"
    echoContent yellow "5.全局IPv4优先"
    read -r -p "请选择:" ipv6Status
    if [[ "${ipv6Status}" == "1" ]]; then
        read -r -p "请按照上面示例录入域名:" domainList
        if [[ -f "${configPath}09_routing.json" ]]; then
            unInstallRouting IPv6-out outboundTag
            routing=$(jq -r ".routing.rules += [{\"type\":\"field\",\"domain\":[\"geosite:${domainList//,/\",\"geosite:}\"],\"outboundTag\":\"IPv6-out\"}]" "${configPath}09_routing.json")
            echo "${routing}" | jq . >"${configPath}09_routing.json"
        fi
    elif [[ "${ipv6Status}" == "2" ]]; then
        unInstallRouting IPv6-out outboundTag
    elif [[ "${ipv6Status}" == "3" ]]; then
        jq -r -c '.routing.rules[]|select (.outboundTag=="IPv6-out")|.domain' "${configPath}09_routing.json" | jq -r
        return 0
    fi

    if [[ "${ipv6Status}" == "1" || "${ipv6Status}" == "4" || "${ipv6Status}" == "5" ]]; then
        unInstallOutbounds IPv4-out
        unInstallOutbounds IPv6-out
        unInstallOutbounds blackhole-out
        if [[ "${ipv6Status}" == "4" ]]; then
            xray_agent_apply_routing_profile "ipv6_first"
        else
            xray_agent_apply_routing_profile "ipv4_first"
        fi
    fi
    reloadCore
}
