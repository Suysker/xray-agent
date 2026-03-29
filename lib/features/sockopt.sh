if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_default_sockopt_json() {
    jq -nc '{
      acceptProxyProtocol: false,
      tcpFastOpen: true,
      tcpMptcp: false,
      tcpNoDelay: false
    }'
}

xray_agent_sockopt_with_proxy_protocol() {
    local accept_proxy="${1:-false}"
    jq -nc --argjson acceptProxyProtocol "${accept_proxy}" '{
      acceptProxyProtocol: $acceptProxyProtocol,
      tcpFastOpen: true,
      tcpMptcp: false,
      tcpNoDelay: false
    }'
}

xray_agent_apply_trusted_x_forwarded_for() {
    local target_path="$1"
    local trusted_source="${2:-127.0.0.1}"
    [[ -f "${target_path}" ]] || return 0
    jq --arg trustedSource "${trusted_source}" '.inbounds[0].streamSettings.sockopt.trustedXForwardedFor = [$trustedSource]' "${target_path}" >"${target_path}.tmp" &&
        mv "${target_path}.tmp" "${target_path}"
}

xray_agent_apply_trusted_xff_patch() {
    local target_path="$1"
    local trusted_source="${XRAY_AGENT_TRUSTED_X_FORWARDED_FOR:-127.0.0.1}"
    xray_agent_apply_trusted_x_forwarded_for "${target_path}" "${trusted_source}"
}

manageSockopt() {
    if [[ "${coreInstallType}" == "1" ]]; then
        current_tcpMptcp=$(jq '.inbounds[].streamSettings.sockopt.tcpMptcp' "${configPath}${frontingType}.json")
        current_tcpNoDelay=$(jq '.inbounds[].streamSettings.sockopt.tcpNoDelay' "${configPath}${frontingType}.json")
        current_tcpFastOpen=$(jq '.inbounds[].streamSettings.sockopt.tcpFastOpen' "${configPath}${frontingType}.json")
    elif [[ "${coreInstallType}" == "2" ]]; then
        current_tcpMptcp=$(jq '.inbounds[].streamSettings.sockopt.tcpMptcp' "${configPath}${RealityfrontingType}.json")
        current_tcpNoDelay=$(jq '.inbounds[].streamSettings.sockopt.tcpNoDelay' "${configPath}${RealityfrontingType}.json")
        current_tcpFastOpen=$(jq '.inbounds[].streamSettings.sockopt.tcpFastOpen' "${configPath}${RealityfrontingType}.json")
    else
        current_tcpMptcp=$(jq -s '.[0].inbounds[].streamSettings.sockopt.tcpMptcp and .[1].inbounds[].streamSettings.sockopt.tcpMptcp' "${configPath}${frontingType}.json" "${configPath}${RealityfrontingType}.json")
        current_tcpNoDelay=$(jq -s '.[0].inbounds[].streamSettings.sockopt.tcpNoDelay and .[1].inbounds[].streamSettings.sockopt.tcpNoDelay' "${configPath}${frontingType}.json" "${configPath}${RealityfrontingType}.json")
        current_tcpFastOpen=$(jq -s '.[0].inbounds[].streamSettings.sockopt.tcpFastOpen and .[1].inbounds[].streamSettings.sockopt.tcpFastOpen' "${configPath}${frontingType}.json" "${configPath}${RealityfrontingType}.json")
    fi
    echoContent yellow "1. $( [[ "${current_tcpMptcp}" == "true" ]] && echo "关闭" || echo "开启" ) tcpMptcp"
    echoContent yellow "2. $( [[ "${current_tcpNoDelay}" == "true" ]] && echo "关闭" || echo "开启" ) tcpNoDelay"
    echoContent yellow "3. $( [[ "${current_tcpFastOpen}" == "true" ]] && echo "关闭" || echo "开启" ) tcpFastOpen"
    read -r -p "请按照上面示例输入:" sockopttype
    case ${sockopttype} in
        1)
            find "${configPath}" -name "*_inbounds.json" | while read -r configfile; do
                if [[ "${current_tcpMptcp}" == "true" ]]; then
                    updated_json=$(jq '.inbounds[].streamSettings.sockopt.tcpMptcp = false' "${configfile}")
                else
                    updated_json=$(jq '.inbounds[].streamSettings.sockopt.tcpMptcp = true' "${configfile}")
                fi
                echo "${updated_json}" | jq . >"${configfile}"
            done
            ;;
        2)
            find "${configPath}" -name "*_inbounds.json" | while read -r configfile; do
                if [[ "${current_tcpNoDelay}" == "true" ]]; then
                    updated_json=$(jq '.inbounds[].streamSettings.sockopt.tcpNoDelay = false' "${configfile}")
                else
                    updated_json=$(jq '.inbounds[].streamSettings.sockopt.tcpNoDelay = true' "${configfile}")
                fi
                echo "${updated_json}" | jq . >"${configfile}"
            done
            ;;
        3)
            find "${configPath}" -name "*_inbounds.json" | while read -r configfile; do
                if [[ "${current_tcpFastOpen}" == "true" ]]; then
                    updated_json=$(jq '.inbounds[].streamSettings.sockopt.tcpFastOpen = false' "${configfile}")
                    sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf
                else
                    updated_json=$(jq '.inbounds[].streamSettings.sockopt.tcpFastOpen = true' "${configfile}")
                    sed -i '$a net.ipv4.tcp_fastopen=3' /etc/sysctl.conf
                fi
                echo "${updated_json}" | jq . >"${configfile}"
            done
            sysctl -p
            ;;
    esac
    reloadCore
}
