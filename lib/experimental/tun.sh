if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_apply_tun_feature_patches() {
    local tun_path="$1"
    local routing_path="$2"
    local process_names="${XRAY_AGENT_TUN_PROCESS_NAMES:-curl,wget,bash}"

    jq --arg processNames "${process_names}" '
      .inbounds[0].settings.process = ($processNames | split(","))' "${tun_path}" >"${tun_path}.tmp" &&
        mv "${tun_path}.tmp" "${tun_path}"

    jq --arg processNames "${process_names}" '
      .routing.rules = [{
        type: "field",
        process_name: ($processNames | split(",")),
        outboundTag: "proxy"
      }]' "${routing_path}" >"${routing_path}.tmp" &&
        mv "${routing_path}.tmp" "${routing_path}"
}

xray_agent_render_local_tun_profile() {
    xray_agent_render_common_xray_configs
    export XRAY_INBOUND_TAG="TUN"
    export XRAY_TUN_MTU="1500"
    export XRAY_SNIFFING_JSON
    XRAY_SNIFFING_JSON="$(xray_agent_default_sniffing_json)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/20_tun.json.tpl" "${configPath}20_TUN_inbounds.json"
    xray_agent_apply_tun_feature_patches "${configPath}20_TUN_inbounds.json" "${configPath}09_routing.json"
}
