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
