#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

XRAY_AGENT_VERSION="${XRAY_AGENT_VERSION:-$(tr -d '\r\n' <"${XRAY_AGENT_PROJECT_ROOT}/VERSION" 2>/dev/null)}"
XRAY_AGENT_PROJECT_NAME="${XRAY_AGENT_PROJECT_NAME:-xray-agent}"
XRAY_AGENT_PROJECT_OWNER="${XRAY_AGENT_PROJECT_OWNER:-Suysker}"
XRAY_AGENT_PROJECT_REPO="${XRAY_AGENT_PROJECT_REPO:-https://github.com/Suysker/xray-agent}"
XRAY_AGENT_PROJECT_BRANCH="${XRAY_AGENT_PROJECT_BRANCH:-master}"
XRAY_AGENT_PROJECT_RAW_INSTALL_URL="${XRAY_AGENT_PROJECT_RAW_INSTALL_URL:-https://raw.githubusercontent.com/Suysker/xray-agent/${XRAY_AGENT_PROJECT_BRANCH}/install.sh}"
XRAY_AGENT_PROJECT_ARCHIVE_URL="${XRAY_AGENT_PROJECT_ARCHIVE_URL:-${XRAY_AGENT_PROJECT_REPO}/archive/refs/heads/${XRAY_AGENT_PROJECT_BRANCH}.tar.gz}"

xray_agent_project_root() {
    printf '%s\n' "${XRAY_AGENT_PROJECT_ROOT}"
}

xray_agent_color_code() {
    case "$1" in
        red) printf '31' ;;
        skyBlue) printf '36' ;;
        green) printf '32' ;;
        white) printf '37' ;;
        magenta) printf '35' ;;
        yellow) printf '33' ;;
        *) printf '0' ;;
    esac
}

xray_agent_println() {
    local color="$1"
    local message="${2:-}"
    printf '\033[%sm%s\033[0m\n' "$(xray_agent_color_code "${color}")" "${message}"
}

xray_agent_print_inline() {
    local color="$1"
    local message="${2:-}"
    printf '\033[%sm%s\033[0m' "$(xray_agent_color_code "${color}")" "${message}"
}

xray_agent_blank() {
    printf '\n'
}

echoContent() {
    xray_agent_println "$1" "${2:-}"
}

xray_agent_log() {
    local color="${1:-white}"
    local message="$2"
    echoContent "${color}" "${message}"
}

xray_agent_normalize_yes_no_prompt() {
    local prompt="$1"
    if [[ "${prompt}" =~ ^(.*)\[[Yy]/[Nn]\]:?$ ]]; then
        prompt="${BASH_REMATCH[1]}"
    fi
    printf '%s' "${prompt}"
}

xray_agent_prompt_yes_no() {
    local prompt="$1"
    local default_value="${2:-y}"
    local answer suffix
    prompt="$(xray_agent_normalize_yes_no_prompt "${prompt}")"
    default_value="$(printf '%s' "${default_value}" | tr '[:upper:]' '[:lower:]')"
    [[ "${default_value}" == "n" ]] || default_value="y"
    if [[ "${default_value}" == "y" ]]; then
        suffix="[Y/n]:"
    else
        suffix="[y/N]:"
    fi
    while true; do
        read -r -p "${prompt}${suffix}" answer
        answer="${answer:-${default_value}}"
        answer="$(printf '%s' "${answer}" | tr '[:upper:]' '[:lower:]')"
        case "${answer}" in
            y | yes) return 0 ;;
            n | no) return 1 ;;
            *) echoContent red " ---> 请输入 y 或 n" ;;
        esac
    done
}

xray_agent_confirm() {
    xray_agent_prompt_yes_no "$@"
}

xray_agent_confirm_action() {
    local prompt="$1"
    local default_value="${2:-y}"
    if xray_agent_prompt_yes_no "${prompt}" "${default_value}"; then
        return 0
    fi
    echoContent yellow " ---> 已取消"
    return 1
}

xray_agent_confirm_danger() {
    xray_agent_prompt_yes_no "$1" "n"
}

xray_agent_error() {
    echoContent red "$1"
    exit 0
}

xray_agent_trim_quotes() {
    local value="$1"
    value="${value%\"}"
    value="${value#\"}"
    echo "${value}"
}

xray_agent_urlencode() {
    local value="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -nr --arg value "${value}" '$value | @uri' | tr -d '\r'
        return 0
    fi
    value="${value//'%'/%25}"
    value="${value//' '/%20}"
    value="${value//\"/%22}"
    value="${value//'#'/%23}"
    value="${value//'&'/%26}"
    value="${value//'+'/%2B}"
    value="${value//','/%2C}"
    value="${value//'/'/%2F}"
    value="${value//':'/%3A}"
    value="${value//';'/%3B}"
    value="${value//'='/%3D}"
    value="${value//'?'/%3F}"
    value="${value//'@'/%40}"
    echo "${value}"
}

xray_agent_uri_authority_host() {
    local host="$1"
    if [[ "${host}" == *:* && "${host}" != \[*\] ]]; then
        printf '[%s]\n' "${host}"
        return 0
    fi
    printf '%s\n' "${host}"
}

xray_agent_ensure_dir() {
    mkdir -p "$1"
}

xray_agent_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

xray_agent_download_file() {
    local url="$1"
    local output_path="$2"
    if xray_agent_command_exists curl; then
        curl -fsSL "${url}" -o "${output_path}"
    elif xray_agent_command_exists wget; then
        wget -q -O "${output_path}" "${url}"
    else
        echoContent red "curl or wget is required"
        return 1
    fi
}

xray_agent_safe_remove() {
    local target_path
    for target_path in "$@"; do
        [[ -n "${target_path}" && "${target_path}" != "/" ]] || continue
        rm -rf -- "${target_path}"
    done
}

xray_agent_json_write() {
    local target_path="$1"
    local json_content="$2"
    local temp_path="${target_path}.tmp"
    printf '%s\n' "${json_content}" | jq . >"${temp_path}" && mv "${temp_path}" "${target_path}"
}

xray_agent_json_update_file() {
    local target_path="$1"
    local jq_filter="$2"
    local temp_path="${target_path}.tmp"
    shift 2
    jq "$@" "${jq_filter}" "${target_path}" >"${temp_path}" && mv "${temp_path}" "${target_path}"
}

xray_agent_json_query() {
    local target_path="$1"
    local jq_filter="$2"
    local default_value="${3:-}"
    if [[ ! -f "${target_path}" ]]; then
        printf '%s\n' "${default_value}"
        return 0
    fi
    jq -r "${jq_filter}" "${target_path}" 2>/dev/null | head -1
}

xray_agent_json_string() {
    jq -Rn --arg value "$1" '$value' | tr -d '\r'
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

xray_agent_render_template_stdout() {
    local template_path="$1"
    local template_content
    template_content=$(cat "${template_path}")
    eval "cat <<__XRAY_AGENT_TEMPLATE__
${template_content}
__XRAY_AGENT_TEMPLATE__"
}

xray_agent_render_json_template() {
    xray_agent_render_template "$1" "$2"
}

xray_agent_apply_json_patch() {
    local target_path="$1"
    local jq_filter="$2"
    xray_agent_json_update_file "${target_path}" "${jq_filter}"
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

xray_agent_validate_non_empty() {
    [[ -n "$1" ]]
}

xray_agent_validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

xray_agent_validate_domain() {
    [[ "$1" =~ ^[A-Za-z0-9.-]+$ ]] && [[ "$1" == *.* ]]
}

xray_agent_validate_uuid() {
    [[ "$1" =~ ^[0-9a-fA-F-]{36}$ ]]
}

xray_agent_validate_path_segment() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

xray_agent_validate_csv() {
    [[ "$1" != *"  "* ]]
}

xray_agent_lock_path() {
    echo "/tmp/xray-agent.lock"
}

xray_agent_lock_acquire() {
    exec 9>"$(xray_agent_lock_path)"
    flock -n 9
}

xray_agent_lock_release() {
    flock -u 9 2>/dev/null || true
    rm -f "$(xray_agent_lock_path)"
}
