if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

warpRouting() {
    if [[ "$(ip a)" =~ ": WARP:" ]]; then
        warpinterface="WARP"
    elif [[ "$(ip a)" =~ ": wgcf:" ]]; then
        warpinterface="wgcf"
    elif [[ "$(ip a)" =~ ": warp:" ]]; then
        warpinterface="warp"
    else
        xray_agent_error " ---> 未安装或未开启，请使用脚本安装或开启"
    fi
    echoContent yellow "1.添加域名"
    echoContent yellow "2.卸载WARP分流"
    echoContent yellow "3.查看已分流域名"
    echoContent yellow "4.分流CN的域名和IP"
    echoContent yellow "5.卸载分流CN域名和IP"
    read -r -p "请选择:" warpStatus
    if [[ "${warpStatus}" == "3" ]]; then
        jq -r -c '.routing.rules[]|select (.outboundTag=="warp-out")|.domain' "${configPath}09_routing.json" | jq -r
        return 0
    elif [[ "${warpStatus}" != "2" && "${warpStatus}" != "5" ]]; then
        if [[ "${warpStatus}" == "1" ]]; then
            unInstallOutbounds warp-out
            outbounds=$(jq -r ".outbounds += [{\"protocol\":\"freedom\",\"streamSettings\":{\"sockopt\":{\"interface\":\"${warpinterface}\"}},\"settings\":{\"domainStrategy\":\"UseIP\"},\"tag\":\"warp-out\"}]" "${configPath}10_ipv4_outbounds.json")
        elif [[ "${warpStatus}" == "4" ]]; then
            unInstallOutbounds cn-out
            outbounds=$(jq -r ".outbounds += [{\"protocol\":\"freedom\",\"streamSettings\":{\"sockopt\":{\"interface\":\"${warpinterface}\"}},\"settings\":{\"domainStrategy\":\"UseIP\"},\"tag\":\"cn-out\"}]" "${configPath}10_ipv4_outbounds.json")
        fi
        echo "${outbounds}" | jq . >"${configPath}10_ipv4_outbounds.json"
        if [[ "${warpStatus}" == "1" ]]; then
            read -r -p "请按照上面示例录入域名:" domainList
            if [[ -f "${configPath}09_routing.json" ]]; then
                unInstallRouting warp-out outboundTag
                routing=$(jq -r ".routing.rules += [{\"type\":\"field\",\"domain\":[\"geosite:${domainList//,/\",\"geosite:}\"],\"outboundTag\":\"warp-out\"}]" "${configPath}09_routing.json")
                echo "${routing}" | jq . >"${configPath}09_routing.json"
            fi
        elif [[ "${warpStatus}" == "4" ]]; then
            if [[ -f "${configPath}09_routing.json" ]]; then
                unInstallRouting cn-out outboundTag
                routing=$(jq -r ".routing.rules += [{\"type\":\"field\",\"domain\":[\"geosite:cn\"],\"ip\":[\"geoip:cn\"],\"outboundTag\":\"cn-out\"}]" "${configPath}09_routing.json")
                echo "${routing}" | jq . >"${configPath}09_routing.json"
            fi
            unInstallRouting cn-blackhole outboundTag
            unInstallOutbounds cn-blackhole
        fi
    elif [[ "${warpStatus}" == "2" ]]; then
        unInstallRouting warp-out outboundTag
        unInstallOutbounds warp-out
    elif [[ "${warpStatus}" == "5" ]]; then
        unInstallRouting cn-out outboundTag
        unInstallOutbounds cn-out
    fi
    reloadCore
}
