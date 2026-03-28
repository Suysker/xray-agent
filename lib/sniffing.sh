xray_agent_default_sniffing_json() {
    jq -nc '{
      enabled: true,
      destOverride: ["http", "tls", "quic"],
      metadataOnly: false,
      routeOnly: false
    }'
}

manageSniffing() {
    if [[ "${coreInstallType}" == "1" ]]; then
        current_sniffing=$(jq '.inbounds[].sniffing.enabled' "${configPath}${frontingType}.json")
        current_routeOnly=$(jq '.inbounds[].sniffing.routeOnly' "${configPath}${frontingType}.json")
    elif [[ "${coreInstallType}" == "2" ]]; then
        current_sniffing=$(jq '.inbounds[].sniffing.enabled' "${configPath}${RealityfrontingType}.json")
        current_routeOnly=$(jq '.inbounds[].sniffing.routeOnly' "${configPath}${RealityfrontingType}.json")
    else
        current_sniffing=$(jq -s '.[0].inbounds[].sniffing.enabled and .[1].inbounds[].sniffing.enabled' "${configPath}${frontingType}.json" "${configPath}${RealityfrontingType}.json")
        current_routeOnly=$(jq -s '.[0].inbounds[].sniffing.routeOnly and .[1].inbounds[].sniffing.routeOnly' "${configPath}${frontingType}.json" "${configPath}${RealityfrontingType}.json")
    fi
    echoContent yellow "1. $( [[ "${current_sniffing}" == "true" ]] && echo "关闭" || echo "开启" ) 流量嗅探"
    echoContent yellow "2. $( [[ "${current_routeOnly}" == "true" ]] && echo "关闭" || echo "开启" ) 流量嗅探仅供路由"
    read -r -p "请按照上面示例输入:" sniffingtype
    case ${sniffingtype} in
        1)
            find "${configPath}" -name "*_inbounds.json" | while read -r configfile; do
                if [[ "${current_sniffing}" == "true" ]]; then
                    updated_json=$(jq '.inbounds[].sniffing.enabled = false' "${configfile}")
                else
                    updated_json=$(jq '.inbounds[].sniffing.enabled = true' "${configfile}")
                fi
                echo "${updated_json}" | jq . >"${configfile}"
            done
            ;;
        2)
            find "${configPath}" -name "*_inbounds.json" | while read -r configfile; do
                if [[ "${current_routeOnly}" == "true" ]]; then
                    updated_json=$(jq '.inbounds[].sniffing.routeOnly = false' "${configfile}")
                else
                    updated_json=$(jq '.inbounds[].sniffing.routeOnly = true' "${configfile}")
                fi
                echo "${updated_json}" | jq . >"${configfile}"
            done
            ;;
    esac
    reloadCore
}
