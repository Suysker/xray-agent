if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

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
    echoContent skyBlue "\n进度  $1/${totalProgress} : 配置Xray开机自启"
    if [[ -n $(find /bin /usr/bin -name "systemctl") ]]; then
        rm -rf /etc/systemd/system/xray.service
        execStart="${ctlPath} run -confdir /etc/xray-agent/xray/conf"
        cat <<EOF >/etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target

[Service]
User=root
Nice=-20
ExecStart=${execStart}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
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
