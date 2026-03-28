handleNginx() {
    if [[ -z $(pgrep -f "nginx") ]] && [[ "$1" == "start" ]]; then
        systemctl start nginx 2>/etc/xray-agent/nginx_error.log
        sleep 0.5
        if [[ -z $(pgrep -f nginx) ]]; then
            xray_agent_error " ---> Nginx启动失败"
        fi
    elif [[ -n $(pgrep -f "nginx") ]] && [[ "$1" == "stop" ]]; then
        systemctl stop nginx
        sleep 0.5
        if [[ -n $(pgrep -f "nginx") ]]; then
            pgrep -f "nginx" | xargs kill -9
        fi
    fi
}

xray_agent_render_nginx_alone_conf() {
    local profile_name="$1"
    local upstream_url="${2:-https://www.kaggle.com}"
    export NGINX_HTTP_PORT="127.0.0.1:31300 http2 so_keepalive=on"
    export SERVER_NAME="${domain}"
    export UPSTREAM_URL="${upstream_url}"
    export NGINX_XHTTP_PATH="/${path}"
    export XRAY_DOLLAR='$'
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/nginx/alone.conf.tpl" "${nginxConfigPath}alone.conf"
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
        realityDomainConfig="${realityDomainConfig}        ${name} reality_backend;\n"
    done

    export NGINX_STREAM_DEFAULT_TARGET="vision_backend"
    export NGINX_STREAM_SERVER_NAME_MAP="        ${domain} vision_backend;\n${realityDomainConfig}"
    export NGINX_STREAM_VISION_TARGET="127.0.0.1:${Port}"
    export NGINX_STREAM_REALITY_TARGET="127.0.0.1:${RealityPort:-443}"
    export NGINX_STREAM_PORT="443"
    export XRAY_DOLLAR='$'
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/nginx/alone.stream.tpl" "${nginxConfigPath}alone.stream"
}

updateRedirectNginxConf() {
    echoContent skyBlue "\n进度  $2/${totalProgress} : 配置镜像站点，默认使用kaggle官网"
    rm -f "${nginxConfigPath}default.conf"
    xray_agent_render_nginx_alone_conf "$1" "https://www.kaggle.com"
    if ([[ "${coreInstallType}" == "1" ]] && [[ "$1" == "Reality" ]]) || ([[ "${coreInstallType}" == "2" ]] && [[ "$1" == "Vision" ]]) || [[ "${coreInstallType}" == "3" ]]; then
        echoContent red "\n=============================================================="
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
