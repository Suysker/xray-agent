xray_agent_apply_vless_encryption_patch() {
    local target_path="$1"
    if [[ "${XRAY_AGENT_ENABLE_VLESS_ENCRYPTION}" != "true" ]]; then
        return 0
    fi

    local encryption_mode="${XRAY_AGENT_VLESS_ENCRYPTION_MODE:-mlkem768}"
    jq --arg encryptionMode "${encryption_mode}" '
      .inbounds[0].settings.vlessEncryption = {
        enabled: true,
        mode: $encryptionMode
      }' "${target_path}" >"${target_path}.tmp" &&
        mv "${target_path}.tmp" "${target_path}"
}
