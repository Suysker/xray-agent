#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

XRAY_AGENT_NETWORK_POLICY_IPV4_PRIORITY="${XRAY_AGENT_NETWORK_POLICY_IPV4_PRIORITY:-32040}"
XRAY_AGENT_NETWORK_POLICY_IPV6_PRIORITY="${XRAY_AGENT_NETWORK_POLICY_IPV6_PRIORITY:-32060}"

xray_agent_network_policy_state_path() {
    printf '%s/state/network-ownership.json\n' "${XRAY_AGENT_ETC_DIR:-/etc/xray-agent}"
}

xray_agent_network_policy_ip() {
    ip "$@"
}

xray_agent_network_policy_current_json() {
    local state_path
    state_path="$(xray_agent_network_policy_state_path)"
    if [[ -r "${state_path}" ]] && jq -e '.schemaVersion == 1 and (.rules | type == "array")' "${state_path}" >/dev/null 2>&1; then
        jq -c . "${state_path}"
    else
        jq -nc '{schemaVersion:1,rules:[]}'
    fi
}

xray_agent_network_policy_rule_line() {
    local family="$1"
    local priority="$2"
    xray_agent_network_policy_ip -"${family}" rule show 2>/dev/null | awk -v priority="${priority}:" '$1 == priority {print; exit}'
}

xray_agent_network_policy_rule_matches() {
    local family="$1"
    local priority="$2"
    local source_cidr="$3"
    local line
    line="$(xray_agent_network_policy_rule_line "${family}" "${priority}")"
    [[ -n "${line}" && " ${line} " == *" from ${source_cidr} "* && " ${line} " == *" lookup main "* ]]
}

xray_agent_network_policy_apply_rule() {
    local family="$1"
    local priority="$2"
    local source_cidr="$3"
    local existing_line
    existing_line="$(xray_agent_network_policy_rule_line "${family}" "${priority}")"
    if [[ -n "${existing_line}" ]]; then
        xray_agent_network_policy_rule_matches "${family}" "${priority}" "${source_cidr}"
        return $?
    fi
    xray_agent_network_policy_ip -"${family}" rule add priority "${priority}" from "${source_cidr}" lookup main
}

xray_agent_network_policy_remove_rule() {
    local family="$1"
    local priority="$2"
    local source_cidr="$3"
    if xray_agent_network_policy_rule_matches "${family}" "${priority}" "${source_cidr}"; then
        xray_agent_network_policy_ip -"${family}" rule del priority "${priority}" from "${source_cidr}" lookup main
    fi
}

xray_agent_network_policy_desired_json() {
    local egress_policy_json="$1"
    local selected_ids_json rules_json='[]'
    xray_agent_detect_network_capabilities
    selected_ids_json="$(jq -c '[.defaultTcpEgress,.defaultUdpEgress,.rules[]?.tcpEgress,.rules[]?.udpEgress] | map(select(type == "string")) | unique' <<<"${egress_policy_json}")" || return 1
    if [[ "${warpDefaultIPv4}" == "true" ]] && jq -e 'any(.[]; . == "native-ipv4-out" or . == "native-auto-out")' <<<"${selected_ids_json}" >/dev/null; then
        [[ -n "${nativeIPv4Address}" ]] || return 1
        rules_json="$(jq -nc --argjson rules "${rules_json}" --argjson priority "${XRAY_AGENT_NETWORK_POLICY_IPV4_PRIORITY}" --arg source "${nativeIPv4Address}/32" '$rules + [{family:4,priority:$priority,source:$source,table:"main"}]')" || return 1
    fi
    if [[ "${warpDefaultIPv6}" == "true" ]] && jq -e 'any(.[]; . == "native-ipv6-out" or . == "native-auto-out")' <<<"${selected_ids_json}" >/dev/null; then
        [[ -n "${nativeIPv6Address}" ]] || return 1
        rules_json="$(jq -nc --argjson rules "${rules_json}" --argjson priority "${XRAY_AGENT_NETWORK_POLICY_IPV6_PRIORITY}" --arg source "${nativeIPv6Address}/128" '$rules + [{family:6,priority:$priority,source:$source,table:"main"}]')" || return 1
    fi
    jq -nc --argjson rules "${rules_json}" '{schemaVersion:1,rules:$rules}'
}

xray_agent_network_policy_write_state() {
    local state_json="$1"
    local state_path temp_path
    state_path="$(xray_agent_network_policy_state_path)"
    mkdir -p "$(dirname "${state_path}")"
    temp_path="${state_path}.tmp"
    printf '%s\n' "${state_json}" | jq . >"${temp_path}" || {
        rm -f -- "${temp_path}"
        return 1
    }
    mv "${temp_path}" "${state_path}"
}

xray_agent_network_policy_reconcile_json() {
    local desired_json="$1"
    local current_json row family priority source existing_line newly_added_json='[]'
    current_json="$(xray_agent_network_policy_current_json)" || return 1

    while IFS= read -r row; do
        family="$(jq -r '.family' <<<"${row}")"
        priority="$(jq -r '.priority' <<<"${row}")"
        source="$(jq -r '.source' <<<"${row}")"
        if jq -e --argjson rule "${row}" 'any(.rules[]; . == $rule)' <<<"${current_json}" >/dev/null; then
            if ! xray_agent_network_policy_apply_rule "${family}" "${priority}" "${source}"; then
                while IFS= read -r row; do
                    xray_agent_network_policy_remove_rule "$(jq -r '.family' <<<"${row}")" "$(jq -r '.priority' <<<"${row}")" "$(jq -r '.source' <<<"${row}")" || true
                done < <(jq -c '.[]' <<<"${newly_added_json}")
                return 1
            fi
            continue
        fi
        existing_line="$(xray_agent_network_policy_rule_line "${family}" "${priority}")"
        if [[ -n "${existing_line}" ]] || ! xray_agent_network_policy_apply_rule "${family}" "${priority}" "${source}"; then
            while IFS= read -r row; do
                xray_agent_network_policy_remove_rule "$(jq -r '.family' <<<"${row}")" "$(jq -r '.priority' <<<"${row}")" "$(jq -r '.source' <<<"${row}")" || true
            done < <(jq -c '.[]' <<<"${newly_added_json}")
            return 1
        fi
        newly_added_json="$(jq -nc --argjson rules "${newly_added_json}" --argjson rule "${row}" '$rules + [$rule]')" || return 1
    done < <(jq -c '.rules[]' <<<"${desired_json}")

    while IFS= read -r row; do
        if ! jq -e --argjson rule "${row}" 'any(.rules[]; . == $rule)' <<<"${desired_json}" >/dev/null; then
            family="$(jq -r '.family' <<<"${row}")"
            priority="$(jq -r '.priority' <<<"${row}")"
            source="$(jq -r '.source' <<<"${row}")"
            if ! xray_agent_network_policy_remove_rule "${family}" "${priority}" "${source}"; then
                while IFS= read -r row; do
                    xray_agent_network_policy_remove_rule "$(jq -r '.family' <<<"${row}")" "$(jq -r '.priority' <<<"${row}")" "$(jq -r '.source' <<<"${row}")" || true
                done < <(jq -c '.[]' <<<"${newly_added_json}")
                return 1
            fi
        fi
    done < <(jq -c '.rules[]' <<<"${current_json}")

    xray_agent_network_policy_write_state "${desired_json}"
}

xray_agent_network_policy_reconcile_egress_policy() {
    local egress_policy_json="$1"
    local desired_json
    desired_json="$(xray_agent_network_policy_desired_json "${egress_policy_json}")" || return 1
    xray_agent_network_policy_reconcile_json "${desired_json}"
}

xray_agent_network_policy_cleanup() {
    xray_agent_network_policy_reconcile_json '{"schemaVersion":1,"rules":[]}'
}
