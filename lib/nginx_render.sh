#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_render_nginx_alone_conf() {
    local profile_name="$1"
    local upstream_url="${2:-https://huggingface.co}"
    local host_header tls_name
    upstream_url="$(xray_agent_nginx_active_upstream_url "${upstream_url}")"
    host_header="$(xray_agent_nginx_active_host_header "${upstream_url}")"
    tls_name="$(xray_agent_nginx_active_tls_name "${upstream_url}" "${host_header}")"
    export NGINX_HTTP_PORT="$(xray_agent_loopback_endpoint 31300) http2 so_keepalive=on"
    export NGINX_XHTTP_GRPC_TARGET="$(xray_agent_loopback_endpoint 31305)"
    export SERVER_NAME="${domain}"
    export UPSTREAM_URL="${upstream_url}"
    export UPSTREAM_HOST_HEADER="${host_header}"
    export UPSTREAM_TLS_NAME="${tls_name}"
    export NGINX_XHTTP_PATH="/${path}"
    export NGINX_CLIENT_HEADER_TIMEOUT="30s"
    export NGINX_CLIENT_BODY_TIMEOUT="1h"
    export NGINX_KEEPALIVE_TIMEOUT="75s"
    export NGINX_GRPC_TIMEOUT="1h"
    export NGINX_PROXY_CONNECT_TIMEOUT="10s"
    export NGINX_PROXY_TIMEOUT="60s"
    export XRAY_DOLLAR='$'
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/nginx/alone.conf.tpl" "${nginxConfigPath}alone.conf"
}

xray_agent_nginx_capability_summary() {
    command -v nginx >/dev/null 2>&1 || return 0
    local nginx_build
    nginx_build="$(nginx -V 2>&1 || true)"
    if [[ "${nginx_build}" != *"--with-http_v2_module"* ]]; then
        echoContent yellow " ---> Nginx 未显式编译 http_v2_module，XHTTP/gRPC 转发可能不可用。"
    fi
    if [[ "${nginx_build}" != *"--with-stream"* ]]; then
        echoContent yellow " ---> Nginx 未显式编译 stream 模块，443 共用分流可能不可用。"
    fi
    if [[ "${nginx_build}" != *"--with-stream_ssl_preread_module"* ]]; then
        echoContent yellow " ---> Nginx 未显式编译 stream_ssl_preread_module，Reality/TLS SNI 分流可能不可用。"
    fi
}

xray_agent_nginx_backup_dir() {
    printf '%s\n' "${XRAY_AGENT_NGINX_BACKUP_DIR:-/etc/xray-agent}"
}

backupNginxConfig() {
    local action="$1"
    local backup_dir
    backup_dir="$(xray_agent_nginx_backup_dir)"
    if [[ "${action}" == "backup" ]]; then
        mkdir -p "${backup_dir}"
        rm -f "${backup_dir}/alone_backup.conf" "${backup_dir}/alone_backup.stream"
        rm -f "${backup_dir}/alone_backup.conf.missing" "${backup_dir}/alone_backup.stream.missing"
        if [[ -f "${nginxConfigPath}alone.conf" ]]; then
            cp "${nginxConfigPath}alone.conf" "${backup_dir}/alone_backup.conf"
        else
            : >"${backup_dir}/alone_backup.conf.missing"
        fi
        if [[ -f "${nginxConfigPath}alone.stream" ]]; then
            cp "${nginxConfigPath}alone.stream" "${backup_dir}/alone_backup.stream"
        else
            : >"${backup_dir}/alone_backup.stream.missing"
        fi
    fi
    if [[ "${action}" == "restoreBackup" ]]; then
        if [[ -f "${backup_dir}/alone_backup.conf" ]]; then
            cp "${backup_dir}/alone_backup.conf" "${nginxConfigPath}alone.conf"
            rm -f "${backup_dir}/alone_backup.conf"
        elif [[ -f "${backup_dir}/alone_backup.conf.missing" ]]; then
            rm -f "${nginxConfigPath}alone.conf" "${backup_dir}/alone_backup.conf.missing"
        fi
        if [[ -f "${backup_dir}/alone_backup.stream" ]]; then
            cp "${backup_dir}/alone_backup.stream" "${nginxConfigPath}alone.stream"
            rm -f "${backup_dir}/alone_backup.stream"
        elif [[ -f "${backup_dir}/alone_backup.stream.missing" ]]; then
            rm -f "${nginxConfigPath}alone.stream" "${backup_dir}/alone_backup.stream.missing"
        fi
    fi
    if [[ "${action}" == "cleanupBackup" ]]; then
        rm -f \
            "${backup_dir}/alone_backup.conf" \
            "${backup_dir}/alone_backup.stream" \
            "${backup_dir}/alone_backup.conf.missing" \
            "${backup_dir}/alone_backup.stream.missing"
    fi
}

xray_agent_nginx_test_config() {
    if command -v nginx >/dev/null 2>&1; then
        nginx -t >/tmp/xray-agent-nginx-test.log 2>&1
    else
        return 0
    fi
}

xray_agent_nginx_create_reverse_proxy_backup() {
    local backup_dir proxy_file
    backup_dir="$(mktemp -d)"
    proxy_file="$(xray_agent_nginx_reverse_proxy_file)"
    if [[ -f "${proxy_file}" ]]; then
        cp "${proxy_file}" "${backup_dir}/reverse_proxies.custom.json"
    else
        : >"${backup_dir}/reverse_proxies.custom.json.missing"
    fi
    printf '%s\n' "${backup_dir}"
}

xray_agent_nginx_restore_reverse_proxy_backup() {
    local backup_dir="$1"
    local proxy_file proxy_dir
    [[ -n "${backup_dir}" && -d "${backup_dir}" ]] || return 0
    proxy_file="$(xray_agent_nginx_reverse_proxy_file)"
    proxy_dir="$(dirname "${proxy_file}")"
    if [[ -f "${backup_dir}/reverse_proxies.custom.json" ]]; then
        mkdir -p "${proxy_dir}"
        cp "${backup_dir}/reverse_proxies.custom.json" "${proxy_file}"
    elif [[ -f "${backup_dir}/reverse_proxies.custom.json.missing" ]]; then
        rm -f "${proxy_file}"
    fi
}

xray_agent_nginx_cleanup_reverse_proxy_backup() {
    local backup_dir="$1"
    [[ -n "${backup_dir}" ]] || return 0
    rm -rf "${backup_dir}"
}

xray_agent_nginx_apply_with_rollback() {
    local render_stream="${1:-auto}"
    local accept_proxy_protocol="false"
    local json_backup_dir json_backup_owned="false"
    if [[ -n "${XRAY_AGENT_NGINX_JSON_ROLLBACK_DIR:-}" ]]; then
        json_backup_dir="${XRAY_AGENT_NGINX_JSON_ROLLBACK_DIR}"
    else
        json_backup_dir="$(xray_agent_nginx_create_reverse_proxy_backup)"
        json_backup_owned="true"
    fi
    backupNginxConfig backup
    xray_agent_render_nginx_alone_conf "Vision" "https://huggingface.co"
    if [[ "${render_stream}" == "y" || ( "${render_stream}" == "auto" && -f "${nginxConfigPath}alone.stream" ) ]]; then
        xray_agent_render_nginx_stream_conf "y"
        accept_proxy_protocol="$(xray_agent_nginx_resolved_proxy_protocol_bool)"
    fi
    if ! xray_agent_nginx_test_config; then
        echoContent red " ---> nginx -t 失败，已回滚。"
        [[ -f /tmp/xray-agent-nginx-test.log ]] && tail -n 20 /tmp/xray-agent-nginx-test.log
        backupNginxConfig restoreBackup
        xray_agent_nginx_restore_reverse_proxy_backup "${json_backup_dir}"
        [[ "${json_backup_owned}" == "true" ]] && xray_agent_nginx_cleanup_reverse_proxy_backup "${json_backup_dir}"
        return 1
    fi
    xray_agent_nginx_sync_xray_proxy_protocol "${accept_proxy_protocol}"
    backupNginxConfig cleanupBackup
    [[ "${json_backup_owned}" == "true" ]] && xray_agent_nginx_cleanup_reverse_proxy_backup "${json_backup_dir}"
    handleNginx stop
    handleNginx start
    if [[ -n "${coreInstallType:-}" ]]; then
        reloadCore
    fi
}

xray_agent_nginx_apply_reverse_proxy_update() {
    local updated_json="$1"
    local render_stream="${2:-auto}"
    local json_backup_dir previous_rollback_dir previous_rollback_set="false" apply_status
    if [[ "${XRAY_AGENT_NGINX_JSON_ROLLBACK_DIR+x}" == "x" ]]; then
        previous_rollback_set="true"
        previous_rollback_dir="${XRAY_AGENT_NGINX_JSON_ROLLBACK_DIR}"
    fi
    json_backup_dir="$(xray_agent_nginx_create_reverse_proxy_backup)"
    export XRAY_AGENT_NGINX_JSON_ROLLBACK_DIR="${json_backup_dir}"
    xray_agent_nginx_save_reverse_proxy_json "${updated_json}"
    if xray_agent_nginx_apply_with_rollback "${render_stream}"; then
        apply_status=0
    else
        apply_status=$?
    fi
    xray_agent_nginx_cleanup_reverse_proxy_backup "${json_backup_dir}"
    if [[ "${previous_rollback_set}" == "true" ]]; then
        export XRAY_AGENT_NGINX_JSON_ROLLBACK_DIR="${previous_rollback_dir}"
    else
        unset XRAY_AGENT_NGINX_JSON_ROLLBACK_DIR
    fi
    return "${apply_status}"
}

xray_agent_nginx_xray_frontdoor_config_files() {
    printf '%s\n' \
        "${configPath:-/etc/xray-agent/xray/conf/}02_VLESS_TCP_inbounds.json" \
        "${configPath:-/etc/xray-agent/xray/conf/}07_VLESS_Reality_TCP_inbounds.json"
}

xray_agent_nginx_sync_xray_proxy_protocol() {
    local accept_proxy_protocol="${1:-false}"
    local configfile
    [[ "${accept_proxy_protocol}" == "true" ]] || accept_proxy_protocol="false"
    while IFS= read -r configfile; do
        [[ -f "${configfile}" ]] || continue
        jq -e '.inbounds[0]? != null' "${configfile}" >/dev/null 2>&1 || continue
        xray_agent_json_update_file "${configfile}" '
          .inbounds[0].streamSettings = (
            (.inbounds[0].streamSettings // {})
            | .rawSettings = ((.rawSettings // {}) + {acceptProxyProtocol:$acceptProxyProtocol})
            | .sockopt = ((.sockopt // {}) + {acceptProxyProtocol:$acceptProxyProtocol})
          )
        ' --argjson acceptProxyProtocol "${accept_proxy_protocol}"
    done < <(xray_agent_nginx_xray_frontdoor_config_files)
}

xray_agent_cleanup_default_nginx_site() {
    rm -f "${nginxConfigPath}default.conf"
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default
}

xray_agent_render_nginx_stream_conf() {
    local reuse_443="$1"
    if [[ "${reuse_443}" != "y" ]]; then
        rm -f "${nginxConfigPath}alone.stream"
        return 0
    fi

    local formattedRealityServerNames realityDomainConfig="" legacyDomainConfig="" legacyUpstreams=""
    local proxy_json legacy_index server_name target backend_name proxy_mode
    formattedRealityServerNames=$(echo "${RealityServerNames}" | sed 's/"//g' | sed 's/,/ /g')
    for name in $formattedRealityServerNames; do
        realityDomainConfig="${realityDomainConfig}        ${name} reality_backend;"$'\n'
    done

    proxy_json="$(xray_agent_nginx_reverse_proxy_json)"
    legacy_index=0
    while IFS='|' read -r server_name target; do
        [[ -n "${server_name}" && -n "${target}" ]] || continue
        if ! xray_agent_validate_domain "${server_name}" || ! xray_agent_nginx_validate_stream_target "${target}"; then
            echoContent yellow " ---> 跳过非法 legacy HTTPS 后端: ${server_name} -> ${target}" >&2
            continue
        fi
        legacy_index=$((legacy_index + 1))
        backend_name="legacy_https_backend_${legacy_index}"
        legacyDomainConfig="${legacyDomainConfig}        ${server_name} ${backend_name};"$'\n'
        legacyUpstreams="${legacyUpstreams}    upstream ${backend_name} {"$'\n'
        legacyUpstreams="${legacyUpstreams}        server ${target};"$'\n'
        legacyUpstreams="${legacyUpstreams}    }"$'\n\n'
    done < <(printf '%s\n' "${proxy_json}" | jq -r '.sites[]? | select(.enabled == true and .mode == "stream_tls") | "\(.server_name)|\(.upstream)"')

    proxy_mode="$(xray_agent_nginx_resolved_proxy_protocol_mode)"
    export NGINX_STREAM_DEFAULT_TARGET="vision_backend"
    export NGINX_STREAM_SERVER_NAME_MAP="        ${domain} vision_backend;"$'\n'"${realityDomainConfig}${legacyDomainConfig}"
    export NGINX_STREAM_VISION_TARGET="$(xray_agent_loopback_endpoint "${Port}")"
    export NGINX_STREAM_REALITY_TARGET="$(xray_agent_loopback_endpoint "${RealityPort:-443}")"
    export NGINX_STREAM_PORT="443"
    export NGINX_STREAM_EXTRA_UPSTREAMS="${legacyUpstreams}"
    export NGINX_STREAM_PROXY_PROTOCOL_DIRECTIVE=""
    if [[ "${proxy_mode}" == "on" ]]; then
        NGINX_STREAM_PROXY_PROTOCOL_DIRECTIVE="        proxy_protocol on;"
    fi
    export NGINX_STREAM_LISTEN_DIRECTIVES
    NGINX_STREAM_LISTEN_DIRECTIVES="$(xray_agent_nginx_stream_listen_directives "${NGINX_STREAM_PORT}")"
    export XRAY_DOLLAR='$'
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/nginx/alone.stream.tpl" "${nginxConfigPath}alone.stream"
}
