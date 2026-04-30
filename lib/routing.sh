#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_reset_routing_profile() {
    XRAY_AGENT_ROUTING_PROFILE_NAME=
    XRAY_AGENT_ROUTING_DOMAIN_STRATEGY=
    XRAY_AGENT_ROUTING_DNS_QUERY_STRATEGY=
    XRAY_AGENT_ROUTING_OUTBOUND_ORDER=
    XRAY_AGENT_ROUTING_RULE_MODE=
}

xray_agent_load_routing_profile() {
    local profile_path="${XRAY_AGENT_PROFILE_DIR}/routing/$1.profile"
    local key value
    if [[ ! -r "${profile_path}" ]]; then
        return 1
    fi

    xray_agent_reset_routing_profile
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        case "${key}" in
            name) XRAY_AGENT_ROUTING_PROFILE_NAME="${value}" ;;
            domain_strategy) XRAY_AGENT_ROUTING_DOMAIN_STRATEGY="${value}" ;;
            dns_query_strategy) XRAY_AGENT_ROUTING_DNS_QUERY_STRATEGY="${value}" ;;
            outbound_order) XRAY_AGENT_ROUTING_OUTBOUND_ORDER="${value}" ;;
            rule_mode) XRAY_AGENT_ROUTING_RULE_MODE="${value}" ;;
        esac
    done <"${profile_path}"
}

xray_agent_render_outbound_template() {
    local template_name="$1"
    local template_path="${XRAY_AGENT_PROJECT_ROOT}/templates/xray/outbounds/${template_name}"
    export XRAY_WARP_INTERFACE="${XRAY_WARP_INTERFACE:-${warpInterface:-WARP}}"
    export XRAY_WARP_DOMAIN_STRATEGY="${XRAY_WARP_DOMAIN_STRATEGY:-$(xray_agent_warp_domain_strategy)}"
    xray_agent_render_template_stdout "${template_path}"
}

xray_agent_render_outbound_by_tag() {
    case "$1" in
        IPv4-out) xray_agent_render_outbound_template "freedom_ipv4.json.tpl" ;;
        IPv6-out) xray_agent_render_outbound_template "freedom_ipv6.json.tpl" ;;
        blackhole-out) xray_agent_render_outbound_template "blackhole.json.tpl" ;;
        warp-out) xray_agent_render_outbound_template "warp_out.json.tpl" ;;
        cn-out) xray_agent_render_outbound_template "cn_out.json.tpl" ;;
        cn-blackhole) xray_agent_render_outbound_template "cn_blackhole.json.tpl" ;;
    esac
}

xray_agent_default_routing_profile_name() {
    xray_agent_detect_network_capabilities
    if [[ "${routeIPv4}" != "true" && "${routeIPv6}" == "true" ]]; then
        printf 'ipv6_first\n'
    else
        printf 'ipv4_default\n'
    fi
}

xray_agent_outbounds_json_for_profile() {
    local profile_name="$1"
    xray_agent_load_routing_profile "${profile_name}"
    local outbound_jsons=()
    local outbound_tag
    while IFS= read -r outbound_tag; do
        outbound_jsons+=("$(xray_agent_render_outbound_by_tag "${outbound_tag}")")
    done < <(echo "${XRAY_AGENT_ROUTING_OUTBOUND_ORDER}" | tr ',' '\n')
    printf '%s\n' "${outbound_jsons[@]}" | jq -sc '.'
}

xray_agent_default_outbounds_json() {
    xray_agent_outbounds_json_for_profile "$(xray_agent_default_routing_profile_name)"
}

xray_agent_default_routing_domain_strategy() {
    xray_agent_load_routing_profile "$(xray_agent_default_routing_profile_name)"
    printf '%s\n' "${XRAY_AGENT_ROUTING_DOMAIN_STRATEGY:-AsIs}"
}

xray_agent_default_dns_query_strategy() {
    local profile_name
    profile_name="$(xray_agent_default_routing_profile_name)"
    if [[ "${profile_name}" == "ipv6_first" ]]; then
        printf 'UseIPv6\n'
    else
        xray_agent_load_routing_profile "${profile_name}"
        printf '%s\n' "${XRAY_AGENT_ROUTING_DNS_QUERY_STRATEGY:-UseIP}"
    fi
}

xray_agent_default_routing_rules_json() {
    jq -nc '[]'
}

xray_agent_default_dns_servers_json() {
    jq -nc '["localhost"]'
}

xray_agent_geosite_domains_json() {
    local domain_list="$1"
    jq -nc --arg domainList "${domain_list}" '$domainList | split(",") | map(select(length > 0)) | map("geosite:" + .)'
}

xray_agent_domain_outbound_rule_json() {
    local domains_json="$1"
    local outbound_tag="$2"
    jq -nc --argjson domains "${domains_json}" --arg outboundTag "${outbound_tag}" '{type:"field",domain:$domains,outboundTag:$outboundTag}'
}

xray_agent_cn_out_rule_json() {
    jq -nc '{type:"field",domain:["geosite:cn"],ip:["geoip:cn"],outboundTag:"cn-out"}'
}

xray_agent_cn_blackhole_rule_json() {
    jq -nc '{type:"field",ip:["geoip:cn"],outboundTag:"cn-blackhole"}'
}

xray_agent_append_routing_rule_json() {
    local target_file="$1"
    local rule_json="$2"
    xray_agent_json_update_file "${target_file}" '.routing.rules += [$rule]' --argjson rule "${rule_json}"
}

xray_agent_append_outbound_by_tag() {
    local target_file="$1"
    local outbound_tag="$2"
    local outbound_json
    outbound_json="$(xray_agent_render_outbound_by_tag "${outbound_tag}")"
    xray_agent_json_update_file "${target_file}" '.outbounds += [$outbound]' --argjson outbound "${outbound_json}"
}

xray_agent_apply_routing_profile() {
    local profile_name="$1"
    xray_agent_load_routing_profile "${profile_name}" || return 1
    local outbound_jsons=()
    local outbound_tag
    while IFS= read -r outbound_tag; do
        outbound_jsons+=("$(xray_agent_render_outbound_by_tag "${outbound_tag}")")
    done < <(echo "${XRAY_AGENT_ROUTING_OUTBOUND_ORDER}" | tr ',' '\n')
    printf '%s\n' "${outbound_jsons[@]}" | jq -sc '{"outbounds": .}' >"${configPath}10_ipv4_outbounds.json"
}

xray_agent_routing_rule_count() {
    local outbound_tag="$1"
    [[ -f "${configPath}09_routing.json" ]] || {
        printf '0\n'
        return 0
    }
    jq -r --arg outboundTag "${outbound_tag}" '[.routing.rules[]? | select(.outboundTag == $outboundTag)] | length' "${configPath}09_routing.json" 2>/dev/null | tr -d '\r'
}

xray_agent_outbound_exists() {
    local outbound_tag="$1"
    [[ -f "${configPath}10_ipv4_outbounds.json" ]] || return 1
    jq -e --arg outboundTag "${outbound_tag}" 'any(.outbounds[]?; .tag == $outboundTag)' "${configPath}10_ipv4_outbounds.json" >/dev/null 2>&1
}

xray_agent_outbound_status_label() {
    if xray_agent_outbound_exists "$1"; then
        printf '存在\n'
    else
        printf '缺失\n'
    fi
}

xray_agent_routing_status_summary() {
    echoContent skyBlue "-------------------------路由规则状态-----------------------------"
    echoContent yellow "IPv6域名规则: $(xray_agent_routing_rule_count IPv6-out)"
    echoContent yellow "WARP域名规则: $(xray_agent_routing_rule_count warp-out)"
    echoContent yellow "黑名单规则: $(xray_agent_routing_rule_count blackhole-out)"
    echoContent yellow "CN WARP规则: $(xray_agent_routing_rule_count cn-out)，outbound=$(xray_agent_outbound_status_label cn-out)"
    echoContent yellow "CN 阻断规则: $(xray_agent_routing_rule_count cn-blackhole)，outbound=$(xray_agent_outbound_status_label cn-blackhole)"
}

ipv6Routing() {
    local selected action domainList
    local -a actions
    xray_agent_tool_status_header "IPv4/IPv6出站策略"
    xray_agent_network_summary
    xray_agent_routing_status_summary

    if [[ "${routeIPv4}" != "true" && "${routeIPv6}" != "true" ]]; then
        echoContent red " ---> 当前未检测到 IPv4/IPv6 默认路由，不能新增出站策略。"
        return 0
    fi

    echoContent skyBlue "-------------------------IPv4/IPv6出站策略-----------------------------"
    echoContent yellow "当前出站栈: $(xray_agent_route_mode_label)"

    if [[ "${routeIPv6}" == "true" ]]; then
        actions+=("add_ipv6_domain")
        echoContent yellow "${#actions[@]}.添加域名到IPv6出站"
    else
        echoContent yellow "提示: 当前没有 IPv6 默认路由，不显示 IPv6 新增/优先动作。"
    fi

    actions+=("remove_ipv6_domain")
    echoContent yellow "${#actions[@]}.卸载IPv6域名出站"
    actions+=("show_ipv6_domain")
    echoContent yellow "${#actions[@]}.查看IPv6出站域名"

    if [[ "${routeIPv4}" == "true" && "${routeIPv6}" == "true" ]]; then
        actions+=("prefer_ipv6")
        echoContent yellow "${#actions[@]}.全局IPv6优先"
        actions+=("prefer_ipv4")
        echoContent yellow "${#actions[@]}.全局IPv4优先"
    elif [[ "${routeIPv6}" == "true" ]]; then
        echoContent yellow "提示: 当前为 IPv6-only，默认基线已使用 IPv6 出站。"
    fi

    read -r -p "请选择:" selected
    if ! [[ "${selected}" =~ ^[0-9]+$ ]] || [[ "${selected}" -lt 1 || "${selected}" -gt "${#actions[@]}" ]]; then
        echoContent red " ---> 无效选择"
        return 0
    fi
    action="${actions[$((selected - 1))]}"

    if [[ "${action}" == "add_ipv6_domain" ]]; then
        read -r -p "请按照上面示例录入域名:" domainList
        echoContent yellow "将把以下 geosite 域名路由到 IPv6-out: ${domainList}"
        xray_agent_confirm "确认继续？[y/N]:" "n" || return 0
        if [[ -f "${configPath}09_routing.json" ]]; then
            unInstallRouting IPv6-out outboundTag
            export XRAY_ROUTING_DOMAINS_JSON
            export XRAY_ROUTING_OUTBOUND_TAG="IPv6-out"
            XRAY_ROUTING_DOMAINS_JSON="$(xray_agent_geosite_domains_json "${domainList}")"
            xray_agent_append_routing_rule_json "${configPath}09_routing.json" "$(xray_agent_domain_outbound_rule_json "${XRAY_ROUTING_DOMAINS_JSON}" "${XRAY_ROUTING_OUTBOUND_TAG}")"
        fi
    elif [[ "${action}" == "remove_ipv6_domain" ]]; then
        echoContent yellow "将移除 IPv6-out 域名规则。"
        xray_agent_confirm "确认继续？[y/N]:" "n" || return 0
        unInstallRouting IPv6-out outboundTag
    elif [[ "${action}" == "show_ipv6_domain" ]]; then
        jq -r -c '.routing.rules[]|select (.outboundTag=="IPv6-out")|.domain' "${configPath}09_routing.json" | jq -r
        return 0
    fi

    if [[ "${action}" == "add_ipv6_domain" || "${action}" == "prefer_ipv6" || "${action}" == "prefer_ipv4" ]]; then
        if [[ "${action}" == "prefer_ipv6" || "${action}" == "prefer_ipv4" ]]; then
            echoContent yellow "将重写基础 outbounds 为 $([[ "${action}" == "prefer_ipv6" ]] && printf 'IPv6优先' || printf 'IPv4优先')。"
            xray_agent_confirm "确认继续？[y/N]:" "n" || return 0
        fi
        unInstallOutbounds IPv4-out
        unInstallOutbounds IPv6-out
        unInstallOutbounds blackhole-out
        if [[ "${action}" == "prefer_ipv6" ]]; then
            xray_agent_apply_routing_profile "ipv6_first"
        else
            xray_agent_apply_routing_profile "ipv4_first"
        fi
    fi
    reloadCore
}

warpRouting() {
    xray_agent_tool_status_header "WARP分流"
    xray_agent_network_summary
    xray_agent_routing_status_summary
    warpinterface="$(xray_agent_detect_usable_warp_interface || true)"
    if [[ -z "${warpinterface}" ]]; then
        xray_agent_error " ---> 未安装或未开启，请使用脚本安装或开启"
    fi
    case "${warpMode:-none}" in
        default_*)
            echoContent yellow "提示: 当前系统默认路由已经走 WARP，下面的规则只会让 Xray 显式绑定该接口，不会改变系统默认路由。"
            ;;
    esac
    if [[ "${warpHasIPv4}" == "true" && "${warpHasIPv6}" == "true" ]]; then
        echoContent yellow "WARP出站能力: IPv4/IPv6 双栈，domainStrategy=UseIP"
    elif [[ "${warpHasIPv4}" == "true" ]]; then
        echoContent yellow "WARP出站能力: IPv4-only，domainStrategy=UseIPv4"
    elif [[ "${warpHasIPv6}" == "true" ]]; then
        echoContent yellow "WARP出站能力: IPv6-only，domainStrategy=UseIPv6"
    else
        xray_agent_error " ---> WARP接口没有可用 IPv4/IPv6 地址"
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
            echoContent yellow "将新增 WARP outbound，接口=${warpinterface}，domainStrategy=$(xray_agent_warp_domain_strategy)。"
            xray_agent_confirm "确认继续？[y/N]:" "n" || return 0
            unInstallOutbounds warp-out
            XRAY_WARP_INTERFACE="${warpinterface}"
            XRAY_WARP_DOMAIN_STRATEGY="$(xray_agent_warp_domain_strategy)"
            xray_agent_append_outbound_by_tag "${configPath}10_ipv4_outbounds.json" "warp-out"
        elif [[ "${warpStatus}" == "4" ]]; then
            echoContent yellow "将把 geosite:cn/geoip:cn 分流到 WARP，并移除 CN 阻断规则。"
            xray_agent_confirm "确认继续？[y/N]:" "n" || return 0
            unInstallOutbounds cn-out
            XRAY_WARP_INTERFACE="${warpinterface}"
            XRAY_WARP_DOMAIN_STRATEGY="$(xray_agent_warp_domain_strategy)"
            xray_agent_append_outbound_by_tag "${configPath}10_ipv4_outbounds.json" "cn-out"
        fi
        if [[ "${warpStatus}" == "1" ]]; then
            read -r -p "请按照上面示例录入域名:" domainList
            if [[ -f "${configPath}09_routing.json" ]]; then
                unInstallRouting warp-out outboundTag
                export XRAY_ROUTING_DOMAINS_JSON
                export XRAY_ROUTING_OUTBOUND_TAG="warp-out"
                XRAY_ROUTING_DOMAINS_JSON="$(xray_agent_geosite_domains_json "${domainList}")"
                xray_agent_append_routing_rule_json "${configPath}09_routing.json" "$(xray_agent_domain_outbound_rule_json "${XRAY_ROUTING_DOMAINS_JSON}" "${XRAY_ROUTING_OUTBOUND_TAG}")"
            fi
        elif [[ "${warpStatus}" == "4" ]]; then
            if [[ -f "${configPath}09_routing.json" ]]; then
                unInstallRouting cn-out outboundTag
                xray_agent_append_routing_rule_json "${configPath}09_routing.json" "$(xray_agent_cn_out_rule_json)"
            fi
            unInstallRouting cn-blackhole outboundTag
            unInstallOutbounds cn-blackhole
        fi
    elif [[ "${warpStatus}" == "2" ]]; then
        echoContent yellow "将卸载 WARP 域名分流规则和 outbound。"
        xray_agent_confirm "确认继续？[y/N]:" "n" || return 0
        unInstallRouting warp-out outboundTag
        unInstallOutbounds warp-out
    elif [[ "${warpStatus}" == "5" ]]; then
        echoContent yellow "将卸载 CN WARP 分流规则和 outbound。"
        xray_agent_confirm "确认继续？[y/N]:" "n" || return 0
        unInstallRouting cn-out outboundTag
        unInstallOutbounds cn-out
    fi
    reloadCore
}

blacklist() {
    xray_agent_tool_status_header "黑名单与CN阻断"
    xray_agent_routing_status_summary
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
        echoContent yellow "将把以下 geosite 域名加入 blackhole-out: ${domainList}"
        xray_agent_confirm "确认继续？[y/N]:" "n" || return 0
        if [[ -f "${configPath}09_routing.json" ]]; then
            unInstallRouting blackhole-out outboundTag
            export XRAY_ROUTING_DOMAINS_JSON
            export XRAY_ROUTING_OUTBOUND_TAG="blackhole-out"
            XRAY_ROUTING_DOMAINS_JSON="$(xray_agent_geosite_domains_json "${domainList}")"
            xray_agent_append_routing_rule_json "${configPath}09_routing.json" "$(xray_agent_domain_outbound_rule_json "${XRAY_ROUTING_DOMAINS_JSON}" "${XRAY_ROUTING_OUTBOUND_TAG}")"
        fi
    elif [[ "${blacklistStatus}" == "2" ]]; then
        echoContent yellow "将删除全部 blackhole-out 域名黑名单规则。"
        xray_agent_confirm "确认继续？[y/N]:" "n" || return 0
        unInstallRouting blackhole-out outboundTag
    elif [[ "${blacklistStatus}" == "4" ]]; then
        echoContent yellow "将阻断 geoip:cn，并移除 CN WARP 分流规则。"
        xray_agent_confirm "确认继续？[y/N]:" "n" || return 0
        if [[ -f "${configPath}09_routing.json" ]]; then
            unInstallRouting cn-blackhole outboundTag
            xray_agent_append_routing_rule_json "${configPath}09_routing.json" "$(xray_agent_cn_blackhole_rule_json)"
        fi
        unInstallOutbounds cn-blackhole
        xray_agent_append_outbound_by_tag "${configPath}10_ipv4_outbounds.json" "cn-blackhole"
        unInstallRouting cn-out outboundTag
        unInstallOutbounds cn-out
    elif [[ "${blacklistStatus}" == "5" ]]; then
        echoContent yellow "将卸载 CN IP 阻断规则。"
        xray_agent_confirm "确认继续？[y/N]:" "n" || return 0
        unInstallRouting cn-blackhole outboundTag
    fi
    reloadCore
}

unInstallOutbounds() {
    local tag=$1
    if grep -q "${tag}" "${configPath}10_ipv4_outbounds.json"; then
        local ipv6OutIndex
        ipv6OutIndex=$(jq .outbounds[].tag "${configPath}10_ipv4_outbounds.json" | awk '{print ""NR""":"$0}' | grep "${tag}" | awk -F "[:]" '{print $1}' | head -1)
        if [[ ${ipv6OutIndex} -gt 0 ]]; then
            xray_agent_json_update_file "${configPath}10_ipv4_outbounds.json" "del(.outbounds[$((ipv6OutIndex - 1))])"
        fi
    fi
}

unInstallRouting() {
    local tag="$1"
    local type="$2"
    local protocol="${3:-}"
    if [[ -f "${configPath}09_routing.json" ]]; then
        local routing
        if grep -q "${tag}" "${configPath}09_routing.json" && grep -q "${type}" "${configPath}09_routing.json"; then
            local index=0
            jq -c .routing.rules[] "${configPath}09_routing.json" | while read -r line; do
                index=$((index + 1))
                local delStatus=0
                if [[ "${type}" == "outboundTag" ]] && echo "${line}" | jq .outboundTag | grep -q "${tag}"; then
                    delStatus=1
                elif [[ "${type}" == "inboundTag" ]] && echo "${line}" | jq .inboundTag | grep -q "${tag}"; then
                    delStatus=1
                fi
                if [[ -n "${protocol}" ]] && echo "${line}" | jq .protocol | grep -q "${protocol}"; then
                    delStatus=1
                elif [[ -z "${protocol}" ]] && [[ $(echo "${line}" | jq .protocol) != "null" ]]; then
                    delStatus=0
                fi
                if [[ ${delStatus} == 1 ]]; then
                    xray_agent_json_update_file "${configPath}09_routing.json" "del(.routing.rules[$((index - 1))])"
                fi
            done
        fi
    fi
}
