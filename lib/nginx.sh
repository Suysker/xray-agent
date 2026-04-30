#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_render_nginx_alone_conf() {
    local profile_name="$1"
    local upstream_url="${2:-https://huggingface.co}"
    export NGINX_HTTP_PORT="127.0.0.1:31300 http2 so_keepalive=on"
    export SERVER_NAME="${domain}"
    export UPSTREAM_URL="${upstream_url}"
    export NGINX_XHTTP_PATH="/${path}"
    export XRAY_DOLLAR='$'
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/nginx/alone.conf.tpl" "${nginxConfigPath}alone.conf"
}

updateRedirectNginxConf() {
    xray_agent_blank
    echoContent skyBlue "进度  $2/${totalProgress} : 配置镜像站点，默认使用kaggle官网"
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

updateNginxBlog() {
    if [[ "${coreInstallType}" != "1" ]] && [[ "${coreInstallType}" != "3" ]]; then
        xray_agent_error " ---> 未安装，请使用脚本安装"
    fi
    if [[ -f "${nginxConfigPath}alone.conf" ]]; then
        read -r -p "请输入要镜像的域名,例如 www.baidu.com，无http/https:" mirrorDomain
        currentmirrorDomain=$(grep -m 1 "proxy_pass https://*" "${nginxConfigPath}alone.conf" | sed 's/;//' | awk -F "//" '{print $2}')
        backupNginxConfig backup
        sed -i "s/${currentmirrorDomain}/${mirrorDomain}/g" "${nginxConfigPath}alone.conf"
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
    export NGINX_STREAM_VISION_TARGET="127.0.0.1:${Port}"
    export NGINX_STREAM_REALITY_TARGET="127.0.0.1:${RealityPort:-443}"
    export NGINX_STREAM_PORT="443"
    export XRAY_DOLLAR='$'
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/nginx/alone.stream.tpl" "${nginxConfigPath}alone.stream"
}
