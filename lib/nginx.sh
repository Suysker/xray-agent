#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_render_nginx_alone_conf() {
    local profile_name="$1"
    local upstream_url="${2:-https://huggingface.co}"
    export NGINX_HTTP_PORT="$(xray_agent_loopback_endpoint 31300) http2 so_keepalive=on"
    export NGINX_XHTTP_GRPC_TARGET="$(xray_agent_loopback_endpoint 31305)"
    export SERVER_NAME="${domain}"
    export UPSTREAM_URL="${upstream_url}"
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

updateRedirectNginxConf() {
    xray_agent_blank
    echoContent skyBlue "进度  $2/${totalProgress} : 配置镜像站点，默认使用huggingface官网"
    rm -f "${nginxConfigPath}default.conf"
    if declare -F xray_agent_cleanup_default_nginx_site >/dev/null 2>&1; then
        xray_agent_cleanup_default_nginx_site
    fi
    if [[ "$1" == "Vision" ]]; then
        xray_agent_render_nginx_alone_conf "$1" "https://huggingface.co"
    fi
    if ([[ "${coreInstallType}" == "1" ]] && [[ "$1" == "Reality" ]]) || ([[ "${coreInstallType}" == "2" ]] && [[ "$1" == "Vision" ]]) || [[ "${coreInstallType}" == "3" ]]; then
        xray_agent_blank
        echoContent red "=============================================================="
        echoContent red "检测到能够共用443端口的条件，是否共用？[y/n]:"
        echoContent red "=============================================================="
        read -r -p "请选择:" reuse443
        if [[ "${reuse443}" == "y" ]]; then
            if [[ "${Port}" == "443" ]]; then
                customPortFunction "Vision"
            fi
            if [[ "${RealityPort}" == "443" ]]; then
                customPortFunction "Reality"
            fi
        fi
    fi
    xray_agent_render_nginx_stream_conf "${reuse443}"
    xray_agent_nginx_capability_summary
    if ! xray_agent_nginx_test_config; then
        echoContent red " ---> nginx -t 失败，请检查 Nginx 是否支持 http_v2/grpc/stream/ssl_preread。"
        [[ -f /tmp/xray-agent-nginx-test.log ]] && tail -n 20 /tmp/xray-agent-nginx-test.log
        return 1
    fi
    handleNginx stop
    handleNginx start
}

backupNginxConfig() {
    if [[ "$1" == "backup" ]]; then
        cp "${nginxConfigPath}alone.conf" /etc/xray-agent/alone_backup.conf
    fi
    if [[ "$1" == "restoreBackup" ]] && [[ -f "/etc/xray-agent/alone_backup.conf" ]]; then
        cp /etc/xray-agent/alone_backup.conf "${nginxConfigPath}alone.conf"
        rm /etc/xray-agent/alone_backup.conf
    fi
}

xray_agent_nginx_current_upstream_url() {
    local nginx_file="${nginxConfigPath}alone.conf"
    [[ -f "${nginx_file}" ]] || return 0
    awk '$1 == "proxy_pass" && $2 ~ /^https?:\/\// {gsub(";","",$2); print $2; exit}' "${nginx_file}"
}

xray_agent_nginx_normalize_upstream_url() {
    local upstream_url="$1"
    if [[ "${upstream_url}" != http://* && "${upstream_url}" != https://* ]]; then
        upstream_url="https://${upstream_url}"
    fi
    printf '%s\n' "${upstream_url}"
}

xray_agent_nginx_validate_upstream_url() {
    [[ "$1" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?(/.*)?$ ]]
}

xray_agent_nginx_test_config() {
    if command -v nginx >/dev/null 2>&1; then
        nginx -t >/tmp/xray-agent-nginx-test.log 2>&1
    else
        return 0
    fi
}

updateNginxBlog() {
    if [[ "${coreInstallType}" != "1" ]] && [[ "${coreInstallType}" != "3" ]]; then
        xray_agent_error " ---> 未安装，请使用脚本安装"
    fi
    xray_agent_tool_status_header "更换伪装站"
    if [[ -f "${nginxConfigPath}alone.conf" ]]; then
        local current_upstream input_upstream mirror_url
        current_upstream="$(xray_agent_nginx_current_upstream_url)"
        echoContent yellow "当前伪装站: ${current_upstream:-未检测到}"
        read -r -p "请输入新的伪装站URL或域名[回车取消]:" input_upstream
        [[ -n "${input_upstream}" ]] || {
            echoContent yellow " ---> 已取消"
            return 0
        }
        mirror_url="$(xray_agent_nginx_normalize_upstream_url "${input_upstream}")"
        if ! xray_agent_nginx_validate_upstream_url "${mirror_url}"; then
            echoContent red " ---> URL 不合法，示例: https://www.example.com/"
            return 0
        fi
        echoContent yellow "将把伪装站从 ${current_upstream:-未知} 改为 ${mirror_url}"
        if ! xray_agent_confirm "确认继续？[y/N]:" "n"; then
            echoContent yellow " ---> 已取消"
            return 0
        fi
        backupNginxConfig backup
        xray_agent_render_nginx_alone_conf "Vision" "${mirror_url}"
        if ! xray_agent_nginx_test_config; then
            echoContent red " ---> nginx -t 失败，已回滚。"
            [[ -f /tmp/xray-agent-nginx-test.log ]] && tail -n 20 /tmp/xray-agent-nginx-test.log
            backupNginxConfig restoreBackup
            return 1
        fi
        handleNginx stop
        handleNginx start
        if [[ -z $(pgrep -f nginx) ]]; then
            backupNginxConfig restoreBackup
            handleNginx start
            exit 0
        fi
    else
        echoContent red " ---> 未安装"
    fi
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

    local formattedRealityServerNames realityDomainConfig=""
    formattedRealityServerNames=$(echo "${RealityServerNames}" | sed 's/"//g' | sed 's/,/ /g')
    for name in $formattedRealityServerNames; do
        realityDomainConfig="${realityDomainConfig}        ${name} reality_backend;"$'\n'
    done

    export NGINX_STREAM_DEFAULT_TARGET="vision_backend"
    export NGINX_STREAM_SERVER_NAME_MAP="        ${domain} vision_backend;"$'\n'"${realityDomainConfig}"
    export NGINX_STREAM_VISION_TARGET="$(xray_agent_loopback_endpoint "${Port}")"
    export NGINX_STREAM_REALITY_TARGET="$(xray_agent_loopback_endpoint "${RealityPort:-443}")"
    export NGINX_STREAM_PORT="443"
    export NGINX_STREAM_LISTEN_DIRECTIVES
    NGINX_STREAM_LISTEN_DIRECTIVES="$(xray_agent_nginx_stream_listen_directives "${NGINX_STREAM_PORT}")"
    export XRAY_DOLLAR='$'
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/nginx/alone.stream.tpl" "${nginxConfigPath}alone.stream"
}
