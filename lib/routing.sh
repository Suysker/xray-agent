#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

XRAY_AGENT_EGRESS_POLICY_SCHEMA_VERSION=1

xray_agent_egress_policy_path() {
    printf '%s/state/egress-policy.json\n' "${XRAY_AGENT_ETC_DIR:-/etc/xray-agent}"
}

xray_agent_routing_config_path() {
    printf '%s09_routing.json\n' "${configPath}"
}

xray_agent_outbounds_config_path() {
    printf '%s10_outbounds.json\n' "${configPath}"
}

xray_agent_dns_config_path() {
    printf '%s11_dns.json\n' "${configPath}"
}

xray_agent_geosite_domains_json() {
    local domain_list="$1"
    jq -nc --arg domainList "${domain_list}" '
      $domainList
      | split(",")
      | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
      | map(select(length > 0))
      | map(if startswith("geosite:") then . else "geosite:" + . end)
      | unique
    '
}

xray_agent_private_destination_rule_json() {
    jq -nc '{
      type:"field",
      ip:[
        "0.0.0.0/8",
        "10.0.0.0/8",
        "100.64.0.0/10",
        "127.0.0.0/8",
        "169.254.0.0/16",
        "172.16.0.0/12",
        "192.0.0.0/24",
        "192.0.2.0/24",
        "192.88.99.0/24",
        "192.168.0.0/16",
        "198.18.0.0/15",
        "198.51.100.0/24",
        "203.0.113.0/24",
        "224.0.0.0/3",
        "::/127",
        "fc00::/7",
        "fe80::/10",
        "ff00::/8"
      ],
      outboundTag:"blackhole-out"
    }'
}

xray_agent_egress_default_policy_json() {
    local tcp_egress udp_egress tcp_preference=ipv4 candidate
    xray_agent_detect_network_capabilities
    if xray_agent_egress_is_available system-auto-out; then
        tcp_egress=system-auto-out
    else
        candidate="$(xray_agent_egress_effective_family_id ipv4)"
        if [[ -n "${candidate}" ]] && xray_agent_egress_is_available "${candidate}"; then
            tcp_egress="${candidate}"
        else
            candidate="$(xray_agent_egress_effective_family_id ipv6)"
            if [[ -n "${candidate}" ]] && xray_agent_egress_is_available "${candidate}"; then
                tcp_egress="${candidate}"
                tcp_preference=ipv6
            else
                tcp_egress="$(xray_agent_egress_catalog_json | jq -r '.egresses[] | select(.available and .family != "auto") | .id' | head -1)"
            fi
        fi
    fi

    candidate="$(xray_agent_egress_effective_family_id ipv4)"
    if [[ -n "${candidate}" ]] && xray_agent_egress_is_available "${candidate}"; then
        udp_egress="${candidate}"
    else
        candidate="$(xray_agent_egress_effective_family_id ipv6)"
        if [[ -n "${candidate}" ]] && xray_agent_egress_is_available "${candidate}"; then
            udp_egress="${candidate}"
        else
            udp_egress="$(xray_agent_egress_catalog_json | jq -r '.egresses[] | select(.available and .family != "auto") | .id' | head -1)"
        fi
    fi

    [[ -n "${tcp_egress}" && -n "${udp_egress}" ]] || return 1
    jq -nc \
        --argjson schemaVersion "${XRAY_AGENT_EGRESS_POLICY_SCHEMA_VERSION}" \
        --arg defaultTcpEgress "${tcp_egress}" \
        --arg defaultTcpPreference "${tcp_preference}" \
        --arg defaultUdpEgress "${udp_egress}" \
        '{schemaVersion:$schemaVersion,defaultTcpEgress:$defaultTcpEgress,defaultTcpPreference:$defaultTcpPreference,defaultUdpEgress:$defaultUdpEgress,rules:[]}'
}

xray_agent_egress_policy_normalize_json() {
    local policy_json="$1"
    jq -c '
      .defaultTcpPreference = (.defaultTcpPreference // "ipv4")
      | .rules = [
          .rules[]?
          | .tcpPreference = (.tcpPreference // "ipv4")
          | .match.domain = ((.match.domain // []) | unique)
          | .match.ip = ((.match.ip // []) | unique)
          | .match |= with_entries(select(.value | length > 0))
        ]
    ' <<<"${policy_json}"
}

xray_agent_egress_policy_validate_json() {
    local policy_json="$1"
    local normalized_json catalog_json
    normalized_json="$(xray_agent_egress_policy_normalize_json "${policy_json}")" || return 1
    catalog_json="$(xray_agent_egress_catalog_json)" || return 1
    jq -e --argjson catalog "${catalog_json}" '
      def available($id):
        $id == "blackhole-out" or any($catalog.egresses[]; .id == $id and .available == true);
      def automatic($id): $id | endswith("-auto-out");
      def tcp_egress($id): available($id);
      def udp_egress($id): available($id) and (automatic($id) | not);
      (.schemaVersion == 1)
      and ((keys - ["schemaVersion","defaultTcpEgress","defaultTcpPreference","defaultUdpEgress","rules"]) | length == 0)
      and (.defaultTcpEgress | type == "string" and tcp_egress(.))
      and (.defaultTcpPreference == "ipv4" or .defaultTcpPreference == "ipv6")
      and (.defaultUdpEgress | type == "string" and udp_egress(.))
      and (.rules | type == "array")
      and (([.rules[].id] | length) == ([.rules[].id] | unique | length))
      and all(.rules[];
        ((keys - ["id","match","tcpEgress","tcpPreference","udpEgress"]) | length == 0)
        and (.id | type == "string" and test("^[a-z0-9][a-z0-9._-]*$"))
        and (.match | type == "object")
        and ((.match | keys) - ["domain","ip"] | length == 0)
        and ((.match.domain // []) | type == "array" and all(.[]; type == "string" and length > 0))
        and ((.match.ip // []) | type == "array" and all(.[]; type == "string" and length > 0))
        and ((((.match.domain // []) | length) + ((.match.ip // []) | length)) > 0)
        and (.tcpEgress | type == "string" and tcp_egress(.))
        and (.tcpPreference == "ipv4" or .tcpPreference == "ipv6")
        and (.udpEgress | type == "string" and udp_egress(.))
      )
    ' <<<"${normalized_json}" >/dev/null
}

xray_agent_egress_policy_read() {
    local policy_path
    policy_path="$(xray_agent_egress_policy_path)"
    [[ -r "${policy_path}" ]] || return 1
    jq -c . "${policy_path}"
}

xray_agent_routing_rule_json() {
    local match_json="$1"
    local network="$2"
    local outbound_tag="$3"
    jq -nc --argjson match "${match_json}" --arg network "${network}" --arg outboundTag "${outbound_tag}" '$match + {type:"field",network:$network,outboundTag:$outboundTag}'
}

xray_agent_routing_rules_json_for_policy() {
    local policy_json="$1"
    local rules_jsons=()
    local row match_json tcp_egress tcp_preference udp_egress tcp_tag udp_tag
    rules_jsons+=("$(xray_agent_private_destination_rule_json)")
    while IFS= read -r row; do
        match_json="$(jq -c '.match' <<<"${row}")"
        tcp_egress="$(jq -r '.tcpEgress' <<<"${row}")"
        tcp_preference="$(jq -r '.tcpPreference' <<<"${row}")"
        udp_egress="$(jq -r '.udpEgress' <<<"${row}")"
        tcp_tag="$(xray_agent_egress_outbound_tag "${tcp_egress}" "${tcp_preference}")"
        udp_tag="$(xray_agent_egress_outbound_tag "${udp_egress}" ipv4)"
        rules_jsons+=("$(xray_agent_routing_rule_json "${match_json}" tcp "${tcp_tag}")")
        rules_jsons+=("$(xray_agent_routing_rule_json "${match_json}" udp "${udp_tag}")")
    done < <(jq -c '.rules[]' <<<"${policy_json}")

    tcp_egress="$(jq -r '.defaultTcpEgress' <<<"${policy_json}")"
    tcp_preference="$(jq -r '.defaultTcpPreference' <<<"${policy_json}")"
    udp_egress="$(jq -r '.defaultUdpEgress' <<<"${policy_json}")"
    tcp_tag="$(xray_agent_egress_outbound_tag "${tcp_egress}" "${tcp_preference}")"
    udp_tag="$(xray_agent_egress_outbound_tag "${udp_egress}" ipv4)"
    rules_jsons+=("$(xray_agent_routing_rule_json '{}' tcp "${tcp_tag}")")
    rules_jsons+=("$(xray_agent_routing_rule_json '{}' udp "${udp_tag}")")
    printf '%s\n' "${rules_jsons[@]}" | jq -sc .
}

xray_agent_outbounds_json_for_policy() {
    local policy_json="$1"
    local specs=()
    local outbounds=()
    local -A seen_tags=()
    local row egress_id preference tag outbound_json
    specs+=("$(jq -r '[.defaultTcpEgress,.defaultTcpPreference] | @tsv' <<<"${policy_json}")")
    specs+=("$(jq -r '[.defaultUdpEgress,"ipv4"] | @tsv' <<<"${policy_json}")")
    while IFS= read -r row; do
        specs+=("$(jq -r '[.tcpEgress,.tcpPreference] | @tsv' <<<"${row}")")
        specs+=("$(jq -r '[.udpEgress,"ipv4"] | @tsv' <<<"${row}")")
    done < <(jq -c '.rules[]' <<<"${policy_json}")
    specs+=("blackhole-out"$'\t'"ipv4")

    for row in "${specs[@]}"; do
        IFS=$'\t' read -r egress_id preference <<<"${row}"
        tag="$(xray_agent_egress_outbound_tag "${egress_id}" "${preference}")"
        [[ -z "${seen_tags[${tag}]:-}" ]] || continue
        outbound_json="$(xray_agent_egress_outbound_json_for_id "${egress_id}" "${preference}")" || return 1
        outbounds+=("${outbound_json}")
        seen_tags["${tag}"]=true
    done
    printf '%s\n' "${outbounds[@]}" | jq -sc .
}

xray_agent_routing_dns_json_for_policy() {
    local dns_path
    dns_path="$(xray_agent_dns_config_path)"
    if [[ -r "${dns_path}" ]]; then
        jq -c '.dns = ((.dns // {}) + {queryStrategy:"UseIP"})' "${dns_path}"
    else
        jq -nc '{dns:{servers:["localhost"],queryStrategy:"UseIP"}}'
    fi
}

xray_agent_routing_staged_config_test() {
    local routing_json="$1"
    local outbounds_json="$2"
    local dns_json="$3"
    local staged_dir
    [[ "${XRAY_AGENT_SKIP_XRAY_CONFIG_TEST:-false}" == "true" ]] && return 0
    declare -F xray_agent_xray_binary_ready >/dev/null 2>&1 || return 0
    xray_agent_xray_binary_ready || return 0
    staged_dir="$(mktemp -d)"
    if [[ -d "${configPath}" ]]; then
        cp -a "${configPath}." "${staged_dir}/"
    fi
    printf '%s\n' "${routing_json}" | jq . >"${staged_dir}/09_routing.json"
    printf '%s\n' "${outbounds_json}" | jq . >"${staged_dir}/10_outbounds.json"
    printf '%s\n' "${dns_json}" | jq . >"${staged_dir}/11_dns.json"
    if ! "${ctlPath}" run -test -confdir "${staged_dir}" >/tmp/xray-agent-egress-test.log 2>&1; then
        rm -rf -- "${staged_dir}"
        return 1
    fi
    rm -rf -- "${staged_dir}"
}

xray_agent_routing_documents_json() {
    local policy_json="$1"
    local normalized_json routing_rules_json outbounds_json dns_json routing_json outbounds_file_json
    normalized_json="$(xray_agent_egress_policy_normalize_json "${policy_json}")" || return 1
    xray_agent_egress_policy_validate_json "${normalized_json}" || return 1
    routing_rules_json="$(xray_agent_routing_rules_json_for_policy "${normalized_json}")" || return 1
    outbounds_json="$(xray_agent_outbounds_json_for_policy "${normalized_json}")" || return 1
    dns_json="$(xray_agent_routing_dns_json_for_policy)" || return 1
    routing_json="$(jq -nc --argjson rules "${routing_rules_json}" '{routing:{domainStrategy:"IPOnDemand",rules:$rules}}')" || return 1
    outbounds_file_json="$(jq -nc --argjson outbounds "${outbounds_json}" '{outbounds:$outbounds}')" || return 1
    jq -nc \
        --argjson policy "${normalized_json}" \
        --argjson routing "${routing_json}" \
        --argjson outbounds "${outbounds_file_json}" \
        --argjson dns "${dns_json}" \
        '{policy:$policy,routing:$routing,outbounds:$outbounds,dns:$dns}'
}

xray_agent_routing_restore_transaction_target() {
    local transaction_dir="$1"
    local name="$2"
    local target_path="$3"
    if [[ -e "${transaction_dir}/original-${name}" ]]; then
        cp -a "${transaction_dir}/original-${name}" "${target_path}"
    else
        rm -f -- "${target_path}"
    fi
}

xray_agent_routing_apply_policy_json() {
    local policy_json="$1"
    local documents_json normalized_json dns_json routing_json outbounds_file_json
    local policy_path routing_path outbounds_path dns_path transaction_dir previous_network_json
    documents_json="$(xray_agent_routing_documents_json "${policy_json}")" || return 1
    normalized_json="$(jq -c '.policy' <<<"${documents_json}")"
    routing_json="$(jq -c '.routing' <<<"${documents_json}")"
    outbounds_file_json="$(jq -c '.outbounds' <<<"${documents_json}")"
    dns_json="$(jq -c '.dns' <<<"${documents_json}")"
    xray_agent_routing_staged_config_test "${routing_json}" "${outbounds_file_json}" "${dns_json}" || return 1

    policy_path="$(xray_agent_egress_policy_path)"
    routing_path="$(xray_agent_routing_config_path)"
    outbounds_path="$(xray_agent_outbounds_config_path)"
    dns_path="$(xray_agent_dns_config_path)"
    mkdir -p "$(dirname "${policy_path}")" "${configPath}"
    transaction_dir="$(mktemp -d "$(dirname "${policy_path}")/.egress-apply.XXXXXX")"
    if ! printf '%s\n' "${normalized_json}" | jq . >"${transaction_dir}/egress-policy.json" ||
        ! printf '%s\n' "${routing_json}" | jq . >"${transaction_dir}/09_routing.json" ||
        ! printf '%s\n' "${outbounds_file_json}" | jq . >"${transaction_dir}/10_outbounds.json" ||
        ! printf '%s\n' "${dns_json}" | jq . >"${transaction_dir}/11_dns.json"; then
        rm -rf -- "${transaction_dir}"
        return 1
    fi
    [[ -e "${policy_path}" ]] && cp -a "${policy_path}" "${transaction_dir}/original-egress-policy.json"
    [[ -e "${routing_path}" ]] && cp -a "${routing_path}" "${transaction_dir}/original-09_routing.json"
    [[ -e "${outbounds_path}" ]] && cp -a "${outbounds_path}" "${transaction_dir}/original-10_outbounds.json"
    [[ -e "${dns_path}" ]] && cp -a "${dns_path}" "${transaction_dir}/original-11_dns.json"

    previous_network_json="$(xray_agent_network_policy_current_json)" || {
        rm -rf -- "${transaction_dir}"
        return 1
    }
    if ! xray_agent_network_policy_reconcile_egress_policy "${normalized_json}"; then
        rm -rf -- "${transaction_dir}"
        return 1
    fi

    if ! mv "${transaction_dir}/egress-policy.json" "${policy_path}" ||
        ! mv "${transaction_dir}/09_routing.json" "${routing_path}" ||
        ! mv "${transaction_dir}/10_outbounds.json" "${outbounds_path}" ||
        ! mv "${transaction_dir}/11_dns.json" "${dns_path}"; then
        xray_agent_routing_restore_transaction_target "${transaction_dir}" egress-policy.json "${policy_path}"
        xray_agent_routing_restore_transaction_target "${transaction_dir}" 09_routing.json "${routing_path}"
        xray_agent_routing_restore_transaction_target "${transaction_dir}" 10_outbounds.json "${outbounds_path}"
        xray_agent_routing_restore_transaction_target "${transaction_dir}" 11_dns.json "${dns_path}"
        xray_agent_network_policy_reconcile_json "${previous_network_json}" || true
        rm -rf -- "${transaction_dir}"
        return 1
    fi
    chmod 600 "${policy_path}" 2>/dev/null || true
    rm -rf -- "${transaction_dir}"
}

xray_agent_routing_policy_is_materialized() {
    local policy_json="$1"
    local documents_json expected current field path
    documents_json="$(xray_agent_routing_documents_json "${policy_json}")" || return 1
    for field in routing outbounds dns; do
        case "${field}" in
            routing) path="$(xray_agent_routing_config_path)" ;;
            outbounds) path="$(xray_agent_outbounds_config_path)" ;;
            dns) path="$(xray_agent_dns_config_path)" ;;
        esac
        [[ -r "${path}" ]] || return 1
        expected="$(jq -S -c ".${field}" <<<"${documents_json}")" || return 1
        current="$(jq -S -c . "${path}")" || return 1
        [[ "${expected}" == "${current}" ]] || return 1
    done
}

xray_agent_egress_reconcile_current_policy() {
    local reload_service="${1:-false}"
    local policy_json
    policy_json="$(xray_agent_egress_policy_read)" || return 0
    xray_agent_egress_policy_validate_json "${policy_json}" || return 1
    xray_agent_routing_policy_is_materialized "${policy_json}" && return 0
    if declare -F xray_agent_backup_create >/dev/null 2>&1; then
        xray_agent_backup_create egress-policy-reconcile true >/dev/null || return 1
    fi
    xray_agent_routing_apply_policy_json "${policy_json}" || return 1
    echoContent green " ---> 已从 egress-policy.json 重新生成 Xray 出站和路由"
    if [[ "${reload_service}" == "true" ]] && declare -F xray_agent_refresh_xray_service >/dev/null 2>&1; then
        xray_agent_refresh_xray_service || return 1
    fi
}

xray_agent_egress_ensure_policy() {
    local policy_json
    if policy_json="$(xray_agent_egress_policy_read 2>/dev/null)"; then
        xray_agent_egress_policy_validate_json "${policy_json}"
        return $?
    fi
    policy_json="$(xray_agent_egress_default_policy_json)" || return 1
    xray_agent_routing_apply_policy_json "${policy_json}"
}

xray_agent_default_outbounds_json() {
    local policy_json
    xray_agent_egress_ensure_policy || return 1
    policy_json="$(xray_agent_egress_policy_read)" || return 1
    xray_agent_outbounds_json_for_policy "${policy_json}"
}

xray_agent_default_routing_rules_json() {
    local policy_json
    xray_agent_egress_ensure_policy || return 1
    policy_json="$(xray_agent_egress_policy_read)" || return 1
    xray_agent_routing_rules_json_for_policy "${policy_json}"
}

xray_agent_default_routing_domain_strategy() {
    printf 'IPOnDemand\n'
}

xray_agent_default_dns_query_strategy() {
    printf 'UseIP\n'
}

xray_agent_default_dns_servers_json() {
    jq -nc '["localhost"]'
}

xray_agent_routing_status_summary() {
    local policy_json rule_count
    echoContent skyBlue "-------------------------出口策略状态-----------------------------"
    if ! policy_json="$(xray_agent_egress_policy_read 2>/dev/null)"; then
        echoContent yellow "尚未建立 egress-policy.json"
        return 0
    fi
    rule_count="$(jq -r '.rules | length' <<<"${policy_json}")"
    echoContent yellow "TCP默认: $(jq -r '.defaultTcpEgress + " / " + .defaultTcpPreference' <<<"${policy_json}")"
    echoContent yellow "UDP默认: $(jq -r '.defaultUdpEgress' <<<"${policy_json}")"
    echoContent yellow "规则数量: ${rule_count}"
    echoContent yellow "实际系统路径: $(xray_agent_egress_effective_path_label)"
}

xray_agent_egress_print_catalog() {
    local usage="$1"
    xray_agent_egress_catalog_json | jq -r --arg usage "${usage}" '
      .egresses[]
      | select(.available == true)
      | select($usage == "tcp" or .family != "auto")
      | [.id,.provider,.family,(if .interface == "" then "system" else .interface end)]
      | @tsv
    ' | awk -F '\t' '{printf "%d.%s  提供者=%s 地址族=%s 接口=%s\n", NR, $1, $2, $3, $4}'
}

xray_agent_egress_select() {
    local usage="$1"
    local selected
    local -a ids=()
    while IFS= read -r selected; do
        ids+=("${selected}")
    done < <(xray_agent_egress_catalog_json | jq -r --arg usage "${usage}" '.egresses[] | select(.available == true) | select($usage == "tcp" or .family != "auto") | .id')
    [[ "${#ids[@]}" -gt 0 ]] || return 1
    xray_agent_egress_print_catalog "${usage}"
    read -r -p "请选择出口:" selected
    [[ "${selected}" =~ ^[0-9]+$ && "${selected}" -ge 1 && "${selected}" -le "${#ids[@]}" ]] || return 1
    XRAY_AGENT_SELECTED_EGRESS="${ids[$((selected - 1))]}"
}

xray_agent_egress_select_preference() {
    local egress_id="$1"
    local selected
    XRAY_AGENT_SELECTED_PREFERENCE=ipv4
    [[ "${egress_id}" == *-auto-out ]] || return 0
    echoContent yellow "1.IPv4 优先（TCP 自动回退）"
    echoContent yellow "2.IPv6 优先（TCP 自动回退）"
    read -r -p "请选择地址族优先级:" selected
    case "${selected}" in
        1) XRAY_AGENT_SELECTED_PREFERENCE=ipv4 ;;
        2) XRAY_AGENT_SELECTED_PREFERENCE=ipv6 ;;
        *) return 1 ;;
    esac
}

xray_agent_routing_apply_interactive_policy() {
    local policy_json="$1"
    local reason="$2"
    xray_agent_egress_policy_validate_json "${policy_json}" || {
        echoContent red " ---> 策略校验失败，未修改配置"
        return 1
    }
    if declare -F xray_agent_backup_create >/dev/null 2>&1; then
        xray_agent_backup_create "${reason}" true >/dev/null || return 1
    fi
    xray_agent_routing_apply_policy_json "${policy_json}" || {
        echoContent red " ---> 策略应用失败，旧配置保持不变"
        return 1
    }
    reloadCore
}

xray_agent_default_egress_menu() {
    local selected policy_json
    xray_agent_tool_status_header "默认 Xray 出站"
    xray_agent_egress_ensure_policy || return 1
    xray_agent_routing_status_summary
    echoContent yellow "1.设置 TCP 默认出口"
    echoContent yellow "2.设置 UDP 默认出口"
    echoContent yellow "3.查看出口目录"
    read -r -p "请选择:" selected
    policy_json="$(xray_agent_egress_policy_read)"
    case "${selected}" in
        1)
            xray_agent_egress_select tcp || return 0
            xray_agent_egress_select_preference "${XRAY_AGENT_SELECTED_EGRESS}" || return 0
            policy_json="$(jq -c --arg egress "${XRAY_AGENT_SELECTED_EGRESS}" --arg preference "${XRAY_AGENT_SELECTED_PREFERENCE}" '.defaultTcpEgress=$egress | .defaultTcpPreference=$preference' <<<"${policy_json}")"
            ;;
        2)
            xray_agent_egress_select udp || return 0
            policy_json="$(jq -c --arg egress "${XRAY_AGENT_SELECTED_EGRESS}" '.defaultUdpEgress=$egress' <<<"${policy_json}")"
            ;;
        3)
            xray_agent_egress_catalog_json | jq .
            return 0
            ;;
        *) return 0 ;;
    esac
    xray_agent_confirm_action "确认应用新的默认出口？" "n" || return 0
    xray_agent_routing_apply_interactive_policy "${policy_json}" egress-default-change
}

xray_agent_rule_id_valid() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9._-]*$ ]]
}

xray_agent_egress_add_domain_rule() {
    local policy_json="$1"
    local rule_id domain_list domains_json rule_json tcp_egress tcp_preference udp_egress
    XRAY_AGENT_CANDIDATE_POLICY_JSON=
    read -r -p "规则 ID（小写字母、数字、点、下划线或连字符）:" rule_id
    xray_agent_rule_id_valid "${rule_id}" || return 1
    read -r -p "geosite 列表，例如 openai,geosite:netflix:" domain_list
    domains_json="$(xray_agent_geosite_domains_json "${domain_list}")"
    [[ "$(jq -r 'length' <<<"${domains_json}")" -gt 0 ]] || return 1
    echoContent yellow "选择 TCP 出口"
    xray_agent_egress_select tcp || return 1
    tcp_egress="${XRAY_AGENT_SELECTED_EGRESS}"
    xray_agent_egress_select_preference "${tcp_egress}" || return 1
    tcp_preference="${XRAY_AGENT_SELECTED_PREFERENCE}"
    echoContent yellow "选择 UDP 出口"
    xray_agent_egress_select udp || return 1
    udp_egress="${XRAY_AGENT_SELECTED_EGRESS}"
    rule_json="$(jq -nc --arg id "${rule_id}" --argjson domains "${domains_json}" --arg tcpEgress "${tcp_egress}" --arg tcpPreference "${tcp_preference}" --arg udpEgress "${udp_egress}" '{id:$id,match:{domain:$domains},tcpEgress:$tcpEgress,tcpPreference:$tcpPreference,udpEgress:$udpEgress}')"
    XRAY_AGENT_CANDIDATE_POLICY_JSON="$(jq -c --arg id "${rule_id}" --argjson rule "${rule_json}" '.rules = ([.rules[] | select(.id != $id)] + [$rule])' <<<"${policy_json}")"
}

xray_agent_egress_add_cn_rule() {
    local policy_json="$1"
    local tcp_egress tcp_preference udp_egress
    XRAY_AGENT_CANDIDATE_POLICY_JSON=
    echoContent yellow "选择中国大陆域名/IP 的 TCP 出口"
    xray_agent_egress_select tcp || return 1
    tcp_egress="${XRAY_AGENT_SELECTED_EGRESS}"
    xray_agent_egress_select_preference "${tcp_egress}" || return 1
    tcp_preference="${XRAY_AGENT_SELECTED_PREFERENCE}"
    echoContent yellow "选择中国大陆域名/IP 的 UDP 出口"
    xray_agent_egress_select udp || return 1
    udp_egress="${XRAY_AGENT_SELECTED_EGRESS}"
    XRAY_AGENT_CANDIDATE_POLICY_JSON="$(jq -c --arg tcpEgress "${tcp_egress}" --arg tcpPreference "${tcp_preference}" --arg udpEgress "${udp_egress}" '
      .rules = ([.rules[] | select(.id != "cn-egress")] + [{id:"cn-egress",match:{domain:["geosite:cn"],ip:["geoip:cn"]},tcpEgress:$tcpEgress,tcpPreference:$tcpPreference,udpEgress:$udpEgress}])
    ' <<<"${policy_json}")"
}

xray_agent_egress_remove_rule() {
    local policy_json="$1"
    local rule_id
    XRAY_AGENT_CANDIDATE_POLICY_JSON=
    jq -r '.rules[] | [.id,(.match | tostring)] | @tsv' <<<"${policy_json}"
    read -r -p "请输入要删除的规则 ID:" rule_id
    XRAY_AGENT_CANDIDATE_POLICY_JSON="$(jq -c --arg id "${rule_id}" '.rules = [.rules[] | select(.id != $id)]' <<<"${policy_json}")"
}

xray_agent_rule_egress_menu() {
    local selected policy_json candidate_json
    xray_agent_tool_status_header "Xray 规则分流"
    xray_agent_egress_ensure_policy || return 1
    xray_agent_routing_status_summary
    echoContent yellow "1.新增或替换域名规则"
    echoContent yellow "2.删除规则"
    echoContent yellow "3.查看规则"
    echoContent yellow "4.设置中国大陆域名/IP规则"
    read -r -p "请选择:" selected
    policy_json="$(xray_agent_egress_policy_read)"
    case "${selected}" in
        1) xray_agent_egress_add_domain_rule "${policy_json}" || return 0; candidate_json="${XRAY_AGENT_CANDIDATE_POLICY_JSON}" ;;
        2) xray_agent_egress_remove_rule "${policy_json}" || return 0; candidate_json="${XRAY_AGENT_CANDIDATE_POLICY_JSON}" ;;
        3) jq '.rules' <<<"${policy_json}"; return 0 ;;
        4) xray_agent_egress_add_cn_rule "${policy_json}" || return 0; candidate_json="${XRAY_AGENT_CANDIDATE_POLICY_JSON}" ;;
        *) return 0 ;;
    esac
    xray_agent_confirm_action "确认应用规则变更？" "n" || return 0
    xray_agent_routing_apply_interactive_policy "${candidate_json}" egress-rule-change
}

xray_agent_blacklist_rule_json() {
    local rule_id="$1"
    local match_json="$2"
    jq -nc --arg id "${rule_id}" --argjson match "${match_json}" '{id:$id,match:$match,tcpEgress:"blackhole-out",tcpPreference:"ipv4",udpEgress:"blackhole-out"}'
}

blacklist() {
    local selected policy_json candidate_json rule_id domain_list domains_json rule_json
    xray_agent_tool_status_header "黑名单与中国大陆 IP 阻断"
    xray_agent_egress_ensure_policy || return 1
    policy_json="$(xray_agent_egress_policy_read)"
    echoContent yellow "1.新增或替换域名黑名单"
    echoContent yellow "2.删除规则"
    echoContent yellow "3.查看黑名单"
    echoContent yellow "4.启用中国大陆 IP 阻断"
    echoContent yellow "5.卸载中国大陆 IP 阻断"
    read -r -p "请选择:" selected
    case "${selected}" in
        1)
            read -r -p "黑名单规则 ID:" rule_id
            xray_agent_rule_id_valid "${rule_id}" || return 0
            read -r -p "geosite 列表，例如 category-ads-all:" domain_list
            domains_json="$(xray_agent_geosite_domains_json "${domain_list}")"
            rule_json="$(xray_agent_blacklist_rule_json "${rule_id}" "$(jq -nc --argjson domain "${domains_json}" '{domain:$domain}')")"
            candidate_json="$(jq -c --arg id "${rule_id}" --argjson rule "${rule_json}" '.rules = ([.rules[] | select(.id != $id)] + [$rule])' <<<"${policy_json}")"
            ;;
        2) xray_agent_egress_remove_rule "${policy_json}" || return 0; candidate_json="${XRAY_AGENT_CANDIDATE_POLICY_JSON}" ;;
        3) jq '[.rules[] | select(.tcpEgress == "blackhole-out" and .udpEgress == "blackhole-out")]' <<<"${policy_json}"; return 0 ;;
        4)
            rule_json="$(xray_agent_blacklist_rule_json cn-blackhole '{"ip":["geoip:cn"]}')"
            candidate_json="$(jq -c --argjson rule "${rule_json}" '.rules = ([.rules[] | select(.id != "cn-blackhole" and .id != "cn-egress")] + [$rule])' <<<"${policy_json}")"
            ;;
        5) candidate_json="$(jq -c '.rules = [.rules[] | select(.id != "cn-blackhole")]' <<<"${policy_json}")" ;;
        *) return 0 ;;
    esac
    xray_agent_confirm_action "确认应用黑名单变更？" "n" || return 0
    xray_agent_routing_apply_interactive_policy "${candidate_json}" blacklist-change
}

ipv6Routing() {
    xray_agent_default_egress_menu
}

warpRouting() {
    xray_agent_rule_egress_menu
}
