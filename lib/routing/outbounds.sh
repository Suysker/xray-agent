if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

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
