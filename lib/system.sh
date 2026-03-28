xray_agent_source_optional_file() {
    local file_path="$1"
    if [[ -r "${file_path}" ]]; then
        source "${file_path}"
    fi
}

xray_agent_init_repo_skeleton() {
    xray_agent_ensure_dir "${XRAY_AGENT_LIB_DIR}"
    xray_agent_ensure_dir "${XRAY_AGENT_TEMPLATE_DIR}/xray"
    xray_agent_ensure_dir "${XRAY_AGENT_TEMPLATE_DIR}/nginx"
    xray_agent_ensure_dir "${XRAY_AGENT_PROFILE_DIR}"
    xray_agent_ensure_dir "${XRAY_AGENT_DOCS_DIR}"
    xray_agent_ensure_dir "${XRAY_AGENT_FEATURE_DIR}"
}

xray_agent_runtime_dirs() {
    xray_agent_ensure_dir "${XRAY_AGENT_ETC_DIR}"
    xray_agent_ensure_dir "${XRAY_AGENT_TLS_DIR}"
    xray_agent_ensure_dir "${XRAY_AGENT_XRAY_CONF_DIR}"
}

checkSystem() {
    if [[ -n $(find /etc -name "redhat-release") ]] || grep </proc/version -q -i "centos"; then
        mkdir -p /etc/yum.repos.d
        if [[ -f "/etc/centos-release" ]]; then
            centosVersion=$(rpm -q centos-release | awk -F "[-]" '{print $3}' | awk -F "[.]" '{print $1}')
            if [[ -z "${centosVersion}" ]] && grep </etc/centos-release -q -i "release 8"; then
                centosVersion=8
            fi
        fi
        release="centos"
        installType='yum -y install'
        removeType='yum -y remove'
        upgrade="yum update -y --skip-broken"
    elif grep </etc/issue -q -i "debian" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "debian" && [[ -f "/proc/version" ]]; then
        release="debian"
        installType='apt -y install'
        upgrade="apt update"
        updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
        removeType='apt -y autoremove'
    elif grep </etc/issue -q -i "ubuntu" && [[ -f "/etc/issue" ]] || grep </etc/issue -q -i "ubuntu" && [[ -f "/proc/version" ]]; then
        release="ubuntu"
        installType='apt -y install'
        upgrade="apt update"
        updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
        removeType='apt -y autoremove'
        if grep </etc/issue -q -i "16."; then
            release=
        fi
    fi

    if [[ -z ${release} ]]; then
        echoContent red "\n本脚本不支持此系统，请将下方日志反馈给开发者\n"
        echoContent yellow "$(cat /etc/issue)"
        echoContent yellow "$(cat /proc/version)"
        exit 0
    fi
}

checkCPUVendor() {
    if [[ -n $(which uname) ]]; then
        if [[ "$(uname)" == "Linux" ]]; then
            case "$(uname -m)" in
                amd64 | x86_64)
                    xrayCoreCPUVendor="Xray-linux-64"
                    ;;
                armv8 | aarch64)
                    xrayCoreCPUVendor="Xray-linux-arm64-v8a"
                    ;;
                *)
                    echoContent red "不支持此CPU架构"
                    exit 1
                    ;;
            esac
        fi
    else
        echoContent red "无法识别此CPU架构，默认amd64、x86_64"
        xrayCoreCPUVendor="Xray-linux-64"
    fi
}

mkdirTools() {
    mkdir -p /etc/xray-agent/tls
    mkdir -p /etc/xray-agent/xray/conf
    mkdir -p /etc/systemd/system/
}

aliasInstall() {
    if [[ -f "$HOME/install.sh" ]] && [[ -d "/etc/xray-agent" ]] && grep <"$HOME/install.sh" -q "xray-agent"; then
        mv "$HOME/install.sh" /etc/xray-agent/install.sh
        local vasmaType=
        if [[ -d "/usr/bin/" ]]; then
            if [[ ! -f "/usr/bin/vasma" ]]; then
                ln -s /etc/xray-agent/install.sh /usr/bin/vasma
                chmod 700 /usr/bin/vasma
                vasmaType=true
            fi
            rm -rf "$HOME/install.sh"
        elif [[ -d "/usr/sbin" ]]; then
            if [[ ! -f "/usr/sbin/vasma" ]]; then
                ln -s /etc/xray-agent/install.sh /usr/sbin/vasma
                chmod 700 /usr/sbin/vasma
                vasmaType=true
            fi
            rm -rf "$HOME/install.sh"
        fi
        if [[ "${vasmaType}" == "true" ]]; then
            echoContent green "快捷方式创建成功，可执行[vasma]重新打开脚本"
        fi
    fi
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

customPortFunction() {
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
                echoContent yellow "\n ---> ${1}端口: ${port}"
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
            updated_json=$(jq ".inbounds[0].port = ${port}" "${configPath}${frontingType}.json")
            echo "${updated_json}" | jq . >"${configPath}${frontingType}.json"
        fi
        if [[ "${historyCustomPortStatus}" == "n" ]]; then
            rm -rf "$(find ${configPath}* | grep "dokodemodoor")"
        fi
    elif [[ "$1" == "Reality" ]]; then
        RealityPort="${port}"
        if [[ -f "${configPath}${RealityfrontingType}.json" ]]; then
            updated_json=$(jq ".inbounds[0].port = ${port}" "${configPath}${RealityfrontingType}.json")
            echo "${updated_json}" | jq . >"${configPath}${RealityfrontingType}.json"
        fi
    fi
}

checkPort() {
    port="$1"
    port_progress=$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $1; exit}')
    if [[ -n "${port_progress}" && "${port_progress}" != "xray" ]]; then
        xray_agent_error "\n ---> ${port}端口被占用，请手动关闭后安装\n"
    fi
}

AdguardManageMenu() {
    echoContent skyBlue "\nAdguardhome管理"
    echoContent red "\n=============================================================="
    echoContent yellow "1.安装Adguardhome"
    echoContent yellow "2.升级Adguardhome"
    echoContent yellow "3.卸载Adguardhome"
    echoContent yellow "4.关闭Adguardhome"
    echoContent yellow "5.打开Adguardhome"
    echoContent yellow "6.重启Adguardhome"
    echoContent red "=============================================================="
    if [[ "${xrayCoreCPUVendor}" == "Xray-linux-64" ]]; then
        adgCoreCPUVendor="AdGuardHome_linux_amd64"
    elif [[ "${xrayCoreCPUVendor}" == "Xray-linux-arm64-v8a" ]]; then
        adgCoreCPUVendor="AdGuardHome_linux_arm64"
    fi
    read -r -p "请选择:" selectADGType
    if [[ "${selectADGType}" == "1" ]]; then
        if [[ -f "/opt/AdGuardHome/AdGuardHome" ]]; then
            xray_agent_error " ---> 检测到安装目录，请执行脚本卸载操作"
        fi
        curl -sSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh
    fi
    if [[ ! -f "/opt/AdGuardHome/AdGuardHome" ]]; then
        xray_agent_error " ---> 没有检测到安装目录，请先安装Adguardhome"
    else
        if ! grep -q "DNSStubListener=no" /etc/systemd/resolved.conf; then
            sudo sed -i '/\[Resolve\]/a DNSStubListener=no' /etc/systemd/resolved.conf
            sudo systemctl restart systemd-resolved
        fi
        systemctl start AdGuardHome
        systemctl enable AdGuardHome
    fi
    case "${selectADGType}" in
        2)
            wget -O '/tmp/AdGuardHome_linux_amd64.tar.gz' "https://static.adguard.com/adguardhome/release/${adgCoreCPUVendor}.tar.gz"
            tar -C /tmp/ -f /tmp/AdGuardHome_linux_amd64.tar.gz -x -v -z
            systemctl stop AdGuardHome
            cp /tmp/AdGuardHome/AdGuardHome /opt/AdGuardHome/AdGuardHome
            systemctl start AdGuardHome
            systemctl enable AdGuardHome
            ;;
        3)
            /opt/AdGuardHome/AdGuardHome -s uninstall
            rm -rf /opt/AdGuardHome
            ;;
        4)
            systemctl stop AdGuardHome
            systemctl disable AdGuardHome
            ;;
        5)
            systemctl start AdGuardHome
            systemctl enable AdGuardHome
            ;;
        6)
            systemctl restart AdGuardHome
            systemctl enable AdGuardHome
            ;;
    esac
}

unInstall() {
    read -r -p "是否确认卸载安装内容？[y/n]:" unInstallStatus
    if [[ "${unInstallStatus}" != "y" ]]; then
        echoContent green " ---> 放弃卸载"
        return 0
    fi
    handleNginx stop
    if [[ -n "${coreInstallType}" ]]; then
        handleXray stop
        rm -rf /etc/systemd/system/xray.service
    fi
    crontab -l | grep -v 'auto_update_geodata.sh' | crontab -
    crontab -l | grep -v 'install.sh RenewTLS' | crontab -
    rm -rf /etc/xray-agent
    rm -rf "${nginxConfigPath}alone.conf"
    rm -rf "${nginxConfigPath}alone.stream"
    rm -rf /usr/bin/vasma
    rm -rf /usr/sbin/vasma
}
