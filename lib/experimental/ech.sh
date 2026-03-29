if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_apply_ech_patch() {
    local target_path="$1"
    if [[ "${XRAY_AGENT_ENABLE_ECH:-false}" != "true" ]]; then
        return 0
    fi

    local ech_config="${XRAY_AGENT_ECH_CONFIG:-example-ech-config}"
    jq --arg echConfig "${ech_config}" '
      .inbounds[0].streamSettings.tlsSettings.echConfigList = [$echConfig]' "${target_path}" >"${target_path}.tmp" &&
        mv "${target_path}.tmp" "${target_path}"
}
