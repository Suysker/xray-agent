#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_github_api_error_message() {
    local response_file="$1"
    jq -r '
        if type == "object" then
            .message // empty
        elif type == "string" then
            .
        else
            empty
        end
    ' "${response_file}" 2>/dev/null | head -1 | tr -d '\r'
}

xray_agent_github_fetch_releases() {
    local repo="$1"
    local response_file="$2"
    local api_url="https://api.github.com/repos/${repo}/releases"
    local error_file="${response_file}.err"
    local github_token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    rm -f "${response_file}" "${error_file}"

    if command -v curl >/dev/null 2>&1; then
        local curl_args=(-sSL --retry 2 --connect-timeout 15 -H "Accept: application/vnd.github+json")
        local http_code
        [[ -n "${github_token}" ]] && curl_args+=(-H "Authorization: Bearer ${github_token}")
        if ! http_code="$(curl "${curl_args[@]}" "${api_url}" -o "${response_file}" -w "%{http_code}" 2>"${error_file}")"; then
            echoContent red " ---> 访问 GitHub Release API 失败: ${repo}" >&2
            [[ -s "${error_file}" ]] && sed 's/^/     /' "${error_file}" >&2
            rm -f "${error_file}"
            return 1
        fi
        if [[ "${http_code}" != "200" ]]; then
            echoContent red " ---> GitHub Release API 返回 HTTP ${http_code}: ${repo}" >&2
            local message
            message="$(xray_agent_github_api_error_message "${response_file}")"
            if [[ -n "${message}" ]]; then
                echoContent yellow " ---> 返回信息: ${message}" >&2
                if printf '%s\n' "${message}" | grep -qi "rate limit"; then
                    echoContent yellow " ---> 这通常是 GitHub API 限流。请稍后重试，或先配置可访问 GitHub 的网络后再升级。" >&2
                fi
            fi
            rm -f "${error_file}"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        local wget_args=(-q -O "${response_file}")
        [[ -n "${github_token}" ]] && wget_args+=(--header "Authorization: Bearer ${github_token}")
        if ! wget "${wget_args[@]}" "${api_url}" 2>"${error_file}"; then
            echoContent red " ---> 访问 GitHub Release API 失败: ${repo}" >&2
            [[ -s "${error_file}" ]] && sed 's/^/     /' "${error_file}" >&2
            rm -f "${error_file}"
            return 1
        fi
    else
        echoContent red " ---> curl 或 wget 不存在，无法访问 GitHub Release API" >&2
        return 1
    fi
    rm -f "${error_file}"

    if ! jq -e 'type == "array"' "${response_file}" >/dev/null 2>&1; then
        local message
        message="$(xray_agent_github_api_error_message "${response_file}")"
        echoContent red " ---> GitHub Release API 返回异常，已停止操作" >&2
        if [[ -n "${message}" ]]; then
            echoContent yellow " ---> 返回信息: ${message}" >&2
            if printf '%s\n' "${message}" | grep -qi "rate limit"; then
                echoContent yellow " ---> 这通常是 GitHub API 限流。请稍后重试，或先配置可访问 GitHub 的网络后再升级。" >&2
            fi
        fi
        return 1
    fi
}

xray_agent_github_release_tags() {
    local repo="$1"
    local prerelease_filter="${2:-}"
    local limit="${3:-1}"
    local response_file
    response_file="$(mktemp)"

    if ! xray_agent_github_fetch_releases "${repo}" "${response_file}"; then
        rm -f "${response_file}"
        return 1
    fi
    if [[ -n "${prerelease_filter}" ]]; then
        jq -r --arg prerelease "${prerelease_filter}" --argjson limit "${limit}" '
            [ .[]? | select((.prerelease // false) == ($prerelease == "true")) | .tag_name // empty | select(length > 0) ][: $limit][]
        ' "${response_file}" | tr -d '\r'
    else
        jq -r --argjson limit "${limit}" '
            [ .[]? | .tag_name // empty | select(length > 0) ][: $limit][]
        ' "${response_file}" | tr -d '\r'
    fi
    rm -f "${response_file}"
}

xray_agent_xray_latest_version() {
    local prerelease_filter="${1:-false}"
    local version
    version="$(xray_agent_github_release_tags "XTLS/Xray-core" "${prerelease_filter}" 1)" || return 1
    printf '%s\n' "${version}" | head -1
}

xray_agent_download_url_to_file() {
    local url="$1"
    local target_file="$2"
    local label="${3:-文件}"
    local temp_file="${target_file}.tmp.$$"
    rm -f "${temp_file}"

    echoContent yellow " ---> 下载 ${label}"
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fL --retry 2 --connect-timeout 15 --progress-bar "${url}" -o "${temp_file}"; then
            echoContent red " ---> ${label} 下载失败"
            rm -f "${temp_file}"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget --help 2>&1 | grep -q show-progress; then
            if ! wget -q --show-progress -O "${temp_file}" "${url}"; then
                echoContent red " ---> ${label} 下载失败"
                rm -f "${temp_file}"
                return 1
            fi
        elif ! wget -O "${temp_file}" "${url}"; then
            echoContent red " ---> ${label} 下载失败"
            rm -f "${temp_file}"
            return 1
        fi
    else
        echoContent red " ---> curl 或 wget 不存在，无法下载 ${label}"
        return 1
    fi

    if [[ ! -s "${temp_file}" ]]; then
        echoContent red " ---> ${label} 下载结果为空"
        rm -f "${temp_file}"
        return 1
    fi
    mv "${temp_file}" "${target_file}"
    echoContent green " ---> ${label} 下载完成"
}

xray_agent_install_xray_release() {
    local version="$1"
    local xray_dir="/etc/xray-agent/xray"
    local archive_path="${xray_dir}/${xrayCoreCPUVendor}.zip"
    local temp_dir
    local release_url="https://github.com/XTLS/Xray-core/releases/download/${version}/${xrayCoreCPUVendor}.zip"

    [[ -n "${version}" ]] || {
        echoContent red " ---> 未获取到可用的 Xray-core 版本，已停止操作"
        return 1
    }

    mkdir -p "${xray_dir}"
    if ! xray_agent_download_url_to_file "${release_url}" "${archive_path}" "Xray-core ${version}"; then
        echoContent yellow " ---> 已保留当前 Xray-core，不会继续解压或覆盖"
        return 1
    fi

    temp_dir="$(mktemp -d)"
    echoContent yellow " ---> 解压并验证 Xray-core ${version}"
    if ! unzip -oq "${archive_path}" -d "${temp_dir}" || [[ ! -f "${temp_dir}/xray" ]]; then
        echoContent red "下载或解压新版本Xray失败，请重试"
        rm -rf "${temp_dir}" "${archive_path}"
        echoContent yellow " ---> 已保留当前 Xray-core"
        return 1
    fi

    find "${temp_dir}" -maxdepth 1 -type f -exec cp -f {} "${xray_dir}/" \;
    rm -rf "${temp_dir}" "${archive_path}"
    chmod 655 "${ctlPath:-${xray_dir}/xray}"
    echoContent green " ---> Xray-core ${version} 已安装"
}

xray_agent_download_geodata() {
    local version xray_dir geosite_tmp geoip_tmp
    xray_dir="/etc/xray-agent/xray"
    version="$(xray_agent_github_release_tags "Loyalsoldier/v2ray-rules-dat" "" 1)" || return 1
    version="$(printf '%s\n' "${version}" | head -1)"
    if [[ -z "${version}" ]]; then
        echoContent red " ---> 未获取到可用的 geosite/geoip 版本，已停止操作"
        return 1
    fi

    mkdir -p "${xray_dir}"
    geosite_tmp="${xray_dir}/geosite.dat.download"
    geoip_tmp="${xray_dir}/geoip.dat.download"
    xray_agent_download_url_to_file "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geosite.dat" "${geosite_tmp}" "geosite.dat" || return 1
    xray_agent_download_url_to_file "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geoip.dat" "${geoip_tmp}" "geoip.dat" || {
        rm -f "${geosite_tmp}"
        return 1
    }
    mv "${geosite_tmp}" "${xray_dir}/geosite.dat"
    mv "${geoip_tmp}" "${xray_dir}/geoip.dat"
    echoContent green " ---> geosite/geoip 已更新到 ${version}"
}

getPublicIP() {
    xray_agent_get_public_ip
}

xray_agent_xray_binary_ready() {
    [[ -x "${ctlPath:-}" ]]
}

xray_agent_xray_help_text() {
    xray_agent_xray_binary_ready || return 1
    "${ctlPath}" help 2>&1 || true
}

xray_agent_xray_supports_command() {
    local command_name="$1"
    xray_agent_xray_help_text | awk -v command_name="${command_name}" '
        $1 == command_name {found = 1}
        END {exit found ? 0 : 1}
    '
}

xray_agent_xray_supports_tls_ech() {
    xray_agent_xray_binary_ready || return 1
    "${ctlPath}" tls help 2>&1 | awk '$1 == "ech" {found = 1} END {exit found ? 0 : 1}'
}

xray_agent_xray_version_number() {
    xray_agent_xray_binary_ready || return 1
    "${ctlPath}" version 2>/dev/null | awk 'NR == 1 {print $2; exit}' | sed 's/^v//; s/[^0-9.].*$//'
}

xray_agent_version_ge() {
    local current="$1"
    local required="$2"
    awk -v current="${current}" -v required="${required}" '
        BEGIN {
            split(current, c, ".")
            split(required, r, ".")
            for (i = 1; i <= 3; i++) {
                cv = c[i] + 0
                rv = r[i] + 0
                if (cv > rv) {
                    exit 0
                }
                if (cv < rv) {
                    exit 1
                }
            }
            exit 0
        }'
}

xray_agent_version_normalize() {
    local version="$1"
    version="${version#v}"
    version="${version%%-*}"
    version="${version%%+*}"
    printf '%s\n' "${version}"
}

xray_agent_version_eq() {
    local current required
    current="$(xray_agent_version_normalize "$1")"
    required="$(xray_agent_version_normalize "$2")"
    [[ "${current}" == "${required}" ]]
}

xray_agent_version_gt() {
    local current required
    current="$(xray_agent_version_normalize "$1")"
    required="$(xray_agent_version_normalize "$2")"
    [[ "${current}" != "${required}" ]] && xray_agent_version_ge "${current}" "${required}"
}

xray_agent_xray_version_at_least() {
    local required="$1"
    local current
    current="$(xray_agent_xray_version_number || true)"
    [[ -n "${current}" ]] || return 1
    xray_agent_version_ge "${current}" "${required}"
}

xray_agent_xray_supports_hysteria2() {
    xray_agent_xray_version_at_least "26.3.27"
}

xray_agent_xray_supports_finalmask() {
    xray_agent_xray_version_at_least "26.3.27"
}

xray_agent_xray_supports_release_hardening() {
    xray_agent_xray_supports_command vlessenc &&
        xray_agent_xray_supports_command mldsa65 &&
        xray_agent_xray_supports_command mlkem768 &&
        xray_agent_xray_supports_tls_ech &&
        xray_agent_xray_supports_hysteria2 &&
        xray_agent_xray_supports_finalmask
}

xray_agent_warn_release_hardening_status() {
    xray_agent_xray_binary_ready || return 0
    local missing=()
    xray_agent_xray_supports_command vlessenc || missing+=("vlessenc")
    xray_agent_xray_supports_command mldsa65 || missing+=("mldsa65")
    xray_agent_xray_supports_command mlkem768 || missing+=("mlkem768")
    xray_agent_xray_supports_tls_ech || missing+=("tls ech")
    xray_agent_xray_supports_hysteria2 || missing+=("hysteria2")
    xray_agent_xray_supports_finalmask || missing+=("finalmask")
    if [[ "${#missing[@]}" -gt 0 ]]; then
        echoContent yellow " ---> 当前 Xray-core 缺少 release hardening 能力: $(xray_agent_join_by ', ' "${missing[@]}")"
        echoContent yellow " ---> 请通过菜单14升级正式版；脚本不会生成当前内核不支持的强化配置。"
    fi
}

xray_agent_xray_config_test() {
    xray_agent_xray_binary_ready || return 0
    [[ -d "${configPath:-}" ]] || return 0
    find "${configPath}" -maxdepth 1 -type f -name "*.json" | grep -q . || return 0
    "${ctlPath}" run -test -confdir "${configPath}" >/tmp/xray-agent-xray-test.log 2>&1
}

checkGFWStatue() {
    readInstallType
    xray_agent_blank
    echoContent skyBlue "进度 $1/${totalProgress} : 验证服务启动状态"
    if [[ -n "${coreInstallType}" ]] && [[ -n $(pgrep -f xray/xray) ]]; then
        echoContent green " ---> 服务启动成功"
    else
        xray_agent_error " ---> 服务启动失败，请检查终端是否有日志打印"
    fi
}

xrayVersionManageMenu() {
    xray_agent_blank
    echoContent skyBlue "进度  $1/${totalProgress} : Xray版本管理"
    if [[ ! -d "/etc/xray-agent/xray/" ]]; then
        echoContent red " ---> 没有检测到安装目录，请执行脚本安装内容"
        menu
        exit 0
    fi
    xray_agent_blank
    echoContent red "=============================================================="
    echoContent yellow "1.升级Xray-core"
    echoContent yellow "2.升级Xray-core 预览版"
    echoContent yellow "3.回退Xray-core"
    echoContent yellow "4.关闭Xray-core"
    echoContent yellow "5.打开Xray-core"
    echoContent yellow "6.重启Xray-core"
    echoContent yellow "7.更新geosite、geoip"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectXrayType
    case "${selectXrayType}" in
        1)
            updateXray || echoContent red " ---> Xray-core 升级未完成"
            ;;
        2)
            prereleaseStatus=true
            updateXray || echoContent red " ---> Xray-core 预览版升级未完成"
            ;;
        3)
            local rollback_versions=()
            local version_index
            echoContent yellow "1.只可以回退最近的五个版本"
            echoContent yellow "2.不保证回退后一定可以正常使用"
            echoContent yellow "3.如果回退的版本不支持当前的config，则会无法连接，谨慎操作"
            echoContent skyBlue "------------------------Version-------------------------------"
            mapfile -t rollback_versions < <(xray_agent_github_release_tags "XTLS/Xray-core" "false" 5)
            if [[ "${#rollback_versions[@]}" -eq 0 ]]; then
                echoContent red " ---> 未获取到可回退版本，请稍后重试"
                return 1
            fi
            for version_index in "${!rollback_versions[@]}"; do
                echoContent yellow "$((version_index + 1)):${rollback_versions[$version_index]}"
            done
            echoContent skyBlue "--------------------------------------------------------------"
            read -r -p "请输入要回退的版本:" selectXrayVersionType
            version=""
            if [[ "${selectXrayVersionType}" =~ ^[0-9]+$ ]] && ((selectXrayVersionType >= 1 && selectXrayVersionType <= ${#rollback_versions[@]})); then
                version="${rollback_versions[$((selectXrayVersionType - 1))]}"
            fi
            if [[ -n "${version}" ]]; then
                updateXray "${version}" || echoContent red " ---> Xray-core 回退未完成"
            else
                echoContent red " ---> 输入有误，请重新输入"
                xrayVersionManageMenu 1
            fi
            ;;
        4)
            handleXray stop
            ;;
        5)
            handleXray start
            ;;
        6)
            reloadCore
            ;;
        7)
            /etc/xray-agent/auto_update_geodata.sh
            ;;
    esac
}

installXray() {
    local version current_version
    readInstallType
    xray_agent_blank
    echoContent skyBlue "进度  $1/${totalProgress} : 检查/安装Xray"
    if [[ -z "${coreInstallType}" ]]; then
        version="$(xray_agent_xray_latest_version false)" || return 1
        echoContent green " ---> Xray-core版本:${version}"
        xray_agent_install_xray_release "${version}" || return 1
        xray_agent_download_geodata || echoContent yellow " ---> geosite/geoip 更新失败，可稍后在菜单14单独更新"
    else
        current_version="$(xray_agent_xray_version_number || true)"
        if [[ -n "${current_version}" ]]; then
            echoContent green " ---> 当前Xray-core版本:${current_version}"
            echoContent yellow " ---> 重装配置将保留当前 Xray-core；升级或回退请使用菜单14。"
            return 0
        fi

        echoContent yellow " ---> 检测到安装记录，但 Xray-core 可执行文件缺失，尝试重新安装正式版。"
        version="$(xray_agent_xray_latest_version false)" || return 1
        echoContent green " ---> Xray-core版本:${version}"
        xray_agent_install_xray_release "${version}" || return 1
    fi
}

reloadCore() {
    if ! xray_agent_xray_config_test; then
        echoContent red " ---> Xray 配置测试失败，已停止 reload。"
        [[ -f /tmp/xray-agent-xray-test.log ]] && tail -n 30 /tmp/xray-agent-xray-test.log
        return 1
    fi
    handleXray stop
    handleXray start
}

updateXray() {
    local version current_version remote_version
    readInstallType
    prereleaseStatus=${prereleaseStatus:-false}
    if [[ -n "$1" ]]; then
        version=$1
    else
        version="$(xray_agent_xray_latest_version "${prereleaseStatus}")" || return 1
    fi
    [[ -n "${version}" ]] || {
        echoContent red " ---> 未获取到可用的 Xray-core 版本，已停止操作"
        return 1
    }
    if [[ -z "${coreInstallType}" ]]; then
        echoContent green " ---> Xray-core版本:${version}"
        xray_agent_install_xray_release "${version}" || return 1
        handleXray stop
        handleXray start
    else
        current_version="$(${ctlPath} --version | awk '{print $2}' | head -1)"
        remote_version="$(xray_agent_version_normalize "${version}")"
        echoContent green " ---> 当前Xray-core版本:${current_version}"
        if [[ -n "$1" ]]; then
            if xray_agent_confirm_danger "回退版本为${version}，是否继续？"; then
                xray_agent_install_xray_release "${version}" || return 1
                reloadCore
                echoContent green " ---> Xray-core 已切换到 ${version}"
            else
                echoContent green " ---> 放弃回退版本"
            fi
        elif xray_agent_version_eq "${current_version}" "${remote_version}"; then
            if xray_agent_confirm_danger "当前版本与最新版相同，是否重新安装？"; then
                xray_agent_install_xray_release "${version}" || return 1
                reloadCore
                echoContent green " ---> Xray-core ${version} 已重新安装"
            else
                echoContent green " ---> 放弃重新安装"
            fi
        elif xray_agent_version_gt "${current_version}" "${remote_version}"; then
            echoContent yellow " ---> 当前版本 ${current_version} 高于远端目标版本 ${version}，不会自动降级。"
            echoContent yellow " ---> 如需回退，请使用菜单 3 并明确选择目标版本。"
        else
            if xray_agent_prompt_yes_no "最新版本为:${version}，是否更新？" "y"; then
                xray_agent_install_xray_release "${version}" || return 1
                reloadCore
                echoContent green " ---> Xray-core 已更新到 ${version}"
            else
                echoContent green " ---> 放弃更新"
            fi
        fi
    fi
}
