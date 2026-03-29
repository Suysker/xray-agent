if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_apply_browser_headers_patch() {
    local target_path="$1"
    local headers_json
    [[ -f "${target_path}" ]] || return 0
    headers_json="$(xray_agent_default_xhttp_headers_json)"

    jq --argjson headers "${headers_json}" '
      .inbounds[0].streamSettings.xhttpSettings.headers = $headers' "${target_path}" >"${target_path}.tmp" &&
        mv "${target_path}.tmp" "${target_path}"
}

xray_agent_browser_dialer_message() {
    echoContent yellow " ---> Browser Dialer 适用于本地模式，需要用户显式打开浏览器并访问 localhost:8080"
    echoContent yellow " ---> 该模式默认不启用，建议配合 local_tun 使用并自行规避回环"
}
