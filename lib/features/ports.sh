if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_render_dokodemo_port() {
    local port="$1"
    export XRAY_DOKODEMO_PORT="${port}"
    export XRAY_TARGET_PORT="${Port}"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/extras/dokodemo_port.json.tpl" "${configPath}02_dokodemodoor_inbounds_${port}.json"
}

addCorePort() {
    echoContent yellow "# 只给TLS+VISION添加新端口，永远不会支持Reality(Reality只建议用443)\n"
    echoContent yellow "1.添加端口"
    echoContent yellow "2.删除端口"
    echoContent yellow "3.查看已添加端口"
    read -r -p "请选择:" selectNewPortType
    if [[ "${selectNewPortType}" == "1" ]]; then
        read -r -p "请输入端口号:" newPort
        if [[ -n "${newPort}" ]]; then
            while read -r port; do
                if [[ "${port}" == "${Port}" ]]; then
                    continue
                fi
                rm -rf "$(find ${configPath}* | grep "${port}")"
                allowPort "${port}"
                xray_agent_render_dokodemo_port "${port}"
            done < <(echo "${newPort}" | tr ',' '\n')
            reloadCore
        fi
    elif [[ "${selectNewPortType}" == "2" ]]; then
        find "${configPath}" -name "*dokodemodoor*" | awk -F "[c][o][n][f][/]" '{print ""NR""":"$2}'
        read -r -p "请输入要删除的端口编号:" portIndex
        dokoConfig=$(find "${configPath}" -name "*dokodemodoor*" | awk -F "[c][o][n][f][/]" '{print ""NR""":"$2}' | grep "${portIndex}:")
        if [[ -n "${dokoConfig}" ]]; then
            rm "${configPath}/$(echo "${dokoConfig}" | awk -F "[:]" '{print $2}')"
            reloadCore
        fi
    else
        find "${configPath}" -name "*dokodemodoor*" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}'
    fi
}
