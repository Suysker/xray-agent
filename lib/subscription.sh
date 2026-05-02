#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

XRAY_AGENT_SUBSCRIPTION_CUSTOM_RULES="${XRAY_AGENT_SUBSCRIPTION_CUSTOM_RULES:-}"
XRAY_AGENT_SUBSCRIPTION_REALITY_ADDRESS="${XRAY_AGENT_SUBSCRIPTION_REALITY_ADDRESS:-}"

xray_agent_subscription_profile_dir() {
    printf '%s/subscription\n' "${XRAY_AGENT_PROFILE_DIR:-${XRAY_AGENT_PROJECT_ROOT}/profiles}"
}

xray_agent_subscription_rules_file() {
    printf '%s/rules.json\n' "$(xray_agent_subscription_profile_dir)"
}

xray_agent_subscription_custom_rules_file() {
    printf '%s/custom_rules.json\n' "$(xray_agent_subscription_profile_dir)"
}

xray_agent_yaml_quote() {
    jq -Rn --arg value "$1" '$value' | tr -d '\r'
}

xray_agent_subscription_prepare_state() {
    readInstallType
    if [[ -z "${coreInstallType}" ]]; then
        echoContent red " ---> 未安装，请先安装 TLS 或 Reality 套餐"
        return 1
    fi
    readInstallProtocolType
    readConfigHostPathUUID
}

xray_agent_subscription_users() {
    {
        [[ -f "${configPath}${frontingType}.json" ]] && jq -r '.inbounds[0].settings.clients[]?.id // empty' "${configPath}${frontingType}.json" 2>/dev/null
        [[ -f "${configPath}03_VLESS_WS_inbounds.json" ]] && jq -r '.inbounds[0].settings.clients[]?.id // empty' "${configPath}03_VLESS_WS_inbounds.json" 2>/dev/null
        [[ -f "${configPath}05_VMess_WS_inbounds.json" ]] && jq -r '.inbounds[0].settings.clients[]?.id // empty' "${configPath}05_VMess_WS_inbounds.json" 2>/dev/null
        [[ -f "${configPath}${RealityfrontingType}.json" ]] && jq -r '.inbounds[0].settings.clients[]?.id // empty' "${configPath}${RealityfrontingType}.json" 2>/dev/null
        [[ -f "${configPath}08_VLESS_XHTTP_inbounds.json" ]] && jq -r '.inbounds[0].settings.clients[]?.id // empty' "${configPath}08_VLESS_XHTTP_inbounds.json" 2>/dev/null
        [[ -f "${configPath}09_Hysteria2_inbounds.json" ]] && jq -r '.inbounds[0].settings.clients[]?.auth // empty' "${configPath}09_Hysteria2_inbounds.json" 2>/dev/null
    } | tr -d '\r' | sed '/^$/d' | sort -u
}

xray_agent_subscription_select_users() {
    local users=()
    local selected_user selected_index
    mapfile -t users < <(xray_agent_subscription_users)

    if [[ "${#users[@]}" -eq 0 ]]; then
        echoContent red " ---> 未检测到可订阅用户" >&2
        return 1
    fi

    echoContent skyBlue "-------------------------选择用户-----------------------------" >&2
    echoContent yellow "0.全部用户" >&2
    for selected_index in "${!users[@]}"; do
        echoContent yellow "$((selected_index + 1)).${users[$selected_index]}" >&2
    done
    read -r -p "请选择[回车=全部]:" selected_user
    selected_user="${selected_user:-0}"

    if [[ "${selected_user}" == "0" ]]; then
        printf '%s\n' "${users[@]}"
        return 0
    fi
    if [[ "${selected_user}" =~ ^[0-9]+$ ]] && ((selected_user >= 1 && selected_user <= ${#users[@]})); then
        printf '%s\n' "${users[$((selected_user - 1))]}"
        return 0
    fi

    echoContent red " ---> 选择错误" >&2
    return 1
}

xray_agent_subscription_base64() {
    if base64 --help 2>&1 | grep -q -- "-w"; then
        base64 -w 0
    else
        base64 | tr -d '\r\n'
    fi
}

xray_agent_subscription_uri_list_for_user() {
    local user_id="$1"
    local uri

    if echo "${currentInstallProtocolType}" | grep -q 0; then
        xray_agent_build_vless_uri "vless_tcp_tls" "${user_id}" || true
    fi
    if echo "${currentInstallProtocolType}" | grep -q 1; then
        xray_agent_build_vless_uri "vless_ws_tls" "${user_id}" || true
    fi
    if echo "${currentInstallProtocolType}" | grep -q 2; then
        xray_agent_build_vmess_ws_uri "${user_id}" || true
    fi
    if echo "${currentInstallProtocolType}" | grep -q 7; then
        uri="$(xray_agent_build_vless_uri "vless_reality_tcp" "${user_id}" 2>/dev/null || true)"
        [[ -n "${uri}" ]] && printf '%s\n' "${uri}"
    fi
    if echo "${currentInstallProtocolType}" | grep -q 8; then
        if [[ "${coreInstallType}" == "1" || "${coreInstallType}" == "3" ]]; then
            xray_agent_build_vless_uri "vless_xhttp" "${user_id}" "tls" || true
        fi
        if [[ "${coreInstallType}" == "2" || "${coreInstallType}" == "3" ]]; then
            uri="$(xray_agent_build_vless_uri "vless_xhttp" "${user_id}" "reality" 2>/dev/null || true)"
            [[ -n "${uri}" ]] && printf '%s\n' "${uri}"
        fi
    fi
    if echo "${currentInstallProtocolType}" | grep -q 9; then
        xray_agent_build_hysteria2_uri "${user_id}" || true
    fi
}

xray_agent_subscription_build_uri_list() {
    local user_id
    if [[ "$#" -eq 0 ]]; then
        mapfile -t XRAY_AGENT_SUBSCRIPTION_ALL_USERS < <(xray_agent_subscription_users)
        set -- "${XRAY_AGENT_SUBSCRIPTION_ALL_USERS[@]}"
    fi
    for user_id in "$@"; do
        xray_agent_subscription_uri_list_for_user "${user_id}"
    done | sed '/^$/d'
}

xray_agent_subscription_print_universal() {
    local users=()
    local uri_content
    xray_agent_subscription_prepare_state || return 1
    mapfile -t users < <(xray_agent_subscription_select_users)
    [[ "${#users[@]}" -gt 0 ]] || return 1

    uri_content="$(xray_agent_subscription_build_uri_list "${users[@]}")"
    if [[ -z "${uri_content}" ]]; then
        echoContent red " ---> 未生成可用订阅内容"
        return 1
    fi

    xray_agent_blank
    echoContent skyBlue "-------------------------通用订阅 URI-------------------------"
    printf '%s\n' "${uri_content}"
    xray_agent_blank
    echoContent skyBlue "-------------------------Base64订阅---------------------------"
    printf '%s\n' "${uri_content}" | xray_agent_subscription_base64
    xray_agent_blank
}

xray_agent_subscription_rule_json_to_lines() {
    local source_file="$1"
    jq -r '
        .rules[]?
        | [
            (.id | tostring),
            (.label // ""),
            (.name // ""),
            (.behavior // ""),
            (.format // ""),
            (.url // ""),
            (.target // "PROXY")
          ]
        | @tsv
    ' "${source_file}" | tr -d '\r' | awk -F '\t' 'BEGIN { OFS = "|" } { print $1, $2, $3, $4, $5, $6, $7 }'
}

xray_agent_subscription_rule_presets() {
    local rules_file custom_rules_file
    rules_file="$(xray_agent_subscription_rules_file)"
    custom_rules_file="$(xray_agent_subscription_custom_rules_file)"

    if [[ ! -r "${rules_file}" ]]; then
        echoContent red " ---> 订阅规则源文件不存在: ${rules_file}" >&2
        return 1
    fi

    xray_agent_subscription_rule_json_to_lines "${rules_file}"
    if [[ -r "${custom_rules_file}" ]]; then
        xray_agent_subscription_rule_json_to_lines "${custom_rules_file}"
    fi
    if [[ -n "${XRAY_AGENT_SUBSCRIPTION_CUSTOM_RULES}" ]]; then
        printf '%s\n' "${XRAY_AGENT_SUBSCRIPTION_CUSTOM_RULES}" | sed '/^$/d'
    fi
}

xray_agent_subscription_default_rule_ids() {
    local rules_file
    rules_file="$(xray_agent_subscription_rules_file)"
    if [[ -r "${rules_file}" ]]; then
        jq -r '(.default_ids // [1,2,3,4]) | map(tostring) | join(",")' "${rules_file}" | tr -d '\r'
    else
        printf '1,2,3,4\n'
    fi
}

xray_agent_subscription_default_rule_lines() {
    local default_ids
    default_ids="$(xray_agent_subscription_default_rule_ids)"
    xray_agent_subscription_rule_presets | awk -F '|' -v ids="${default_ids}" '
        BEGIN {
            split(ids, id_list, ",")
            for (idx in id_list) {
                wanted[id_list[idx]] = 1
            }
        }
        wanted[$1]
    '
}

xray_agent_subscription_select_rule_lines() {
    local presets=()
    local selected_rules token index line default_ids
    mapfile -t presets < <(xray_agent_subscription_rule_presets)
    default_ids="$(xray_agent_subscription_default_rule_ids)"

    echoContent skyBlue "-------------------------规则源-------------------------------" >&2
    for index in "${!presets[@]}"; do
        IFS='|' read -r token line _ <<<"${presets[$index]}"
        echoContent yellow "${token}.${line}" >&2
    done
    echoContent yellow "默认: ${default_ids}" >&2
    read -r -p "请输入规则编号[逗号分隔]:" selected_rules
    selected_rules="${selected_rules:-${default_ids}}"

    selected_rules="${selected_rules//，/,}"
    IFS=',' read -r -a XRAY_AGENT_SELECTED_RULE_INDEXES <<<"${selected_rules}"
    for token in "${XRAY_AGENT_SELECTED_RULE_INDEXES[@]}"; do
        token="$(printf '%s' "${token}" | tr -d ' ')"
        line="$(printf '%s\n' "${presets[@]}" | awk -F '|' -v id="${token}" '$1 == id {print; exit}')"
        if [[ -n "${line}" ]]; then
            printf '%s\n' "${line}"
        else
            echoContent yellow " ---> 跳过未知规则编号: ${token}" >&2
        fi
    done
}

xray_agent_subscription_rule_provider_yaml() {
    local rule_lines="$1"
    local id label name behavior format url target ext
    echo "rule-providers:"
    while IFS='|' read -r id label name behavior format url target; do
        [[ -n "${name}" ]] || continue
        ext="${format}"
        [[ "${format}" == "mrs" ]] && ext="mrs"
        printf '  %s:\n' "${name}"
        printf '    type: http\n'
        printf '    behavior: %s\n' "${behavior}"
        printf '    format: %s\n' "${format}"
        printf '    url: %s\n' "$(xray_agent_yaml_quote "${url}")"
        printf '    path: ./ruleset/%s.%s\n' "${name}" "${ext}"
        printf '    interval: 86400\n'
    done <<<"${rule_lines}"
}

xray_agent_subscription_rules_yaml() {
    local rule_lines="$1"
    local id label name behavior format url target
    echo "rules:"
    while IFS='|' read -r id label name behavior format url target; do
        [[ -n "${name}" ]] || continue
        printf '  - RULE-SET,%s,%s\n' "${name}" "${target:-PROXY}"
    done <<<"${rule_lines}"
    printf '  - MATCH,PROXY\n'
}

xray_agent_subscription_proxy_name() {
    local user_id="$1"
    local suffix="$2"
    printf '%s-%s\n' "${user_id}" "${suffix}"
}

xray_agent_subscription_proxy_names_for_user() {
    local user_id="$1"
    if echo "${currentInstallProtocolType}" | grep -q 0; then
        xray_agent_subscription_proxy_name "${user_id}" "VLESS-TCP-TLS"
    fi
    if echo "${currentInstallProtocolType}" | grep -q 1; then
        xray_agent_subscription_proxy_name "${user_id}" "VLESS-WS-TLS"
    fi
    if echo "${currentInstallProtocolType}" | grep -q 2; then
        xray_agent_subscription_proxy_name "${user_id}" "VMess-WS-TLS"
    fi
    if echo "${currentInstallProtocolType}" | grep -q 7; then
        xray_agent_subscription_proxy_name "${user_id}" "VLESS-TCP-Reality"
    fi
    if echo "${currentInstallProtocolType}" | grep -q 8; then
        if [[ "${coreInstallType}" == "1" || "${coreInstallType}" == "3" ]]; then
            xray_agent_subscription_proxy_name "${user_id}" "VLESS-XHTTP-TLS"
        fi
        if [[ "${coreInstallType}" == "2" || "${coreInstallType}" == "3" ]]; then
            xray_agent_subscription_proxy_name "${user_id}" "VLESS-XHTTP-Reality"
        fi
    fi
    if echo "${currentInstallProtocolType}" | grep -q 9; then
        xray_agent_subscription_proxy_name "${user_id}" "Hysteria2"
    fi
}

xray_agent_subscription_proxy_names() {
    local user_id
    for user_id in "$@"; do
        xray_agent_subscription_proxy_names_for_user "${user_id}"
    done | sed '/^$/d'
}

xray_agent_subscription_reality_short_id() {
    local sid="${RealityShortID//\"/}"
    printf '%s\n' "${sid%%,*}"
}

xray_agent_subscription_prepare_reality_address() {
    if [[ -n "${XRAY_AGENT_SUBSCRIPTION_REALITY_ADDRESS}" ]]; then
        return 0
    fi
    XRAY_AGENT_SUBSCRIPTION_REALITY_ADDRESS="$(xray_agent_select_public_ip_for_reality)" || return 1
    [[ -n "${XRAY_AGENT_SUBSCRIPTION_REALITY_ADDRESS}" ]]
}

xray_agent_subscription_yaml_alpn() {
    local csv="$1"
    local item
    IFS=',' read -r -a XRAY_AGENT_SUBSCRIPTION_ALPN_LIST <<<"${csv}"
    echo "    alpn:"
    for item in "${XRAY_AGENT_SUBSCRIPTION_ALPN_LIST[@]}"; do
        item="$(printf '%s' "${item}" | sed 's/^ *//;s/ *$//')"
        [[ -n "${item}" ]] && printf '      - %s\n' "$(xray_agent_yaml_quote "${item}")"
    done
}

xray_agent_subscription_vless_tcp_tls_proxy_yaml() {
    local user_id="$1"
    local name port encryption
    name="$(xray_agent_subscription_proxy_name "${user_id}" "VLESS-TCP-TLS")"
    port="$(xray_agent_share_port_for_profile vless_tcp_tls tls)"
    encryption="$(xray_agent_share_encryption_for_profile vless_tcp_tls)"
    printf '  - name: %s\n' "$(xray_agent_yaml_quote "${name}")"
    printf '    type: vless\n'
    printf '    server: %s\n' "$(xray_agent_yaml_quote "${domain}")"
    printf '    port: %s\n' "${port}"
    printf '    uuid: %s\n' "$(xray_agent_yaml_quote "${user_id}")"
    printf '    udp: true\n'
    printf '    tls: true\n'
    printf '    servername: %s\n' "$(xray_agent_yaml_quote "${domain}")"
    printf '    client-fingerprint: chrome\n'
    printf '    flow: xtls-rprx-vision\n'
    printf '    packet-encoding: xudp\n'
    printf '    encryption: %s\n' "$(xray_agent_yaml_quote "${encryption}")"
    printf '    network: tcp\n'
}

xray_agent_subscription_vless_ws_tls_proxy_yaml() {
    local user_id="$1"
    local name port encryption
    name="$(xray_agent_subscription_proxy_name "${user_id}" "VLESS-WS-TLS")"
    port="$(xray_agent_share_port_for_profile vless_ws_tls tls)"
    encryption="$(xray_agent_share_encryption_for_profile vless_ws_tls)"
    printf '  - name: %s\n' "$(xray_agent_yaml_quote "${name}")"
    printf '    type: vless\n'
    printf '    server: %s\n' "$(xray_agent_yaml_quote "${domain}")"
    printf '    port: %s\n' "${port}"
    printf '    uuid: %s\n' "$(xray_agent_yaml_quote "${user_id}")"
    printf '    udp: true\n'
    printf '    tls: true\n'
    printf '    servername: %s\n' "$(xray_agent_yaml_quote "${domain}")"
    printf '    client-fingerprint: chrome\n'
    printf '    encryption: %s\n' "$(xray_agent_yaml_quote "${encryption}")"
    printf '    network: ws\n'
    printf '    ws-opts:\n'
    printf '      path: %s\n' "$(xray_agent_yaml_quote "/${path}ws")"
    printf '      headers:\n'
    printf '        Host: %s\n' "$(xray_agent_yaml_quote "${domain}")"
}

xray_agent_subscription_vmess_ws_tls_proxy_yaml() {
    local user_id="$1"
    local name port
    name="$(xray_agent_subscription_proxy_name "${user_id}" "VMess-WS-TLS")"
    port="$(xray_agent_share_port_for_profile vmess_ws_tls tls)"
    printf '  - name: %s\n' "$(xray_agent_yaml_quote "${name}")"
    printf '    type: vmess\n'
    printf '    server: %s\n' "$(xray_agent_yaml_quote "${domain}")"
    printf '    port: %s\n' "${port}"
    printf '    uuid: %s\n' "$(xray_agent_yaml_quote "${user_id}")"
    printf '    alterId: 0\n'
    printf '    cipher: auto\n'
    printf '    udp: true\n'
    printf '    tls: true\n'
    printf '    servername: %s\n' "$(xray_agent_yaml_quote "${domain}")"
    printf '    client-fingerprint: chrome\n'
    printf '    network: ws\n'
    printf '    ws-opts:\n'
    printf '      path: %s\n' "$(xray_agent_yaml_quote "/${path}vws")"
    printf '      headers:\n'
    printf '        Host: %s\n' "$(xray_agent_yaml_quote "${domain}")"
}

xray_agent_subscription_vless_reality_proxy_yaml() {
    local user_id="$1"
    local name port sni public_key short_id
    xray_agent_subscription_prepare_reality_address || return 1
    name="$(xray_agent_subscription_proxy_name "${user_id}" "VLESS-TCP-Reality")"
    port="$(xray_agent_share_port_for_profile vless_reality_tcp reality)"
    sni="$(xray_agent_primary_reality_server_name)"
    public_key="$(xray_agent_reality_public_key_value || true)"
    short_id="$(xray_agent_subscription_reality_short_id)"
    [[ -n "${public_key}" ]] || return 1
    printf '  - name: %s\n' "$(xray_agent_yaml_quote "${name}")"
    printf '    type: vless\n'
    printf '    server: %s\n' "$(xray_agent_yaml_quote "${XRAY_AGENT_SUBSCRIPTION_REALITY_ADDRESS}")"
    printf '    port: %s\n' "${port}"
    printf '    uuid: %s\n' "$(xray_agent_yaml_quote "${user_id}")"
    printf '    udp: true\n'
    printf '    tls: true\n'
    printf '    servername: %s\n' "$(xray_agent_yaml_quote "${sni}")"
    printf '    client-fingerprint: chrome\n'
    printf '    flow: xtls-rprx-vision\n'
    printf '    packet-encoding: xudp\n'
    printf '    network: tcp\n'
    printf '    reality-opts:\n'
    printf '      public-key: %s\n' "$(xray_agent_yaml_quote "${public_key}")"
    [[ -n "${short_id}" ]] && printf '      short-id: %s\n' "$(xray_agent_yaml_quote "${short_id}")"
}

xray_agent_subscription_vless_xhttp_proxy_yaml() {
    local user_id="$1"
    local variant="$2"
    local suffix security address port sni encryption name flow_value
    if [[ "${variant}" == "reality" ]]; then
        xray_agent_subscription_prepare_reality_address || return 1
        suffix="VLESS-XHTTP-Reality"
        security="reality"
        address="${XRAY_AGENT_SUBSCRIPTION_REALITY_ADDRESS}"
        sni="$(xray_agent_primary_reality_server_name)"
    else
        suffix="VLESS-XHTTP-TLS"
        security="tls"
        address="${domain}"
        sni="${domain}"
    fi
    name="$(xray_agent_subscription_proxy_name "${user_id}" "${suffix}")"
    port="$(xray_agent_share_port_for_profile vless_xhttp "${variant}")"
    encryption="$(xray_agent_share_encryption_for_profile vless_xhttp)"
    printf '  - name: %s\n' "$(xray_agent_yaml_quote "${name}")"
    printf '    type: vless\n'
    printf '    server: %s\n' "$(xray_agent_yaml_quote "${address}")"
    printf '    port: %s\n' "${port}"
    printf '    uuid: %s\n' "$(xray_agent_yaml_quote "${user_id}")"
    printf '    udp: true\n'
    printf '    tls: true\n'
    printf '    servername: %s\n' "$(xray_agent_yaml_quote "${sni}")"
    printf '    client-fingerprint: chrome\n'
    printf '    encryption: %s\n' "$(xray_agent_yaml_quote "${encryption}")"
    if declare -F xray_agent_xhttp_vision_flow_for_share >/dev/null 2>&1; then
        flow_value="$(xray_agent_xhttp_vision_flow_for_share)"
        [[ -n "${flow_value}" ]] && printf '    flow: %s\n' "$(xray_agent_yaml_quote "${flow_value}")"
    fi
    printf '    network: xhttp\n'
    printf '    xhttp-opts:\n'
    printf '      path: %s\n' "$(xray_agent_yaml_quote "/${path}")"
    printf '      mode: %s\n' "$(xray_agent_yaml_quote "${XHTTPMode:-auto}")"
    printf '      headers:\n'
    printf '        Host: %s\n' "$(xray_agent_yaml_quote "${sni}")"
    if [[ "${security}" == "reality" ]]; then
        local public_key short_id
        public_key="$(xray_agent_reality_public_key_value || true)"
        short_id="$(xray_agent_subscription_reality_short_id)"
        [[ -n "${public_key}" ]] || return 1
        printf '    reality-opts:\n'
        printf '      public-key: %s\n' "$(xray_agent_yaml_quote "${public_key}")"
        [[ -n "${short_id}" ]] && printf '      short-id: %s\n' "$(xray_agent_yaml_quote "${short_id}")"
    fi
}

xray_agent_subscription_hysteria2_proxy_yaml() {
    local user_id="$1"
    local name ports
    name="$(xray_agent_subscription_proxy_name "${user_id}" "Hysteria2")"
    ports="$(xray_agent_hysteria2_hop_ports_value)"
    printf '  - name: %s\n' "$(xray_agent_yaml_quote "${name}")"
    printf '    type: hysteria2\n'
    printf '    server: %s\n' "$(xray_agent_yaml_quote "${domain}")"
    printf '    port: 443\n'
    if [[ -n "${ports}" ]]; then
        printf '    ports: %s\n' "$(xray_agent_yaml_quote "${ports}")"
        printf '    hop-interval: %s\n' "${Hysteria2HopInterval:-30}"
    fi
    printf '    password: %s\n' "$(xray_agent_yaml_quote "${user_id}")"
    printf '    sni: %s\n' "$(xray_agent_yaml_quote "${domain}")"
    printf '    skip-cert-verify: false\n'
    printf '    alpn:\n'
    printf '      - h3\n'
}

xray_agent_subscription_proxies_yaml() {
    local user_id
    echo "proxies:"
    for user_id in "$@"; do
        if echo "${currentInstallProtocolType}" | grep -q 0; then
            xray_agent_subscription_vless_tcp_tls_proxy_yaml "${user_id}"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 1; then
            xray_agent_subscription_vless_ws_tls_proxy_yaml "${user_id}"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 2; then
            xray_agent_subscription_vmess_ws_tls_proxy_yaml "${user_id}"
        fi
        if echo "${currentInstallProtocolType}" | grep -q 7; then
            xray_agent_subscription_vless_reality_proxy_yaml "${user_id}" || echoContent yellow " ---> Clash订阅跳过 Reality TCP: ${user_id}" >&2
        fi
        if echo "${currentInstallProtocolType}" | grep -q 8; then
            if [[ "${coreInstallType}" == "1" || "${coreInstallType}" == "3" ]]; then
                xray_agent_subscription_vless_xhttp_proxy_yaml "${user_id}" "tls"
            fi
            if [[ "${coreInstallType}" == "2" || "${coreInstallType}" == "3" ]]; then
                xray_agent_subscription_vless_xhttp_proxy_yaml "${user_id}" "reality" || echoContent yellow " ---> Clash订阅跳过 XHTTP Reality: ${user_id}" >&2
            fi
        fi
        if echo "${currentInstallProtocolType}" | grep -q 9; then
            xray_agent_subscription_hysteria2_proxy_yaml "${user_id}"
        fi
    done
}

xray_agent_subscription_proxy_groups_yaml() {
    local proxy_names=("$@")
    local proxy_name
    echo "proxy-groups:"
    echo "  - name: PROXY"
    echo "    type: select"
    echo "    proxies:"
    echo "      - AUTO"
    echo "      - DIRECT"
    for proxy_name in "${proxy_names[@]}"; do
        printf '      - %s\n' "$(xray_agent_yaml_quote "${proxy_name}")"
    done
    echo "  - name: AUTO"
    echo "    type: url-test"
    echo "    url: https://www.gstatic.com/generate_204"
    echo "    interval: 300"
    echo "    proxies:"
    for proxy_name in "${proxy_names[@]}"; do
        printf '      - %s\n' "$(xray_agent_yaml_quote "${proxy_name}")"
    done
}

xray_agent_build_clash_subscription() {
    local users=("$@")
    local proxy_names=()
    local rule_lines="${XRAY_AGENT_SUBSCRIPTION_RULE_LINES:-}"

    if [[ "${#users[@]}" -eq 0 ]]; then
        mapfile -t users < <(xray_agent_subscription_users)
    fi
    mapfile -t proxy_names < <(xray_agent_subscription_proxy_names "${users[@]}")
    if [[ "${#proxy_names[@]}" -eq 0 ]]; then
        echoContent red " ---> 未生成可用 Mihomo 节点" >&2
        return 1
    fi
    if [[ -z "${rule_lines}" ]]; then
        rule_lines="$(xray_agent_subscription_default_rule_lines)"
    fi

    echo "mixed-port: 7890"
    echo "allow-lan: false"
    echo "mode: rule"
    echo "log-level: info"
    echo "ipv6: true"
    xray_agent_subscription_proxies_yaml "${users[@]}"
    xray_agent_subscription_proxy_groups_yaml "${proxy_names[@]}"
    xray_agent_subscription_rule_provider_yaml "${rule_lines}"
    xray_agent_subscription_rules_yaml "${rule_lines}"
}

xray_agent_subscription_print_clash() {
    local users=()
    local rule_lines
    xray_agent_subscription_prepare_state || return 1
    mapfile -t users < <(xray_agent_subscription_select_users)
    [[ "${#users[@]}" -gt 0 ]] || return 1
    rule_lines="$(xray_agent_subscription_select_rule_lines)"
    [[ -n "${rule_lines}" ]] || rule_lines="$(xray_agent_subscription_default_rule_lines)"

    XRAY_AGENT_SUBSCRIPTION_RULE_LINES="${rule_lines}"
    xray_agent_blank
    echoContent skyBlue "-------------------------Clash/Mihomo订阅---------------------"
    xray_agent_build_clash_subscription "${users[@]}"
    xray_agent_blank
    echoContent yellow "提示: 规则来自第三方仓库，导入前请确认客户端支持 Mihomo 的 VLESS/Reality/XHTTP/Hysteria2 字段。"
}

xray_agent_subscription_print_supported_protocols() {
    xray_agent_subscription_prepare_state || return 1
    xray_agent_blank
    echoContent skyBlue "-------------------------订阅支持状态-------------------------"
    if echo "${currentInstallProtocolType}" | grep -q 0; then
        echoContent green "VLESS TCP TLS: 通用订阅 + Clash/Mihomo"
    fi
    if echo "${currentInstallProtocolType}" | grep -q 1; then
        echoContent green "VLESS WS TLS: 通用订阅 + Clash/Mihomo"
    fi
    if echo "${currentInstallProtocolType}" | grep -q 2; then
        echoContent green "VMess WS TLS: 通用订阅 + Clash/Mihomo"
    fi
    if echo "${currentInstallProtocolType}" | grep -q 7; then
        echoContent green "VLESS TCP Reality: 通用订阅 + Clash/Mihomo"
    fi
    if echo "${currentInstallProtocolType}" | grep -q 8; then
        echoContent green "VLESS XHTTP: 通用订阅 + Mihomo"
    fi
    if echo "${currentInstallProtocolType}" | grep -q 9; then
        echoContent green "Hysteria2: 通用订阅 + Clash/Mihomo"
    fi
    echoContent yellow "订阅只在菜单中显示，不生成公网订阅 URL。"
}

xray_agent_subscription_next_custom_rule_id() {
    xray_agent_subscription_rule_presets | awk -F '|' '
        $1 ~ /^[0-9]+$/ && $1 > max_id { max_id = $1 }
        END { print max_id + 1 }
    '
}

xray_agent_subscription_ensure_custom_rules_file() {
    local custom_rules_file custom_rules_dir
    custom_rules_file="$(xray_agent_subscription_custom_rules_file)"
    custom_rules_dir="$(dirname "${custom_rules_file}")"
    mkdir -p "${custom_rules_dir}"
    if [[ ! -f "${custom_rules_file}" ]]; then
        printf '{\n  "rules": []\n}\n' >"${custom_rules_file}"
    fi
    if ! jq -e '.rules | type == "array"' "${custom_rules_file}" >/dev/null 2>&1; then
        echoContent red " ---> 自定义规则文件格式错误: ${custom_rules_file}"
        return 1
    fi
}

xray_agent_subscription_append_custom_rule() {
    local id="$1"
    local name="$2"
    local behavior="$3"
    local format="$4"
    local url="$5"
    local target="$6"
    local custom_rules_file temp_file

    xray_agent_subscription_ensure_custom_rules_file || return 1
    custom_rules_file="$(xray_agent_subscription_custom_rules_file)"
    temp_file="$(mktemp)"
    if jq \
        --argjson id "${id}" \
        --arg label "自定义 ${name}" \
        --arg name "${name}" \
        --arg behavior "${behavior}" \
        --arg format "${format}" \
        --arg url "${url}" \
        --arg target "${target}" \
        '.rules += [{
            id: $id,
            label: $label,
            name: $name,
            behavior: $behavior,
            format: $format,
            url: $url,
            target: $target
        }]' \
        "${custom_rules_file}" >"${temp_file}"; then
        mv "${temp_file}" "${custom_rules_file}"
    else
        rm -f "${temp_file}"
        return 1
    fi
}

xray_agent_subscription_add_custom_rule() {
    local name behavior format url target next_id
    echoContent skyBlue "-------------------------自定义规则源-------------------------"
    read -r -p "规则源名称[英文/数字/_/-]:" name
    if [[ ! "${name}" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echoContent red " ---> 名称不合法"
        return 1
    fi
    read -r -p "behavior[domain/ipcidr/classical]:" behavior
    if [[ ! "${behavior}" =~ ^(domain|ipcidr|classical)$ ]]; then
        echoContent red " ---> behavior 不合法"
        return 1
    fi
    read -r -p "format[yaml/text/mrs]:" format
    if [[ ! "${format}" =~ ^(yaml|text|mrs)$ ]]; then
        echoContent red " ---> format 不合法"
        return 1
    fi
    read -r -p "规则 raw URL:" url
    if [[ "${url}" != http://* && "${url}" != https://* ]]; then
        echoContent red " ---> URL 不合法"
        return 1
    fi
    read -r -p "策略[PROXY/DIRECT/REJECT，回车=PROXY]:" target
    target="${target:-PROXY}"
    if [[ ! "${target}" =~ ^(PROXY|DIRECT|REJECT)$ ]]; then
        echoContent red " ---> 策略不合法"
        return 1
    fi

    next_id="$(xray_agent_subscription_next_custom_rule_id)"
    xray_agent_subscription_append_custom_rule "${next_id}" "${name}" "${behavior}" "${format}" "${url}" "${target}" || return 1
    echoContent green " ---> 已保存自定义规则: ${name}"
    echoContent yellow " ---> 文件: $(xray_agent_subscription_custom_rules_file)"
    if xray_agent_prompt_yes_no "是否立即生成 Clash/Mihomo 订阅？" "y"; then
        xray_agent_subscription_print_clash
    fi
}

xray_agent_subscription_menu() {
    local selected_item
    xray_agent_tool_status_header "订阅管理"
    if [[ -z "${coreInstallType}" ]]; then
        echoContent red " ---> 未安装，请先安装 TLS 或 Reality 套餐"
        return 1
    fi
    echoContent yellow "1.查看通用订阅"
    echoContent yellow "2.查看 Clash/Mihomo 订阅"
    echoContent yellow "3.查看当前支持协议"
    echoContent yellow "4.自定义规则源"
    echoContent red "=============================================================="
    read -r -p "请输入:" selected_item
    case "${selected_item}" in
        1) xray_agent_subscription_print_universal ;;
        2) xray_agent_subscription_print_clash ;;
        3) xray_agent_subscription_print_supported_protocols ;;
        4) xray_agent_subscription_add_custom_rule ;;
        *) echoContent red " ---> 选择错误" ;;
    esac
}
