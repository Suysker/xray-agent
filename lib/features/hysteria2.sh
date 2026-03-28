xray_agent_apply_hysteria2_feature_patches() {
    local target_path="$1"

    if declare -F xray_agent_apply_finalmask_patch >/dev/null 2>&1; then
        xray_agent_apply_finalmask_patch "${target_path}"
    fi
}
