xray_agent_apply_trusted_xff_patch() {
    local target_path="$1"
    local trusted_source="${XRAY_AGENT_TRUSTED_X_FORWARDED_FOR:-127.0.0.1}"
    xray_agent_apply_trusted_x_forwarded_for "${target_path}" "${trusted_source}"
}
