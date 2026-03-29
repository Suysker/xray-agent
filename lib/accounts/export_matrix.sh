if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_build_clash_meta_vless() {
    local profile_name="$1"
    local id="$2"
    local variant="${3:-}"
    xray_agent_load_protocol_profile "${profile_name}" || return 1
    local address port sni path_value security
    address="$(xray_agent_protocol_address_value "${variant}")"
    port="$(xray_agent_protocol_port_value "${variant}")"
    sni="$(xray_agent_protocol_sni_value "${variant}")"
    path_value="$(xray_agent_protocol_path_value)"
    security="$(xray_agent_protocol_security_value "${variant}")"
    jq -nc \
        --arg name "${id}" \
        --arg server "${address}" \
        --argjson port "${port}" \
        --arg uuid "${id}" \
        --arg network "${XRAY_AGENT_PROTOCOL_TRANSPORT}" \
        --arg tlsSecurity "${security}" \
        --arg sni "${sni}" \
        --arg flow "${XRAY_AGENT_PROTOCOL_FLOW}" \
        --arg path "${path_value}" \
        --arg pbk "${RealityPublicKey}" \
        --arg sid "${RealityShortID}" \
        '{
          name: $name,
          type: "vless",
          server: $server,
          port: $port,
          uuid: $uuid,
          tls: ($tlsSecurity != "none"),
          servername: $sni,
          network: $network,
          udp: true
        }
        + (if $flow != "" then {flow: $flow} else {} end)
        + (if $network == "xhttp" then {xhttp_opts: {path: $path}} else {} end)
        + (if $tlsSecurity == "reality" then {"reality-opts": {"public-key": $pbk, "short-id": $sid}} else {} end)'
}

xray_agent_build_sing_box_vless() {
    local profile_name="$1"
    local id="$2"
    local variant="${3:-}"
    xray_agent_load_protocol_profile "${profile_name}" || return 1
    local address port sni path_value security
    address="$(xray_agent_protocol_address_value "${variant}")"
    port="$(xray_agent_protocol_port_value "${variant}")"
    sni="$(xray_agent_protocol_sni_value "${variant}")"
    path_value="$(xray_agent_protocol_path_value)"
    security="$(xray_agent_protocol_security_value "${variant}")"
    jq -nc \
        --arg type "vless" \
        --arg tag "${id}" \
        --arg server "${address}" \
        --argjson server_port "${port}" \
        --arg uuid "${id}" \
        --arg flow "${XRAY_AGENT_PROTOCOL_FLOW}" \
        --arg transport "${XRAY_AGENT_PROTOCOL_TRANSPORT}" \
        --arg security "${security}" \
        --arg server_name "${sni}" \
        --arg path "${path_value}" \
        --arg public_key "${RealityPublicKey}" \
        --arg short_id "${RealityShortID}" \
        '{
          type: $type,
          tag: $tag,
          server: $server,
          server_port: $server_port,
          uuid: $uuid
        }
        + (if $flow != "" then {flow: $flow} else {} end)
        + (if $security == "tls" then {tls: {enabled: true, server_name: $server_name}} else {} end)
        + (if $security == "reality" then {tls: {enabled: true, server_name: $server_name, reality: {enabled: true, public_key: $public_key, short_id: $short_id}}} else {} end)
        + (if $transport == "xhttp" then {transport: {type: "xhttp", path: $path}} else {transport: {type: "tcp"}} end)'
}

xray_agent_print_share_bundle() {
    local profile_name="$1"
    local id="$2"
    local variant="${3:-}"
    local uri clash sing_box
    uri="$(xray_agent_build_vless_uri "${profile_name}" "${id}" "${variant}")"
    clash="$(xray_agent_build_clash_meta_vless "${profile_name}" "${id}" "${variant}")"
    sing_box="$(xray_agent_build_sing_box_vless "${profile_name}" "${id}" "${variant}")"
    echoContent yellow " ---> VLESS URL"
    echoContent green "${uri}\n"
    echoContent yellow " ---> Clash Meta"
    echoContent green "${clash}\n"
    echoContent yellow " ---> sing-box"
    echoContent green "${sing_box}\n"
}
