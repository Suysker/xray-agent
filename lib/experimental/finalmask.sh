if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_apply_finalmask_patch() {
    local target_path="$1"
    if [[ "${XRAY_AGENT_ENABLE_FINALMASK:-false}" != "true" ]]; then
        return 0
    fi

    local finalmask_mode="${XRAY_AGENT_FINALMASK_MODE:-header}"
    local quic_mask="${XRAY_AGENT_FINALMASK_QUIC_PARAMS:-off}"

    jq --arg finalmaskMode "${finalmask_mode}" --arg quicMask "${quic_mask}" '
      .inbounds[0].streamSettings.finalmask = {
        enabled: true,
        mode: $finalmaskMode,
        quicParams: $quicMask
      }' "${target_path}" >"${target_path}.tmp" &&
        mv "${target_path}.tmp" "${target_path}"
}
