if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

checkLog() {
    if [[ -z "${coreInstallType}" ]]; then
        xray_agent_error " ---> 没有检测到安装目录，请执行脚本安装内容"
    fi
    local logStatus=false
    if grep -q "access" "${configPath}00_log.json"; then
        logStatus=true
    fi
    echoContent skyBlue "\n功能 $1/${totalProgress} : 查看日志"
    echoContent red "\n=============================================================="
    if [[ "${logStatus}" == "false" ]]; then
        echoContent yellow "1.打开access日志"
    else
        echoContent yellow "1.关闭access日志"
    fi
    echoContent yellow "2.监听access日志"
    echoContent yellow "3.监听error日志"
    echoContent yellow "4.查看证书定时任务日志"
    echoContent yellow "5.查看证书安装日志"
    echoContent yellow "6.清空日志"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectAccessLogType
    local configPathLog="${configPath//conf\//}"
    case ${selectAccessLogType} in
        1)
            if [[ "${logStatus}" == "false" ]]; then
                xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/extras/access_log_on.patch.json" "${configPath}00_log.json"
            else
                xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/extras/access_log_off.patch.json" "${configPath}00_log.json"
            fi
            reloadCore
            ;;
        2)
            tail -f "${configPathLog}access.log"
            ;;
        3)
            tail -f "${configPathLog}error.log"
            ;;
        4)
            tail -n 100 /etc/xray-agent/crontab_tls.log
            ;;
        5)
            tail -n 100 /etc/xray-agent/tls/acme.log
            ;;
        6)
            echo >"${configPathLog}access.log"
            echo >"${configPathLog}error.log"
            ;;
    esac
}
