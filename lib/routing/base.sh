if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
    local template_content
    template_content=$(cat "${template_path}")
    eval "cat <<__XRAY_AGENT_OUTBOUND__
${template_content}
__XRAY_AGENT_OUTBOUND__"
}

xray_agent_render_outbound_by_tag() {
    case "$1" in
        IPv4-out) xray_agent_render_outbound_template "freedom_ipv4.json.tpl" ;;
        IPv6-out) xray_agent_render_outbound_template "freedom_ipv6.json.tpl" ;;
        blackhole-out) xray_agent_render_outbound_template "blackhole.json.tpl" ;;
        warp-out) xray_agent_render_outbound_template "warp_out.json.tpl" ;;
        cn-out) xray_agent_render_outbound_template "cn_out.json.tpl" ;;
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
