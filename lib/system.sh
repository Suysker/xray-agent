#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

mkdirTools() {
    mkdir -p /etc/xray-agent/tls
    mkdir -p /etc/xray-agent/xray/conf
    mkdir -p /etc/systemd/system/
}

xray_agent_write_nginx_apt_source() {
    local distro="$1"
    local codename="$2"
    printf 'deb http://nginx.org/packages/mainline/%s %s nginx\n' "${distro}" "${codename}" |
        sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
}

xray_agent_write_nginx_apt_preferences() {
    {
        printf 'Package: *\n'
        printf 'Pin: origin nginx.org\n'
        printf 'Pin: release o=nginx\n'
        printf 'Pin-Priority: 900\n'
    } | sudo tee /etc/apt/preferences.d/99nginx >/dev/null 2>&1
}

xray_agent_write_nginx_yum_repo() {
    {
        printf '[nginx-stable]\n'
        printf 'name=nginx stable repo\n'
        printf 'baseurl=http://nginx.org/packages/centos/$releasever/$basearch/\n'
        printf 'gpgcheck=1\n'
        printf 'enabled=1\n'
        printf 'gpgkey=https://nginx.org/keys/nginx_signing.key\n'
        printf 'module_hotfixes=true\n\n'
        printf '[nginx-mainline]\n'
        printf 'name=nginx mainline repo\n'
        printf 'baseurl=http://nginx.org/packages/mainline/centos/$releasever/$basearch/\n'
        printf 'gpgcheck=1\n'
        printf 'enabled=0\n'
        printf 'gpgkey=https://nginx.org/keys/nginx_signing.key\n'
        printf 'module_hotfixes=true\n'
    } | sudo tee /etc/yum.repos.d/nginx.repo >/dev/null 2>&1
}

installNginxTools() {
    if [[ "${release}" == "debian" ]]; then
        sudo apt install gnupg2 ca-certificates lsb-release -y >/dev/null 2>&1
        xray_agent_write_nginx_apt_source "debian" "$(lsb_release -cs)"
        xray_agent_write_nginx_apt_preferences
        curl -o /tmp/nginx_signing.key https://nginx.org/keys/nginx_signing.key >/dev/null 2>&1
        sudo mv /tmp/nginx_signing.key /etc/apt/trusted.gpg.d/nginx_signing.asc
        sudo apt update >/dev/null 2>&1
    elif [[ "${release}" == "ubuntu" ]]; then
        sudo apt install gnupg2 ca-certificates lsb-release -y >/dev/null 2>&1
        xray_agent_write_nginx_apt_source "ubuntu" "$(lsb_release -cs)"
        xray_agent_write_nginx_apt_preferences
        curl -o /tmp/nginx_signing.key https://nginx.org/keys/nginx_signing.key >/dev/null 2>&1
        sudo mv /tmp/nginx_signing.key /etc/apt/trusted.gpg.d/nginx_signing.asc
        sudo apt update >/dev/null 2>&1
    elif [[ "${release}" == "centos" ]]; then
        ${installType} yum-utils >/dev/null 2>&1
        xray_agent_write_nginx_yum_repo
        sudo yum-config-manager --enable nginx-mainline >/dev/null 2>&1
    fi
    ${installType} nginx >/dev/null 2>&1
    systemctl daemon-reload
    systemctl enable nginx
}

installTools() {
    xray_agent_blank
    echoContent skyBlue "进度  $1/${totalProgress} : 安装工具"
    mkdirTools
    if [[ "${release}" == "ubuntu" ]]; then
        dpkg --configure -a
    fi
    if pgrep -f "apt" >/dev/null 2>&1; then
        pgrep -f apt | xargs kill -9
    fi
    echoContent green " ---> 检查、安装更新【新机器会很慢，如长时间无反应，请手动停止后重新执行】"
    ${upgrade} >/etc/xray-agent/install.log 2>&1
    if [[ -n "${updateReleaseInfoChange}" ]] && grep -q "changed" "/etc/xray-agent/install.log"; then
        ${updateReleaseInfoChange} >/dev/null 2>&1
    fi
    if [[ "${release}" == "centos" ]]; then
        rm -rf /var/run/yum.pid
        ${installType} epel-release >/dev/null 2>&1
    fi
    declare -a tools=("wget" "curl" "unzip" "tar" "cron" "jq" "ld" "lsb_release" "sudo" "lsof" "dig")
    for tool in "${tools[@]}"; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            if [[ "${tool}" == "cron" ]]; then
                if [[ "${release}" == "ubuntu" ]] || [[ "${release}" == "debian" ]]; then
                    ${installType} cron >/dev/null 2>&1
                else
                    ${installType} crontabs >/dev/null 2>&1
                fi
            elif [[ "${tool}" == "ld" ]]; then
                ${installType} binutils >/dev/null 2>&1
            elif [[ "${tool}" == "lsb_release" ]]; then
                ${installType} lsb-release >/dev/null 2>&1
            elif [[ "${tool}" == "dig" ]]; then
                if echo "${installType}" | grep -q -w "apt"; then
                    ${installType} dnsutils >/dev/null 2>&1
                else
                    ${installType} bind-utils >/dev/null 2>&1
                fi
            else
                ${installType} "${tool}" >/dev/null 2>&1
            fi
        fi
    done

    if ! command -v nginx >/dev/null 2>&1; then
        installNginxTools
    else
        nginxVersion=$(nginx -v 2>&1)
        nginxVersion=$(echo "${nginxVersion}" | awk -F "[n][g][i][n][x][/]" '{print $2}' | awk -F "[.]" '{print $2}')
        if [[ ${nginxVersion} -lt 14 ]]; then
            if xray_agent_confirm "读取到当前的Nginx版本不支持gRPC，会导致安装失败，是否卸载Nginx后重新安装 ？[y/n]:" "n"; then
                ${removeType} nginx >/dev/null 2>&1
                installNginxTools >/dev/null 2>&1
            else
                exit 0
            fi
        fi
    fi

    if ! command -v semanage >/dev/null 2>&1; then
        ${installType} bash-completion >/dev/null 2>&1
        if [[ "${centosVersion}" == "7" ]]; then
            policyCoreUtils="policycoreutils-python.x86_64"
        elif [[ "${centosVersion}" == "8" ]]; then
            policyCoreUtils="policycoreutils-python-utils-2.9-9.el8.noarch"
        fi
        if [[ -n "${policyCoreUtils}" ]]; then
            ${installType} "${policyCoreUtils}" >/dev/null 2>&1
        fi
        if command -v semanage >/dev/null 2>&1; then
            semanage port -a -t http_port_t -p tcp 31300
        fi
    fi

    if [[ ! -d "$HOME/.acme.sh" ]] || [[ -d "$HOME/.acme.sh" && -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
        curl -s https://get.acme.sh | sh >/etc/xray-agent/tls/acme.log 2>&1
        sudo "$HOME/.acme.sh/acme.sh" --upgrade --auto-upgrade
        if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
            tail -n 100 /etc/xray-agent/tls/acme.log
            exit 0
        fi
    fi
}

xray_agent_firewall_comment() {
    echo "xray-agent"
}

checkFirewalldAllowPort() {
    if firewall-cmd --list-ports --permanent | grep -q "$1"; then
        echoContent green " ---> $1端口开放成功"
    else
        echoContent red " ---> $1端口开放失败"
        exit 0
    fi
}

checkUFWAllowPort() {
    if ufw status | grep -q "$1"; then
        echoContent green " ---> $1端口开放成功"
    else
        echoContent red " ---> $1端口开放失败"
        exit 0
    fi
}

allowPort() {
    local port="$1"
    local type="${2:-tcp}"
    if systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
        local update_firewall_status=
        if ! iptables -L | grep -q "${port}"; then
            update_firewall_status=true
            iptables -I INPUT -p "${type}" --dport "${port}" -m comment --comment "allow ${port}($(xray_agent_firewall_comment))" -j ACCEPT
        fi
        if ! ip6tables -L | grep -q "${port}"; then
            update_firewall_status=true
            ip6tables -I INPUT -p "${type}" --dport "${port}" -m comment --comment "allow ${port}($(xray_agent_firewall_comment))" -j ACCEPT
        fi
        if [[ "${update_firewall_status}" == "true" ]]; then
            netfilter-persistent save
        fi
    elif systemctl status ufw 2>/dev/null | grep -q "active (exited)"; then
        if ufw status | grep -q "Status: active" && ! ufw status | grep -q "${port}/${type}"; then
            sudo ufw allow "${port}/${type}"
            sudo ufw allow from any to any proto ipv6 "${type}" port "${port}"
            checkUFWAllowPort "${port}"
        fi
    elif systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
        local update_firewall_status=
        if ! firewall-cmd --list-ports --permanent | grep -qw "${port}/${type}"; then
            update_firewall_status=true
            firewall-cmd --zone=public --add-port="${port}/${type}" --permanent
            firewall-cmd --zone=public --add-port="${port}/${type}" --permanent --add-rich-rule="rule family=ipv6"
            checkFirewalldAllowPort "${port}"
        fi
        if [[ "${update_firewall_status}" == "true" ]]; then
            firewall-cmd --reload
        fi
    fi
}

xray_agent_allow_port_safe() {
    local port="$1"
    local protocol="${2:-tcp}"
    allowPort "${port}" "${protocol}"
}

checkPort() {
    local port="$1"
    local port_progress
    port_progress=$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $1; exit}')
    if [[ -n "${port_progress}" && "${port_progress}" != "xray" ]]; then
        xray_agent_blank
        xray_agent_error " ---> ${port}端口被占用，请手动关闭后安装"
    fi
}

checkUDPPort() {
    local port="$1"
    local port_progress
    port_progress=$(lsof -nP -iUDP:"${port}" 2>/dev/null | awk 'NR>1 {print $1; exit}')
    if [[ -n "${port_progress}" && "${port_progress}" != "xray" ]]; then
        xray_agent_blank
        xray_agent_error " ---> UDP ${port}端口被占用，请手动关闭后安装"
    fi
}

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

handleXray() {
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]] && [[ -n $(find /etc/systemd/system/ -name "xray.service") ]]; then
        if [[ -z $(pgrep -f "xray/xray") ]] && [[ "$1" == "start" ]]; then
            systemctl start xray.service
        elif [[ -n $(pgrep -f "xray/xray") ]] && [[ "$1" == "stop" ]]; then
            systemctl stop xray.service
        fi
    fi
    sleep 0.8
    if [[ "$1" == "start" && -z $(pgrep -f "xray/xray") ]]; then
        xray_agent_error "Xray启动失败"
    fi
    if [[ "$1" == "stop" && -n $(pgrep -f "xray/xray") ]]; then
        xray_agent_error "xray关闭失败"
    fi
}

installXrayService() {
    xray_agent_blank
    echoContent skyBlue "进度  $1/${totalProgress} : 配置Xray开机自启"
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]]; then
        rm -rf /etc/systemd/system/xray.service
        export XRAY_SERVICE_EXEC_START="${ctlPath} run -confdir /etc/xray-agent/xray/conf"
        xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/systemd/xray.service.tpl" /etc/systemd/system/xray.service
        systemctl daemon-reload
        systemctl enable xray.service
    fi
}

customPortFunction() {
    local port historyCustomPortStatus
    if [[ "$1" == "Vision" ]]; then
        port="${Port}"
    elif [[ "$1" == "Reality" ]]; then
        port="${RealityPort}"
    fi

    if [[ -n "${port}" ]]; then
        read -r -p "${1}读取到上次安装时的端口，是否使用上次安装时的端口 ？[y/n]:" historyCustomPortStatus
        if [[ "${historyCustomPortStatus}" == "y" ]]; then
            if [[ "${reuse443}" == "y" && "${port}" == "443" ]]; then
                historyCustomPortStatus="n"
            else
                xray_agent_blank
                echoContent yellow " ---> ${1}端口: ${port}"
            fi
        fi
    fi

    if [[ "${historyCustomPortStatus}" == "n" || -z "${port}" ]]; then
        echoContent yellow "${1}请输入自定义端口[例: 2083]，[回车]使用443"
        read -r -p "端口:" port
        if [[ -n "${port}" ]]; then
            if ((port >= 1 && port <= 65535)); then
                if [[ "${reuse443}" == "y" && "${port}" == "443" ]]; then
                    xray_agent_error " ---> ${1}全局设置为不允许使用端口 443"
                fi
                checkPort "${port}"
            else
                xray_agent_error " ---> ${1}端口输入错误"
            fi
        else
            if [[ "${reuse443}" == "y" ]]; then
                xray_agent_error " ---> ${1}全局设置为不允许使用默认端口 443"
            fi
            port=443
            checkPort "${port}"
        fi
    fi

    allowPort "${port}"

    if [[ "$1" == "Vision" ]]; then
        Port="${port}"
        if [[ -f "${configPath}${frontingType}.json" ]]; then
            xray_agent_json_update_file "${configPath}${frontingType}.json" ".inbounds[0].port = ${port}"
        fi
        if [[ "${historyCustomPortStatus}" == "n" ]]; then
            rm -rf "$(find ${configPath}* | grep "dokodemodoor")"
        fi
    elif [[ "$1" == "Reality" ]]; then
        RealityPort="${port}"
        if [[ -f "${configPath}${RealityfrontingType}.json" ]]; then
            xray_agent_json_update_file "${configPath}${RealityfrontingType}.json" ".inbounds[0].port = ${port}"
        fi
    fi
}

installCronTLS() {
    if [[ -f "/etc/xray-agent/install.sh" ]]; then
        crontab -l >/etc/xray-agent/backup_crontab.cron
        historyCrontab=$(sed '/install.sh/d;/acme.sh/d' /etc/xray-agent/backup_crontab.cron)
        echo "${historyCrontab}" >/etc/xray-agent/backup_crontab.cron
        xray_agent_tls_renew_cron_line >>/etc/xray-agent/backup_crontab.cron
        printf '\n' >>/etc/xray-agent/backup_crontab.cron
        crontab /etc/xray-agent/backup_crontab.cron
    else
        crontab -l | grep -v 'install.sh RenewTLS' | crontab -
    fi
}

xray_agent_tls_renew_cron_line() {
    printf '%s\n' '30 1 * * * /bin/bash /etc/xray-agent/install.sh RenewTLS >> /etc/xray-agent/crontab_tls.log 2>&1'
}

xray_agent_geodata_cron_line() {
    printf '%s\n' '30 1 * * 1 /bin/bash /etc/xray-agent/auto_update_geodata.sh >> /etc/xray-agent/crontab_geo.log 2>&1'
}

xray_agent_write_geodata_update_helper() {
    {
        printf '%s\n' '#!/bin/sh'
        printf '%s\n' 'wget -O /etc/xray-agent/xray/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat && wget -O /etc/xray-agent/xray/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat && systemctl restart xray'
    } >/etc/xray-agent/auto_update_geodata.sh
}

auto_update_geodata() {
    if [[ -f "/etc/xray-agent/xray/xray" ]] || [[ -f "/etc/xray-agent/xray/geosite.dat" ]] || [[ -f "/etc/xray-agent/xray/geoip.dat" ]]; then
        xray_agent_write_geodata_update_helper
        chmod +x /etc/xray-agent/auto_update_geodata.sh
        crontab -l >/etc/xray-agent/backup_crontab.cron
        historyCrontab=$(sed '/auto_update_geodata.sh/d' /etc/xray-agent/backup_crontab.cron)
        echo "${historyCrontab}" >/etc/xray-agent/backup_crontab.cron
        xray_agent_geodata_cron_line >>/etc/xray-agent/backup_crontab.cron
        printf '\n' >>/etc/xray-agent/backup_crontab.cron
        crontab /etc/xray-agent/backup_crontab.cron
    else
        crontab -l | grep -v 'auto_update_geodata.sh' | crontab -
    fi
}

xray_agent_apply_sysctl_defaults() {
    if ! grep -q "net.ipv4.tcp_fastopen=3" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.tcp_fastopen=3" >>/etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1 || true
}
