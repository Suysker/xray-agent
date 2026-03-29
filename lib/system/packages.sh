if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

mkdirTools() {
    mkdir -p /etc/xray-agent/tls
    mkdir -p /etc/xray-agent/xray/conf
    mkdir -p /etc/systemd/system/
}

installNginxTools() {
    if [[ "${release}" == "debian" ]]; then
        sudo apt install gnupg2 ca-certificates lsb-release -y >/dev/null 2>&1
        echo "deb http://nginx.org/packages/mainline/debian $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
        echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx >/dev/null 2>&1
        curl -o /tmp/nginx_signing.key https://nginx.org/keys/nginx_signing.key >/dev/null 2>&1
        sudo mv /tmp/nginx_signing.key /etc/apt/trusted.gpg.d/nginx_signing.asc
        sudo apt update >/dev/null 2>&1
    elif [[ "${release}" == "ubuntu" ]]; then
        sudo apt install gnupg2 ca-certificates lsb-release -y >/dev/null 2>&1
        echo "deb http://nginx.org/packages/mainline/ubuntu $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
        echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | sudo tee /etc/apt/preferences.d/99nginx >/dev/null 2>&1
        curl -o /tmp/nginx_signing.key https://nginx.org/keys/nginx_signing.key >/dev/null 2>&1
        sudo mv /tmp/nginx_signing.key /etc/apt/trusted.gpg.d/nginx_signing.asc
        sudo apt update >/dev/null 2>&1
    elif [[ "${release}" == "centos" ]]; then
        ${installType} yum-utils >/dev/null 2>&1
        cat <<EOF >/etc/yum.repos.d/nginx.repo
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF
        sudo yum-config-manager --enable nginx-mainline >/dev/null 2>&1
    fi
    ${installType} nginx >/dev/null 2>&1
    systemctl daemon-reload
    systemctl enable nginx
}

installTools() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : 安装工具"
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
