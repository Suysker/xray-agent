#!/usr/bin/env bash

export LANG=en_US.UTF-8

SCRIPT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export XRAY_AGENT_PROJECT_ROOT="${SCRIPT_DIR}"

XRAY_AGENT_PROJECT_REPO="${XRAY_AGENT_PROJECT_REPO:-https://github.com/Suysker/xray-agent}"
XRAY_AGENT_BOOTSTRAP_BRANCH="${XRAY_AGENT_BOOTSTRAP_BRANCH:-master}"
XRAY_AGENT_BOOTSTRAP_TARGET_ROOT="${XRAY_AGENT_BOOTSTRAP_TARGET_ROOT:-/etc/xray-agent}"
XRAY_AGENT_BOOTSTRAP_ARCHIVE_URL="${XRAY_AGENT_BOOTSTRAP_ARCHIVE_URL:-${XRAY_AGENT_PROJECT_REPO}/archive/refs/heads/${XRAY_AGENT_BOOTSTRAP_BRANCH}.tar.gz}"

xray_agent_prepend_path_once() {
    local candidate="$1"
    [[ -d "${candidate}" ]] || return 0
    case ":${PATH}:" in
        *":${candidate}:"*) ;;
        *) export PATH="${candidate}:${PATH}" ;;
    esac
}

xray_agent_to_unix_path() {
    local raw_path="$1"
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "${raw_path}"
        return 0
    fi
    raw_path="${raw_path//\\//}"
    if [[ "${raw_path}" =~ ^([A-Za-z]):(/.*)?$ ]]; then
        printf '/mnt/%s%s\n' "$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')" "${BASH_REMATCH[2]}"
        return 0
    fi
    printf '%s\n' "${raw_path}"
}

xray_agent_ensure_jq_on_path() {
    command -v jq >/dev/null 2>&1 && return 0

    local local_app_data unix_local_app_data winget_links_dir candidate_dir
    local_app_data="${LOCALAPPDATA:-}"
    if [[ -z "${local_app_data}" && -n "${USERPROFILE:-}" ]]; then
        local_app_data="${USERPROFILE}\\AppData\\Local"
    fi

    if [[ -n "${local_app_data}" ]]; then
        unix_local_app_data="$(xray_agent_to_unix_path "${local_app_data}")"
        winget_links_dir="${unix_local_app_data}/Microsoft/WinGet/Links"
        xray_agent_prepend_path_once "${winget_links_dir}"

        for candidate_dir in "${unix_local_app_data}"/Microsoft/WinGet/Packages/jqlang.jq_*/; do
            xray_agent_prepend_path_once "${candidate_dir%/}"
        done
    fi

    for winget_links_dir in /mnt/c/Users/*/AppData/Local/Microsoft/WinGet/Links /c/Users/*/AppData/Local/Microsoft/WinGet/Links; do
        xray_agent_prepend_path_once "${winget_links_dir}"
    done

    for candidate_dir in /mnt/c/Users/*/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_*/ /c/Users/*/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_*/; do
        xray_agent_prepend_path_once "${candidate_dir%/}"
    done
}

xray_agent_runtime_layout_complete() {
    local required_path
    for required_path in \
        "${SCRIPT_DIR}/lib/common.sh" \
        "${SCRIPT_DIR}/lib/network.sh" \
        "${SCRIPT_DIR}/lib/runtime.sh" \
        "${SCRIPT_DIR}/lib/system.sh" \
        "${SCRIPT_DIR}/lib/tls.sh" \
        "${SCRIPT_DIR}/lib/core.sh" \
        "${SCRIPT_DIR}/lib/nginx_state.sh" \
        "${SCRIPT_DIR}/lib/nginx_preflight.sh" \
        "${SCRIPT_DIR}/lib/nginx_render.sh" \
        "${SCRIPT_DIR}/lib/nginx.sh" \
        "${SCRIPT_DIR}/lib/protocols.sh" \
        "${SCRIPT_DIR}/lib/accounts.sh" \
        "${SCRIPT_DIR}/lib/backup.sh" \
        "${SCRIPT_DIR}/lib/subscription.sh" \
        "${SCRIPT_DIR}/lib/routing.sh" \
        "${SCRIPT_DIR}/lib/features.sh" \
        "${SCRIPT_DIR}/lib/apps.sh" \
        "${SCRIPT_DIR}/lib/external.sh" \
        "${SCRIPT_DIR}/lib/installer.sh" \
        "${SCRIPT_DIR}/lib/cli.sh" \
        "${SCRIPT_DIR}/profiles/install" \
        "${SCRIPT_DIR}/profiles/protocol" \
        "${SCRIPT_DIR}/profiles/routing" \
        "${SCRIPT_DIR}/profiles/subscription/rules.json" \
        "${SCRIPT_DIR}/templates/xray/base" \
        "${SCRIPT_DIR}/templates/xray/inbounds" \
        "${SCRIPT_DIR}/templates/xray/outbounds" \
        "${SCRIPT_DIR}/templates/nginx" \
        "${SCRIPT_DIR}/templates/systemd" \
        "${SCRIPT_DIR}/templates/share" \
        "${SCRIPT_DIR}/packaging"; do
        [[ -e "${required_path}" ]] || return 1
    done
}

xray_agent_download_bootstrap_archive() {
    local archive_path="$1"
    local archive_source="${XRAY_AGENT_BOOTSTRAP_ARCHIVE:-}"

    if [[ -n "${archive_source}" && -f "${archive_source}" ]]; then
        cp "${archive_source}" "${archive_path}"
        return 0
    fi

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${archive_source:-${XRAY_AGENT_BOOTSTRAP_ARCHIVE_URL}}" -o "${archive_path}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "${archive_path}" "${archive_source:-${XRAY_AGENT_BOOTSTRAP_ARCHIVE_URL}}"
    else
        echo "curl or wget is required to bootstrap xray-agent" >&2
        return 1
    fi
}

xray_agent_bootstrap_full_layout() {
    local temp_dir archive_path layout_script target_root
    target_root="${XRAY_AGENT_BOOTSTRAP_TARGET_ROOT}"
    temp_dir="$(mktemp -d)"
    archive_path="${temp_dir}/xray-agent.tar.gz"

    xray_agent_download_bootstrap_archive "${archive_path}" || return 1
    tar -m -xzf "${archive_path}" -C "${temp_dir}"

    layout_script="$(find "${temp_dir}" -mindepth 3 -maxdepth 4 -path "*/packaging/install-layout.sh" -print -quit)"
    if [[ -z "${layout_script}" ]]; then
        echo "Downloaded xray-agent archive does not contain packaging/install-layout.sh" >&2
        return 1
    fi

    bash "${layout_script}" "${target_root}"
    chmod 700 "${target_root}/install.sh"
    if [[ "${XRAY_AGENT_BOOTSTRAP_NO_EXEC:-false}" == "true" ]]; then
        rm -rf "${temp_dir}"
        exit 0
    fi
    rm -rf "${temp_dir}"
    exec bash "${target_root}/install.sh" "$@"
}

if ! xray_agent_runtime_layout_complete; then
    if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
        echo "xray-agent runtime layout is incomplete; execute install.sh to bootstrap the full layout" >&2
        return 1
    fi
    xray_agent_bootstrap_full_layout "$@"
fi

xray_agent_ensure_jq_on_path

for module_file in \
    "${SCRIPT_DIR}/lib/common.sh" \
    "${SCRIPT_DIR}/lib/network.sh" \
    "${SCRIPT_DIR}/lib/runtime.sh" \
    "${SCRIPT_DIR}/lib/system.sh" \
    "${SCRIPT_DIR}/lib/tls.sh" \
    "${SCRIPT_DIR}/lib/core.sh" \
    "${SCRIPT_DIR}/lib/nginx_state.sh" \
    "${SCRIPT_DIR}/lib/nginx_preflight.sh" \
    "${SCRIPT_DIR}/lib/nginx_render.sh" \
    "${SCRIPT_DIR}/lib/nginx.sh" \
    "${SCRIPT_DIR}/lib/features.sh" \
    "${SCRIPT_DIR}/lib/apps.sh" \
    "${SCRIPT_DIR}/lib/external.sh" \
    "${SCRIPT_DIR}/lib/routing.sh" \
    "${SCRIPT_DIR}/lib/protocols.sh" \
    "${SCRIPT_DIR}/lib/accounts.sh" \
    "${SCRIPT_DIR}/lib/backup.sh" \
    "${SCRIPT_DIR}/lib/subscription.sh" \
    "${SCRIPT_DIR}/lib/installer.sh" \
    "${SCRIPT_DIR}/lib/cli.sh"; do
    source "${module_file}"
done

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    xray_agent_main "$@"
fi
