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

xray_agent_install_context_needs_nginx() {
    case "${XRAY_AGENT_INSTALL_PROFILE_ENTRY:-}" in
        xrayCoreInstall)
            return 0
            ;;
        xrayCoreInstall_Reality)
            return 1
            ;;
        "")
            return 0
            ;;
    esac
    return 0
}

xray_agent_install_context_needs_cert_tools() {
    case "${XRAY_AGENT_INSTALL_PROFILE_ENTRY:-}" in
        xrayCoreInstall)
            return 0
            ;;
        xrayCoreInstall_Reality)
            return 1
            ;;
        "")
            return 0
            ;;
    esac
    return 0
}

xray_agent_ensure_nginx_tools() {
    if ! command -v nginx >/dev/null 2>&1; then
        installNginxTools
    else
        nginxVersion=$(nginx -v 2>&1)
        nginxVersion=$(echo "${nginxVersion}" | awk -F "[n][g][i][n][x][/]" '{print $2}' | awk -F "[.]" '{print $2}')
        if [[ ${nginxVersion} -lt 14 ]]; then
            if xray_agent_confirm_danger "读取到当前的Nginx版本不支持gRPC，会导致安装失败，是否卸载Nginx后重新安装？"; then
                ${removeType} nginx >/dev/null 2>&1
                installNginxTools >/dev/null 2>&1
            else
                echoContent yellow " ---> 已取消"
                exit 0
            fi
        fi
    fi
}

xray_agent_ensure_acme_tools() {
    mkdir -p "${XRAY_AGENT_TLS_DIR}"
    if [[ ! -d "$HOME/.acme.sh" ]] || [[ -d "$HOME/.acme.sh" && -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
        curl -s https://get.acme.sh | sh >"${XRAY_AGENT_TLS_DIR}/acme.log" 2>&1
        sudo "$HOME/.acme.sh/acme.sh" --upgrade --auto-upgrade
        if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
            tail -n 100 "${XRAY_AGENT_TLS_DIR}/acme.log"
            exit 0
        fi
    fi
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
    declare -a tools=("wget" "curl" "unzip" "tar" "cron" "jq" "ld" "lsb_release" "sudo" "lsof" "dig" "ip" "iptables" "ip6tables")
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
            elif [[ "${tool}" == "ip" ]]; then
                if echo "${installType}" | grep -q -w "apt"; then
                    ${installType} iproute2 >/dev/null 2>&1
                else
                    ${installType} iproute >/dev/null 2>&1
                fi
            elif [[ "${tool}" == "iptables" || "${tool}" == "ip6tables" ]]; then
                ${installType} iptables >/dev/null 2>&1
            else
                ${installType} "${tool}" >/dev/null 2>&1
            fi
        fi
    done

    if xray_agent_install_context_needs_nginx; then
        xray_agent_ensure_nginx_tools
    else
        echoContent yellow " ---> 当前安装 profile 不需要 Nginx，跳过 Nginx 安装/版本检查"
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

    if xray_agent_install_context_needs_cert_tools; then
        xray_agent_ensure_acme_tools
    else
        echoContent yellow " ---> 当前安装 profile 不需要 TLS 证书，跳过 acme.sh 安装/升级"
    fi
}

xray_agent_firewall_comment() {
    echo "xray-agent"
}

checkFirewalldAllowPort() {
    local port="$1"
    local type="${2:-tcp}"
    if firewall-cmd --list-ports --permanent | grep -qw "${port}/${type}"; then
        echoContent green " ---> $1端口开放成功"
    else
        echoContent red " ---> $1端口开放失败"
        exit 0
    fi
}

checkUFWAllowPort() {
    local port="$1"
    local type="${2:-tcp}"
    if ufw status | grep -q "${port}/${type}"; then
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
        if command -v iptables >/dev/null 2>&1 && ! iptables -L INPUT -n 2>/dev/null | grep -q "${type}.*dpt:${port}"; then
            update_firewall_status=true
            iptables -I INPUT -p "${type}" --dport "${port}" -m comment --comment "allow ${port}($(xray_agent_firewall_comment))" -j ACCEPT
        fi
        if command -v ip6tables >/dev/null 2>&1 && ! ip6tables -L INPUT -n 2>/dev/null | grep -q "${type}.*dpt:${port}"; then
            update_firewall_status=true
            ip6tables -I INPUT -p "${type}" --dport "${port}" -m comment --comment "allow ${port}($(xray_agent_firewall_comment))" -j ACCEPT
        fi
        if [[ "${update_firewall_status}" == "true" ]]; then
            netfilter-persistent save
        fi
    elif systemctl status ufw 2>/dev/null | grep -q "active (exited)"; then
        if ufw status | grep -q "Status: active" && ! ufw status | grep -q "${port}/${type}"; then
            sudo ufw allow "${port}/${type}"
            checkUFWAllowPort "${port}" "${type}"
        elif ! ufw status | grep -q "Status: active"; then
            echoContent yellow " ---> UFW未启用，跳过防火墙放行"
        fi
    elif systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
        local update_firewall_status=
        if ! firewall-cmd --list-ports --permanent | grep -qw "${port}/${type}"; then
            update_firewall_status=true
            firewall-cmd --zone=public --add-port="${port}/${type}" --permanent
        fi
        if [[ "${update_firewall_status}" == "true" ]]; then
            firewall-cmd --reload
            checkFirewalldAllowPort "${port}" "${type}"
        fi
    else
        echoContent yellow " ---> 未检测到已启用防火墙，跳过${port}/${type}放行"
    fi
}

xray_agent_allow_port_safe() {
    local port="$1"
    local protocol="${2:-tcp}"
    allowPort "${port}" "${protocol}"
}

xray_agent_xray_service_main_pid() {
    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl show -p MainPID --value xray 2>/dev/null |
        awk '$1 ~ /^[0-9]+$/ && $1 != "0" {print $1; exit}'
}

xray_agent_process_is_xray() {
    local command_name="$1"
    local pid="${2:-}"
    local main_pid comm exe cmdline

    case "${command_name}" in
        xray | Xray)
            return 0
            ;;
    esac

    [[ "${pid}" =~ ^[0-9]+$ ]] || return 1

    main_pid="$(xray_agent_xray_service_main_pid || true)"
    if [[ -n "${main_pid}" && "${pid}" == "${main_pid}" ]]; then
        return 0
    fi

    comm="$(ps -p "${pid}" -o comm= 2>/dev/null | awk '{print $1; exit}')"
    case "${comm}" in
        xray | Xray)
            return 0
            ;;
    esac

    exe="$(readlink -f "/proc/${pid}/exe" 2>/dev/null || true)"
    case "${exe}" in
        */xray | */xray-agent/xray/xray)
            return 0
            ;;
    esac

    if [[ -r "/proc/${pid}/cmdline" ]]; then
        cmdline="$(tr '\0' ' ' <"/proc/${pid}/cmdline" 2>/dev/null || true)"
    else
        cmdline=
    fi
    case "${cmdline}" in
        *"/xray run "* | *"/xray/xray run "* | *"/etc/xray-agent/xray/xray "*)
            return 0
            ;;
    esac

    return 1
}

xray_agent_port_owner_label() {
    local command_name="$1"
    local pid="${2:-}"
    local user="${3:-}"
    command_name="${command_name:-process}"
    if [[ -n "${pid}" && -n "${user}" ]]; then
        printf '%s/%s/%s\n' "${command_name}" "${pid}" "${user}"
    elif [[ -n "${pid}" ]]; then
        printf '%s/%s\n' "${command_name}" "${pid}"
    else
        printf '%s\n' "${command_name}"
    fi
}

xray_agent_lsof_port_rows() {
    local protocol="$1"
    local port="$2"
    local lsof_output
    if ! command -v lsof >/dev/null 2>&1; then
        return 0
    fi

    if [[ "${protocol}" == "UDP" ]]; then
        lsof_output="$(lsof -nP -iUDP:"${port}" -F pcL 2>/dev/null || true)"
    else
        lsof_output="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -F pcL 2>/dev/null || true)"
    fi

    if [[ "${lsof_output}" == p* || "${lsof_output}" == *$'\n'p* ]]; then
        awk '
            /^p/ {
                if (pid != "") {
                    print command_name "|" pid "|" user
                }
                pid = substr($0, 2)
                command_name = ""
                user = ""
                next
            }
            /^c/ {
                command_name = substr($0, 2)
                next
            }
            /^L/ {
                user = substr($0, 2)
                next
            }
            END {
                if (pid != "") {
                    print command_name "|" pid "|" user
                }
            }
        ' <<<"${lsof_output}"
        return 0
    fi

    printf '%s\n' "${lsof_output}" | awk '
        NR == 1 && $1 == "COMMAND" {next}
        NF >= 4 {
            if ($1 ~ /^[0-9]+$/ && $2 ~ /^[^[:space:]]+$/ && $3 ~ /^[0-9]+[a-zA-Z]*$/) {
                print "" "|" $1 "|" $2
            } else {
                print $1 "|" $2 "|" $3
            }
        }
    '
}

checkPort() {
    local port="$1"
    local command_name pid user blocked_owner xray_owner
    while IFS='|' read -r command_name pid user; do
        [[ -n "${command_name}${pid}" ]] || continue
        if xray_agent_process_is_xray "${command_name}" "${pid}"; then
            xray_owner="$(xray_agent_port_owner_label "${command_name:-xray}" "${pid}" "${user}")"
            continue
        fi
        blocked_owner="$(xray_agent_port_owner_label "${command_name}" "${pid}" "${user}")"
        break
    done < <(xray_agent_lsof_port_rows TCP "${port}")

    if [[ -n "${blocked_owner}" ]]; then
        xray_agent_blank
        if [[ "${port}" == "443" ]]; then
            echoContent red " ---> TCP/443 当前由 ${blocked_owner} 占用，不会静默覆盖现有前端/网站。"
            echoContent yellow " ---> 请先迁移现有网站到本机 upstream 后注册到网站/反代管理，或为 Xray 选择非 443 后端端口。"
            if declare -F xray_agent_nginx_print_proxy_protocol_preflight >/dev/null 2>&1; then
                xray_agent_nginx_print_proxy_protocol_preflight
            fi
        fi
        xray_agent_error " ---> ${port}端口被占用，请手动关闭后安装"
    fi
    if [[ -n "${xray_owner}" ]]; then
        echoContent yellow " ---> TCP ${port}端口当前由 Xray 占用，可继续复用"
    fi
}

checkUDPPort() {
    local port="$1"
    local command_name pid user blocked_owner xray_owner
    while IFS='|' read -r command_name pid user; do
        [[ -n "${command_name}${pid}" ]] || continue
        if xray_agent_process_is_xray "${command_name}" "${pid}"; then
            xray_owner="$(xray_agent_port_owner_label "${command_name:-xray}" "${pid}" "${user}")"
            continue
        fi
        blocked_owner="$(xray_agent_port_owner_label "${command_name}" "${pid}" "${user}")"
        break
    done < <(xray_agent_lsof_port_rows UDP "${port}")

    if [[ -n "${blocked_owner}" ]]; then
        xray_agent_blank
        xray_agent_error " ---> UDP ${port}端口被 ${blocked_owner} 占用，请手动关闭后安装"
    fi
    if [[ -n "${xray_owner}" ]]; then
        echoContent yellow " ---> UDP ${port}端口当前由 Xray 占用，可继续复用"
    fi
}

xray_agent_tcp_port_reusable_for_xray() {
    local label="$1"
    local port="$2"
    xray_agent_validate_reuse_tcp_port "${label}" "${port}" "xray-backend" || true
    xray_agent_print_reuse_check_result "${label}端口" "TCP/${port}" "$(xray_agent_reuse_status)" "$(xray_agent_reuse_reason)"
    xray_agent_reuse_can_prompt
}

xray_agent_validate_reuse_tcp_port() {
    local label="$1"
    local port="$2"
    local expected_role="${3:-xray-backend}"
    local owner

    if ! xray_agent_validate_port "${port}"; then
        xray_agent_reuse_result block "${label}端口不合法"
        return 1
    fi

    owner="$(xray_agent_port_owner TCP "${port}" 2>/dev/null || printf '未检测')"
    echoContent yellow " ---> ${label}端口owner: TCP/${port}=${owner}"
    case "${owner}" in
        空闲 | xray/* | Xray/*)
            xray_agent_reuse_result ok "端口空闲或由 Xray 占用，可继续复用"
            return 0
            ;;
        未检测*)
            xray_agent_reuse_result warn "无法确认端口 owner，后续仍会做监听检查"
            return 0
            ;;
        nginx/* | Nginx/*)
            if [[ "${expected_role}" == "frontdoor" ]]; then
                xray_agent_reuse_result ok "端口由预期 Nginx 前置占用"
                return 0
            fi
            xray_agent_reuse_result block "端口由 Nginx 前置占用，不能作为 Xray 后端复用"
            return 1
            ;;
        *)
            xray_agent_reuse_result block "端口被非预期进程占用: ${owner}"
            return 1
            ;;
    esac
}

xray_agent_default_backend_port_for_label() {
    case "$1" in
        Vision) printf '31301\n' ;;
        Reality) printf '31302\n' ;;
        *) printf '31303\n' ;;
    esac
}

xray_agent_other_suite_uses_public_443() {
    case "$1" in
        Vision)
            xray_agent_reality_suite_installed && [[ "${RealityPort:-}" == "443" ]] && ! xray_agent_nginx_frontdoor_enabled
            ;;
        Reality)
            xray_agent_tls_suite_installed && [[ "${Port:-}" == "443" ]] && ! xray_agent_nginx_frontdoor_enabled
            ;;
        *)
            return 1
            ;;
    esac
}

xray_agent_force_shared_frontdoor() {
    local label="$1"
    xray_agent_other_suite_uses_public_443 "${label}" || return 1
    echoContent yellow " ---> 检测到另一个套餐已使用公网 TCP/443。"
    echoContent yellow " ---> TLS 与 Reality 同时安装时强制使用 Nginx stream 共用公网443。"
    echoContent yellow " ---> Reality/XHTTP 本身不需要 Nginx；这里仅用于两个套餐共用公网443。"
    reuse443="y"
    XRAY_AGENT_INSTALL_STREAM_ONLY=true
    XRAY_AGENT_FORCE_SHARED_FRONTDOOR=true
    return 0
}

xray_agent_prepare_existing_suite_backend_for_frontdoor() {
    local current_label="$1"
    [[ "${reuse443}" == "y" ]] || return 0
    [[ "${XRAY_AGENT_SHARED_FRONTDOOR_PORT_PREPARED:-}" != "true" ]] || return 0
    XRAY_AGENT_SHARED_FRONTDOOR_PORT_PREPARED=true
    case "${current_label}" in
        Vision)
            if [[ "${RealityPort:-}" == "443" ]]; then
                customPortFunction "Reality"
            fi
            ;;
        Reality)
            if [[ "${Port:-}" == "443" ]]; then
                customPortFunction "Vision"
            fi
            ;;
    esac
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

xray_agent_render_xray_service_file() {
    export XRAY_SERVICE_EXEC_START_PRE=
    export XRAY_SERVICE_EXEC_START="${ctlPath:-${XRAY_AGENT_XRAY_BINARY}} run -confdir /etc/xray-agent/xray/conf"
    readConfigHostPathUUID 2>/dev/null || true
    if [[ -n "${Hysteria2HopPorts:-}" ]] &&
        declare -F xray_agent_hysteria2_port_spec_valid >/dev/null 2>&1 &&
        xray_agent_hysteria2_port_spec_valid "${Hysteria2HopPorts}"; then
        XRAY_SERVICE_EXEC_START_PRE="ExecStartPre=-/usr/bin/env bash /etc/xray-agent/lib/hysteria2-check.sh"
    fi
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/systemd/xray.service.tpl" /etc/systemd/system/xray.service
    systemctl daemon-reload
}

xray_agent_refresh_xray_service() {
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]]; then
        if [[ ! -f /etc/systemd/system/xray.service ]]; then
            echoContent yellow " ---> xray.service 不存在，跳过刷新"
            return 0
        fi
        xray_agent_render_xray_service_file
        echoContent green " ---> xray.service 已刷新"
    fi
}

installXrayService() {
    xray_agent_blank
    echoContent skyBlue "进度  $1/${totalProgress} : 配置Xray开机自启"
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]]; then
        rm -rf /etc/systemd/system/xray.service
        xray_agent_render_xray_service_file
        systemctl enable xray.service
    fi
}

customPortFunction() {
    local port historyCustomPortStatus default_port disallow_443="false"
    if [[ "$1" == "Vision" ]]; then
        port="${Port}"
    elif [[ "$1" == "Reality" ]]; then
        port="${RealityPort}"
    fi
    default_port="443"

    if [[ "${reuse443}" != "y" ]] && xray_agent_other_suite_uses_public_443 "$1"; then
        if xray_agent_force_shared_frontdoor "$1"; then
            :
        else
            disallow_443="true"
            default_port="$(xray_agent_default_backend_port_for_label "$1")"
        fi
    fi

    if [[ "${reuse443}" == "y" ]]; then
        disallow_443="true"
        default_port="$(xray_agent_default_backend_port_for_label "$1")"
        xray_agent_prepare_existing_suite_backend_for_frontdoor "$1"
    fi

    if [[ -n "${port}" ]]; then
        echoContent yellow " ---> 检测到上次安装时的${1}端口: ${port}"
        if [[ "${disallow_443}" == "true" && "${port}" == "443" ]]; then
            echoContent yellow " ---> 当前场景下 ${1} 后端不能继续监听443"
            if xray_agent_tcp_port_reusable_for_xray "${1}" "${default_port}"; then
                port="${default_port}"
                historyCustomPortStatus="y"
                echoContent yellow " ---> ${1}后端端口自动切换为: ${port}"
            else
                port=
                historyCustomPortStatus="n"
            fi
        elif xray_agent_tcp_port_reusable_for_xray "${1}" "${port}"; then
            if xray_agent_prompt_yes_no "是否继续使用该${1}端口？" "y"; then
                historyCustomPortStatus="y"
                xray_agent_blank
                echoContent yellow " ---> ${1}端口: ${port}"
            else
                historyCustomPortStatus="n"
            fi
        else
            echoContent red " ---> 上次${1}端口当前不可用，请重新选择"
            historyCustomPortStatus="n"
        fi
    fi

    if [[ -z "${port}" && "${disallow_443}" == "true" ]]; then
        if xray_agent_tcp_port_reusable_for_xray "${1}" "${default_port}"; then
            port="${default_port}"
            historyCustomPortStatus="y"
            echoContent yellow " ---> ${1}后端端口自动使用: ${port}"
        else
            historyCustomPortStatus="n"
        fi
    fi

    if [[ "${historyCustomPortStatus}" == "n" || -z "${port}" ]]; then
        echoContent yellow "${1}请输入自定义端口[例: 2083]，[回车]使用${default_port}"
        read -r -p "端口:" port
        if [[ -n "${port}" ]]; then
            if xray_agent_validate_port "${port}"; then
                if [[ "${disallow_443}" == "true" && "${port}" == "443" ]]; then
                    xray_agent_error " ---> 当前场景下不允许 ${1} 后端使用端口 443"
                fi
                checkPort "${port}"
            else
                xray_agent_error " ---> ${1}端口输入错误"
            fi
        else
            port="${default_port}"
            checkPort "${port}"
        fi
    fi

    checkPort "${port}"
    allowPort "${port}"

    if [[ "$1" == "Vision" ]]; then
        Port="${port}"
        if [[ -f "${configPath}${frontingType}.json" ]]; then
            xray_agent_json_update_file "${configPath}${frontingType}.json" ".inbounds[0].port = ${port}"
        fi
        if [[ "${historyCustomPortStatus}" == "n" ]]; then
            find "${configPath}" -maxdepth 1 -type f -name "02_dokodemodoor_inbounds_*.json" -delete
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
