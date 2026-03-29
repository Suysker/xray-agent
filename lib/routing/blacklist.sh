if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

blacklist() {
    echoContent yellow "1.添加域名"
    echoContent yellow "2.删除黑名单"
    echoContent yellow "3.查看已屏蔽域名"
    echoContent yellow "4.启用阻止访问中国大陆IP"
    echoContent yellow "5.卸载阻止访问中国大陆IP"
    read -r -p "请选择:" blacklistStatus
    if [[ "${blacklistStatus}" == "3" ]]; then
        jq -r -c '.routing.rules[]|select (.outboundTag=="blackhole-out")|.domain' "${configPath}09_routing.json" | jq -r
        return 0
    elif [[ "${blacklistStatus}" == "1" ]]; then
        read -r -p "请按照上面示例录入域名:" domainList
        if [[ -f "${configPath}09_routing.json" ]]; then
            unInstallRouting blackhole-out outboundTag
            routing=$(jq -r ".routing.rules += [{\"type\":\"field\",\"domain\":[\"geosite:${domainList//,/\",\"geosite:}\"],\"outboundTag\":\"blackhole-out\"}]" "${configPath}09_routing.json")
            echo "${routing}" | jq . >"${configPath}09_routing.json"
        fi
    elif [[ "${blacklistStatus}" == "2" ]]; then
        unInstallRouting blackhole-out outboundTag
    elif [[ "${blacklistStatus}" == "4" ]]; then
        if [[ -f "${configPath}09_routing.json" ]]; then
            unInstallRouting cn-blackhole outboundTag
            routing=$(jq -r ".routing.rules += [{\"type\":\"field\",\"ip\":[\"geoip:cn\"],\"outboundTag\":\"cn-blackhole\"}]" "${configPath}09_routing.json")
            echo "${routing}" | jq . >"${configPath}09_routing.json"
        fi
        unInstallOutbounds cn-blackhole
        outbounds=$(jq -r '.outbounds += [{"protocol":"blackhole","tag":"cn-blackhole"}]' "${configPath}10_ipv4_outbounds.json")
        echo "${outbounds}" | jq . >"${configPath}10_ipv4_outbounds.json"
        unInstallRouting cn-out outboundTag
        unInstallOutbounds cn-out
    elif [[ "${blacklistStatus}" == "5" ]]; then
        unInstallRouting cn-blackhole outboundTag
    fi
    reloadCore
}
