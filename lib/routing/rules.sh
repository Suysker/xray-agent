if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

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
                    routing=$(jq -r 'del(.routing.rules['$((index - 1))'])' "${configPath}09_routing.json")
                    echo "${routing}" | jq . >"${configPath}09_routing.json"
                fi
            done
        fi
    fi
}
