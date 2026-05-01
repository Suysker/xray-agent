#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_backup_dir() {
    printf '%s/backups\n' "${XRAY_AGENT_ETC_DIR}"
}

xray_agent_backup_id() {
    date '+%Y%m%d-%H%M%S'
}

xray_agent_backup_copy_abs_path() {
    local source_path="$1"
    local payload_dir="$2"
    local relative_path target_path
    [[ -e "${source_path}" ]] || return 0
    relative_path="${source_path#/}"
    target_path="${payload_dir}/${relative_path}"
    mkdir -p "$(dirname "${target_path}")"
    cp -a "${source_path}" "${target_path}"
}

xray_agent_backup_collect_payload() {
    local payload_dir="$1"
    local etc_parent etc_base etc_relative_parent
    mkdir -p "${payload_dir}"

    if [[ -d "${XRAY_AGENT_ETC_DIR}" ]]; then
        etc_parent="$(dirname "${XRAY_AGENT_ETC_DIR}")"
        etc_base="$(basename "${XRAY_AGENT_ETC_DIR}")"
        etc_relative_parent="$(dirname "${XRAY_AGENT_ETC_DIR#/}")"
        mkdir -p "${payload_dir}/${etc_relative_parent}"
        tar \
            --exclude="${etc_base}/backups" \
            --exclude="${etc_base}/*.log" \
            --exclude="${etc_base}/xray/*.log" \
            -C "${etc_parent}" -cf - "${etc_base}" | tar -C "${payload_dir}/${etc_relative_parent}" -xf -
    fi

    xray_agent_backup_copy_abs_path "${nginxConfigPath}alone.conf" "${payload_dir}"
    xray_agent_backup_copy_abs_path "${nginxConfigPath}alone.stream" "${payload_dir}"
}

xray_agent_backup_files_json() {
    local payload_dir="$1"
    (
        cd "${payload_dir}" || exit 1
        find . -type f -print0 | sort -z | while IFS= read -r -d '' file_path; do
            local relative_path checksum file_size
            relative_path="${file_path#./}"
            checksum="$(sha256sum "${file_path}" | awk '{print $1}')"
            file_size="$(wc -c <"${file_path}" | tr -d '[:space:]')"
            jq -nc \
                --arg path "/${relative_path}" \
                --arg sha256 "${checksum}" \
                --argjson size "${file_size:-0}" \
                '{path:$path,sha256:$sha256,size:$size}'
        done
    ) | jq -s .
}

xray_agent_backup_manifest_json() {
    local backup_id="$1"
    local reason="$2"
    local payload_dir="$3"
    local files_json hostname_value protocol_value
    files_json="$(xray_agent_backup_files_json "${payload_dir}")"
    hostname_value="$(hostname 2>/dev/null || true)"
    protocol_value="$(xray_agent_protocol_summary 2>/dev/null || true)"

    jq -n \
        --argjson schema_version 1 \
        --arg backup_id "${backup_id}" \
        --arg reason "${reason}" \
        --arg created_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg project_version "${XRAY_AGENT_VERSION:-unknown}" \
        --arg hostname "${hostname_value}" \
        --arg install_type "$(xray_agent_install_type_label 2>/dev/null || true)" \
        --arg protocols "${protocol_value}" \
        --arg domain "${domain:-}" \
        --arg tls_domain "${TLSDomain:-}" \
        --arg reality_target "${RealityDestDomain:-}" \
        --arg reality_port "${RealityPort:-}" \
        --arg nginx_config_path "${nginxConfigPath:-}" \
        --argjson files "${files_json}" \
        '{
          schema_version:$schema_version,
          backup_id:$backup_id,
          reason:$reason,
          created_at:$created_at,
          project_version:$project_version,
          hostname:$hostname,
          install_type:$install_type,
          protocols:$protocols,
          domain:$domain,
          tls_domain:$tls_domain,
          reality_target:$reality_target,
          reality_port:$reality_port,
          nginx_config_path:$nginx_config_path,
          files:$files
        }'
}

xray_agent_backup_create() {
    local reason="${1:-manual}"
    local quiet="${2:-false}"
    local backup_dir backup_id staging_dir payload_dir manifest_path archive_path

    backup_dir="$(xray_agent_backup_dir)"
    backup_id="$(xray_agent_backup_id)"
    archive_path="${backup_dir}/xray-agent-${backup_id}.tar.gz"
    staging_dir="$(mktemp -d)"
    payload_dir="${staging_dir}/payload"
    manifest_path="${staging_dir}/manifest.json"

    mkdir -p "${backup_dir}"
    chmod 700 "${backup_dir}" 2>/dev/null || true

    readInstallType 2>/dev/null || true
    readInstallProtocolType 2>/dev/null || true
    readConfigHostPathUUID 2>/dev/null || true

    xray_agent_backup_collect_payload "${payload_dir}"
    xray_agent_backup_manifest_json "${backup_id}" "${reason}" "${payload_dir}" >"${manifest_path}"
    jq -e . "${manifest_path}" >/dev/null

    tar -czf "${archive_path}" -C "${staging_dir}" manifest.json payload
    chmod 600 "${archive_path}" 2>/dev/null || true
    rm -rf "${staging_dir}"

    if [[ "${quiet}" != "true" ]]; then
        echoContent green " ---> 备份已创建: ${archive_path}"
    fi
    printf '%s\n' "${archive_path}"
}

xray_agent_backup_latest_archive() {
    local backup_dir
    backup_dir="$(xray_agent_backup_dir)"
    ls -1t "${backup_dir}"/xray-agent-*.tar.gz 2>/dev/null | head -1
}

xray_agent_backup_list() {
    local backup_dir
    backup_dir="$(xray_agent_backup_dir)"
    xray_agent_blank
    echoContent skyBlue "-------------------------备份列表-----------------------------"
    if ! ls -1t "${backup_dir}"/xray-agent-*.tar.gz >/dev/null 2>&1; then
        echoContent yellow "暂无备份"
        return 0
    fi
    ls -1t "${backup_dir}"/xray-agent-*.tar.gz | awk '{print NR"."$0}'
}

xray_agent_backup_validate_checksums() {
    local extracted_dir="$1"
    local manifest_path="${extracted_dir}/manifest.json"
    local payload_dir="${extracted_dir}/payload"
    local row relative_path expected actual target_path

    while IFS= read -r row; do
        relative_path="$(printf '%s\n' "${row}" | jq -r '.path')"
        expected="$(printf '%s\n' "${row}" | jq -r '.sha256')"
        target_path="${payload_dir}${relative_path}"
        if [[ ! -f "${target_path}" ]]; then
            echoContent red " ---> 备份缺少文件: ${relative_path}"
            return 1
        fi
        actual="$(sha256sum "${target_path}" | awk '{print $1}')"
        if [[ "${actual}" != "${expected}" ]]; then
            echoContent red " ---> 文件校验失败: ${relative_path}"
            return 1
        fi
    done < <(jq -c '.files[]' "${manifest_path}")
}

xray_agent_backup_validate_json_files() {
    local payload_dir="$1"
    local json_file
    while IFS= read -r json_file; do
        if ! jq -e . "${json_file}" >/dev/null 2>&1; then
            echoContent red " ---> JSON校验失败: ${json_file#${payload_dir}}"
            return 1
        fi
    done < <(find "${payload_dir}" -type f -name "*.json" 2>/dev/null)
}

xray_agent_backup_validate_xray_config() {
    local payload_dir="$1"
    local payload_conf_dir="${payload_dir}${XRAY_AGENT_XRAY_CONF_DIR}"
    local old_config_path status
    [[ -d "${payload_conf_dir}" ]] || return 0
    old_config_path="${configPath}"
    configPath="${payload_conf_dir}/"
    xray_agent_xray_config_test
    status=$?
    configPath="${old_config_path}"
    return "${status}"
}

xray_agent_backup_validate_extracted() {
    local extracted_dir="$1"
    local manifest_path="${extracted_dir}/manifest.json"
    local payload_dir="${extracted_dir}/payload"

    [[ -f "${manifest_path}" && -d "${payload_dir}" ]] || {
        echoContent red " ---> 备份包结构不完整"
        return 1
    }
    jq -e '.schema_version == 1 and (.files | type == "array")' "${manifest_path}" >/dev/null || {
        echoContent red " ---> manifest.json 格式不正确"
        return 1
    }
    xray_agent_backup_validate_checksums "${extracted_dir}" || return 1
    xray_agent_backup_validate_json_files "${payload_dir}" || return 1
    xray_agent_backup_validate_xray_config "${payload_dir}" || return 1
}

xray_agent_backup_extract_and_validate() {
    local archive_path="$1"
    local extracted_dir="$2"
    [[ -f "${archive_path}" ]] || {
        echoContent red " ---> 备份包不存在: ${archive_path}"
        return 1
    }
    tar -xzf "${archive_path}" -C "${extracted_dir}" || {
        echoContent red " ---> 备份包解压失败"
        return 1
    }
    xray_agent_backup_validate_extracted "${extracted_dir}"
}

xray_agent_backup_safe_replace_path() {
    local source_path="$1"
    local target_path="$2"
    [[ -e "${source_path}" ]] || return 0
    case "${target_path}" in
        "${XRAY_AGENT_ETC_DIR}" | "${XRAY_AGENT_ETC_DIR}"/* | "${nginxConfigPath}"*)
            rm -rf "${target_path}"
            mkdir -p "$(dirname "${target_path}")"
            cp -a "${source_path}" "${target_path}"
            ;;
        *)
            echoContent red " ---> 拒绝恢复到非托管路径: ${target_path}"
            return 1
            ;;
    esac
}

xray_agent_backup_restore_payload() {
    local payload_dir="$1"
    local payload_etc_dir="${payload_dir}${XRAY_AGENT_ETC_DIR}"
    local entry source_path target_path

    mkdir -p "${XRAY_AGENT_ETC_DIR}"
    for entry in install.sh README.md VERSION LICENSE lib profiles templates docs packaging tls xray; do
        source_path="${payload_etc_dir}/${entry}"
        target_path="${XRAY_AGENT_ETC_DIR}/${entry}"
        xray_agent_backup_safe_replace_path "${source_path}" "${target_path}"
    done

    if [[ -f "${payload_dir}${nginxConfigPath}alone.conf" ]]; then
        xray_agent_backup_safe_replace_path "${payload_dir}${nginxConfigPath}alone.conf" "${nginxConfigPath}alone.conf"
    fi
    if [[ -f "${payload_dir}${nginxConfigPath}alone.stream" ]]; then
        xray_agent_backup_safe_replace_path "${payload_dir}${nginxConfigPath}alone.stream" "${nginxConfigPath}alone.stream"
    else
        rm -f "${nginxConfigPath}alone.stream"
    fi

    [[ -f "${XRAY_AGENT_ETC_DIR}/install.sh" ]] && chmod 700 "${XRAY_AGENT_ETC_DIR}/install.sh" 2>/dev/null || true
}

xray_agent_backup_post_restore_validate() {
    if ! xray_agent_xray_config_test; then
        echoContent red " ---> 恢复后的 Xray 配置测试失败"
        [[ -f /tmp/xray-agent-xray-test.log ]] && tail -n 30 /tmp/xray-agent-xray-test.log
        return 1
    fi
    if ! xray_agent_nginx_test_config; then
        echoContent red " ---> 恢复后的 Nginx 配置测试失败"
        [[ -f /tmp/xray-agent-nginx-test.log ]] && tail -n 20 /tmp/xray-agent-nginx-test.log
        return 1
    fi
}

xray_agent_backup_restore() {
    local archive_path="$1"
    local extracted_dir payload_dir pre_restore_backup

    extracted_dir="$(mktemp -d)"
    if ! xray_agent_backup_extract_and_validate "${archive_path}" "${extracted_dir}"; then
        rm -rf "${extracted_dir}"
        return 1
    fi

    pre_restore_backup="$(xray_agent_backup_create "pre-restore" true)" || {
        rm -rf "${extracted_dir}"
        return 1
    }
    echoContent yellow " ---> 恢复前备份: ${pre_restore_backup}"

    payload_dir="${extracted_dir}/payload"
    if ! xray_agent_backup_restore_payload "${payload_dir}"; then
        echoContent red " ---> 恢复写入失败，当前状态备份: ${pre_restore_backup}"
        rm -rf "${extracted_dir}"
        return 1
    fi
    if ! xray_agent_backup_post_restore_validate; then
        echoContent red " ---> 恢复已写入但服务配置校验失败，可用恢复前备份回滚。"
        echoContent yellow " ---> 回滚备份: ${pre_restore_backup}"
        rm -rf "${extracted_dir}"
        return 1
    fi
    rm -rf "${extracted_dir}"
    echoContent green " ---> 恢复完成"
}

xray_agent_backup_restore_prompt() {
    local archive_path latest_archive
    latest_archive="$(xray_agent_backup_latest_archive)"
    read -r -p "请输入备份包路径[回车使用最新备份]:" archive_path
    archive_path="${archive_path:-${latest_archive}}"
    if [[ -z "${archive_path}" ]]; then
        echoContent yellow " ---> 暂无可恢复备份"
        return 0
    fi
    echoContent yellow "将恢复备份: ${archive_path}"
    xray_agent_confirm "确认继续？[y/N]:" "n" || return 0
    xray_agent_backup_restore "${archive_path}"
}

xray_agent_backup_menu() {
    local selected_item
    xray_agent_tool_status_header "备份与恢复管理"
    echoContent yellow "1.创建备份"
    echoContent yellow "2.查看备份"
    echoContent yellow "3.恢复备份"
    echoContent red "=============================================================="
    read -r -p "请输入:" selected_item
    case "${selected_item}" in
        1) xray_agent_backup_create "manual" >/dev/null ;;
        2) xray_agent_backup_list ;;
        3) xray_agent_backup_restore_prompt ;;
        *) echoContent red " ---> 选择错误" ;;
    esac
}
