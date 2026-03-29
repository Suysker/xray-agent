if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xrayVersionManageMenu() {
    echoContent skyBlue "\n进度  $1/${totalProgress} : Xray版本管理"
    echoContent red "\n=============================================================="
    echoContent yellow "1.升级Xray-core"
    echoContent yellow "2.升级Xray-core 预览版"
    echoContent yellow "3.回退Xray-core"
    echoContent yellow "4.关闭Xray-core"
    echoContent yellow "5.打开Xray-core"
    echoContent yellow "6.重启Xray-core"
    echoContent yellow "7.更新geosite、geoip"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectXrayType
    case "${selectXrayType}" in
        1)
            updateXray
            ;;
        2)
            prereleaseStatus=true
            updateXray
            ;;
        3)
            curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -5 | awk '{print ""NR""":"$0}'
            read -r -p "请输入要回退的版本:" selectXrayVersionType
            version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[]|select (.prerelease==false)|.tag_name' | head -5 | awk '{print ""NR""":"$0}' | grep "${selectXrayVersionType}:" | awk -F "[:]" '{print $2}')
            if [[ -n "${version}" ]]; then
                updateXray "${version}"
            fi
            ;;
        4)
            handleXray stop
            ;;
        5)
            handleXray start
            ;;
        6)
            reloadCore
            ;;
        7)
            /etc/xray-agent/auto_update_geodata.sh
            ;;
    esac
}
