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
    export XRAY_WARP_INTERFACE="${XRAY_WARP_INTERFACE:-WARP}"
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

xray_agent_default_outbounds_json() {
    xray_agent_load_routing_profile "ipv4_default"
    local outbound_jsons=()
    local outbound_tag
    while IFS= read -r outbound_tag; do
        outbound_jsons+=("$(xray_agent_render_outbound_by_tag "${outbound_tag}")")
    done < <(echo "${XRAY_AGENT_ROUTING_OUTBOUND_ORDER}" | tr ',' '\n')
    printf '%s\n' "${outbound_jsons[@]}" | jq -sc '.'
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
            export XRAY_ROUTING_DOMAINS_JSON
            export XRAY_ROUTING_OUTBOUND_TAG="IPv6-out"
            XRAY_ROUTING_DOMAINS_JSON="$(xray_agent_geosite_domains_json "${domainList}")"
            xray_agent_append_routing_rule_json "${configPath}09_routing.json" "$(xray_agent_domain_outbound_rule_json "${XRAY_ROUTING_DOMAINS_JSON}" "${XRAY_ROUTING_OUTBOUND_TAG}")"
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
            XRAY_WARP_INTERFACE="${warpinterface}"
            xray_agent_append_outbound_by_tag "${configPath}10_ipv4_outbounds.json" "warp-out"
        elif [[ "${warpStatus}" == "4" ]]; then
            unInstallOutbounds cn-out
            XRAY_WARP_INTERFACE="${warpinterface}"
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
            export XRAY_ROUTING_DOMAINS_JSON
            export XRAY_ROUTING_OUTBOUND_TAG="blackhole-out"
            XRAY_ROUTING_DOMAINS_JSON="$(xray_agent_geosite_domains_json "${domainList}")"
            xray_agent_append_routing_rule_json "${configPath}09_routing.json" "$(xray_agent_domain_outbound_rule_json "${XRAY_ROUTING_DOMAINS_JSON}" "${XRAY_ROUTING_OUTBOUND_TAG}")"
        fi
    elif [[ "${blacklistStatus}" == "2" ]]; then
        unInstallRouting blackhole-out outboundTag
    elif [[ "${blacklistStatus}" == "4" ]]; then
        if [[ -f "${configPath}09_routing.json" ]]; then
            unInstallRouting cn-blackhole outboundTag
            xray_agent_append_routing_rule_json "${configPath}09_routing.json" "$(xray_agent_cn_blackhole_rule_json)"
        fi
        unInstallOutbounds cn-blackhole
        xray_agent_append_outbound_by_tag "${configPath}10_ipv4_outbounds.json" "cn-blackhole"
        unInstallRouting cn-out outboundTag
        unInstallOutbounds cn-out
    elif [[ "${blacklistStatus}" == "5" ]]; then
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
