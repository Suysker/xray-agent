if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_trim_quotes() {
    local value="$1"
    value="${value%\"}"
    value="${value#\"}"
    echo "${value}"
}

xray_agent_urlencode() {
    local value="$1"
    value="${value//'%'/%25}"
    value="${value//' '/%20}"
    value="${value//\"/%22}"
    value="${value//'#'/%23}"
    value="${value//'&'/%26}"
    value="${value//'+'/%2B}"
    value="${value//'/'/%2F}"
    value="${value//':'/%3A}"
    value="${value//';'/%3B}"
    value="${value//'='/%3D}"
    value="${value//'?'/%3F}"
    value="${value//'@'/%40}"
    echo "${value}"
}

xray_agent_ensure_dir() {
    mkdir -p "$1"
}

xray_agent_json_write() {
    local target_path="$1"
    local json_content="$2"
    printf '%s\n' "${json_content}" | jq . >"${target_path}"
}

xray_agent_render_template() {
    local template_path="$1"
    local output_path="$2"
    local template_content
    template_content=$(cat "${template_path}")
    eval "cat <<__XRAY_AGENT_TEMPLATE__
${template_content}
__XRAY_AGENT_TEMPLATE__" >"${output_path}"
}

xray_agent_render_json_template() {
    xray_agent_render_template "$1" "$2"
}

xray_agent_apply_json_patch() {
    local target_path="$1"
    local jq_filter="$2"
    local temp_path="${target_path}.tmp"
    jq "${jq_filter}" "${target_path}" >"${temp_path}" && mv "${temp_path}" "${target_path}"
}

xray_agent_join_by() {
    local separator="$1"
    shift
    local first="$1"
    shift || true
    printf '%s' "${first}"
    for item in "$@"; do
        printf '%s%s' "${separator}" "${item}"
    done
}
