xray_agent_default_outbounds_json() {
    jq -nc '[
      {
        protocol: "freedom",
        settings: {domainStrategy: "UseIPv4"},
        tag: "IPv4-out"
      },
      {
        protocol: "freedom",
        settings: {domainStrategy: "UseIPv6"},
        tag: "IPv6-out"
      },
      {
        protocol: "blackhole",
        tag: "blackhole-out"
      }
    ]'
}

xray_agent_default_routing_rules_json() {
    jq -nc '[]'
}

xray_agent_default_dns_servers_json() {
    jq -nc '["localhost"]'
}

unInstallRouting() {
    local tag=$1
    local type=$2
    local protocol=$3
    if [[ -f "${configPath}09_routing.json" ]]; then
        local routing
        if grep -q "${tag}" "${configPath}09_routing.json" && grep -q "${type}" "${configPath}09_routing.json"; then
            jq -c .routing.rules[] "${configPath}09_routing.json" | while read -r line; do
                local index=$((index + 1))
                local delStatus=0
                if [[ "${type}" == "outboundTag" ]] && echo "${line}" | jq .outboundTag | grep -q "${tag}"; then
                    delStatus=1
                elif [[ "${type}" == "inboundTag" ]] && echo "${line}" | jq .inboundTag | grep -q "${tag}"; then
                    delStatus=1
                fi
                if [[ -n ${protocol} ]] && echo "${line}" | jq .protocol | grep -q "${protocol}"; then
                    delStatus=1
                elif [[ -z ${protocol} ]] && [[ $(echo "${line}" | jq .protocol) != "null" ]]; then
                    delStatus=0
                fi
                if [[ ${delStatus} == 1 ]]; then
                    routing=$(jq -r 'del(.routing.rules['$((index - 1))'])' "${configPath}09_routing.json")
                    echo "${routing}" | jq . >"${configPath}09_routing.json"
                fi
            done
        fi
    fi
}

unInstallOutbounds() {
    local tag=$1
    if grep -q "${tag}" "${configPath}10_ipv4_outbounds.json"; then
        local ipv6OutIndex
        ipv6OutIndex=$(jq .outbounds[].tag "${configPath}10_ipv4_outbounds.json" | awk '{print ""NR""":"$0}' | grep "${tag}" | awk -F "[:]" '{print $1}' | head -1)
        if [[ ${ipv6OutIndex} -gt 0 ]]; then
            routing=$(jq -r 'del(.outbounds['$((ipv6OutIndex - 1))'])' "${configPath}10_ipv4_outbounds.json")
            echo "${routing}" | jq . >"${configPath}10_ipv4_outbounds.json"
        fi
    fi
}

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
            outbounds=$(jq -r '.outbounds = [{"protocol":"freedom","settings":{"domainStrategy":"UseIPv6"},"tag":"IPv6-out"},{"protocol":"freedom","settings":{"domainStrategy":"UseIPv4"},"tag":"IPv4-out"}] + .outbounds + [{"protocol":"blackhole","tag":"blackhole-out"}]' "${configPath}10_ipv4_outbounds.json")
        else
            outbounds=$(jq -r '.outbounds = [{"protocol":"freedom","settings":{"domainStrategy":"UseIPv4"},"tag":"IPv4-out"},{"protocol":"freedom","settings":{"domainStrategy":"UseIPv6"},"tag":"IPv6-out"}] + .outbounds + [{"protocol":"blackhole","tag":"blackhole-out"}]' "${configPath}10_ipv4_outbounds.json")
        fi
        echo "${outbounds}" | jq . >"${configPath}10_ipv4_outbounds.json"
    fi
    reloadCore
}
