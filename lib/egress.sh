#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_egress_catalog_entry_json() {
    local id="$1"
    local provider="$2"
    local family="$3"
    local interface_name="$4"
    local source_address="$5"
    local available="$6"
    local reason="$7"
    local effective_default="$8"
    jq -nc \
        --arg id "${id}" \
        --arg provider "${provider}" \
        --arg family "${family}" \
        --arg interface "${interface_name}" \
        --arg sourceAddress "${source_address}" \
        --arg reason "${reason}" \
        --argjson available "${available}" \
        --argjson effectiveDefault "${effective_default}" \
        '{
          id:$id,
          provider:$provider,
          family:$family,
          interface:$interface,
          sourceAddress:$sourceAddress,
          available:$available,
          reason:$reason,
          effectiveDefault:$effectiveDefault
        }'
}

xray_agent_egress_auto_available() {
    declare -F xray_agent_xray_supports_safe_happy_eyeballs >/dev/null 2>&1 &&
        xray_agent_xray_supports_safe_happy_eyeballs
}

xray_agent_egress_catalog_json() {
    local entries=()
    local available reason effective_default native_auto_available warp_auto_available system_auto_available network_json
    xray_agent_detect_network_capabilities
    network_json="${networkJSON:-}"
    [[ -n "${network_json}" ]] || network_json='{}'

    available=false
    [[ "${nativeHasIPv4:-false}" == "true" && "${nativeRouteIPv4:-false}" == "true" ]] && available=true
    reason=
    [[ "${available}" == "true" ]] || reason="未发现绑定接口后公网实测可用的原生 IPv4 出口"
    effective_default=false
    [[ "${available}" == "true" && "${defaultIPv4Interface}" == "${nativeIPv4Interface}" ]] && effective_default=true
    entries+=("$(xray_agent_egress_catalog_entry_json native-ipv4-out native ipv4 "${nativeIPv4Interface}" "${nativeIPv4Address}" "${available}" "${reason}" "${effective_default}")")

    available=false
    [[ "${nativeHasIPv6:-false}" == "true" && "${nativeRouteIPv6:-false}" == "true" ]] && available=true
    reason=
    [[ "${available}" == "true" ]] || reason="未发现绑定接口后公网实测可用的原生 IPv6 出口"
    effective_default=false
    [[ "${available}" == "true" && "${defaultIPv6Interface}" == "${nativeIPv6Interface}" ]] && effective_default=true
    entries+=("$(xray_agent_egress_catalog_entry_json native-ipv6-out native ipv6 "${nativeIPv6Interface}" "${nativeIPv6Address}" "${available}" "${reason}" "${effective_default}")")

    available=false
    [[ "${warpHasIPv4:-false}" == "true" && "${warpRouteIPv4:-false}" == "true" ]] && available=true
    reason=
    [[ "${available}" == "true" ]] || reason="未发现绑定接口后公网实测为 WARP 的 IPv4 出口"
    entries+=("$(xray_agent_egress_catalog_entry_json warp-ipv4-out warp ipv4 "${warpInterface}" "$(xray_agent_csv_first "${warpIPv4CSV}")" "${available}" "${reason}" "${warpDefaultIPv4:-false}")")

    available=false
    [[ "${warpHasIPv6:-false}" == "true" && "${warpRouteIPv6:-false}" == "true" ]] && available=true
    reason=
    [[ "${available}" == "true" ]] || reason="未发现绑定接口后公网实测为 WARP 的 IPv6 出口"
    entries+=("$(xray_agent_egress_catalog_entry_json warp-ipv6-out warp ipv6 "${warpInterface}" "$(xray_agent_csv_first "${warpIPv6CSV}")" "${available}" "${reason}" "${warpDefaultIPv6:-false}")")

    system_auto_available=false
    if [[ "${routeIPv4}" == "true" && "${routeIPv6}" == "true" ]] && xray_agent_egress_auto_available; then
        system_auto_available=true
    fi
    reason=
    [[ "${system_auto_available}" == "true" ]] || reason="需要有效 IPv4/IPv6 默认路由和已支持的 TCP Happy Eyeballs"
    entries+=("$(xray_agent_egress_catalog_entry_json system-auto-out system auto "" "" "${system_auto_available}" "${reason}" "${system_auto_available}")")

    native_auto_available=false
    if [[ "${nativeHasIPv4}" == "true" && "${nativeHasIPv6}" == "true" && "${nativeRouteIPv4:-false}" == "true" && "${nativeRouteIPv6:-false}" == "true" && "${nativeIPv4Interface}" == "${nativeIPv6Interface}" ]] && xray_agent_egress_auto_available; then
        native_auto_available=true
    fi
    reason=
    [[ "${native_auto_available}" == "true" ]] || reason="需要同一原生接口具备 IPv4/IPv6 和已支持的 TCP Happy Eyeballs"
    entries+=("$(xray_agent_egress_catalog_entry_json native-auto-out native auto "${nativeIPv4Interface}" "" "${native_auto_available}" "${reason}" false)")

    warp_auto_available=false
    if [[ "${warpHasIPv4}" == "true" && "${warpHasIPv6}" == "true" && "${warpRouteIPv4:-false}" == "true" && "${warpRouteIPv6:-false}" == "true" ]] && xray_agent_egress_auto_available; then
        warp_auto_available=true
    fi
    reason=
    [[ "${warp_auto_available}" == "true" ]] || reason="需要同一 WARP 接口具备 IPv4/IPv6 和已支持的 TCP Happy Eyeballs"
    entries+=("$(xray_agent_egress_catalog_entry_json warp-auto-out warp auto "${warpInterface}" "" "${warp_auto_available}" "${reason}" false)")

    printf '%s\n' "${entries[@]}" | jq -sc --argjson network "${network_json}" '{schemaVersion:1,network:$network,egresses:.}'
}

xray_agent_egress_get() {
    local egress_id="$1"
    xray_agent_egress_catalog_json | jq -c --arg id "${egress_id}" '.egresses[] | select(.id == $id)'
}

xray_agent_egress_is_available() {
    local egress_id="$1"
    [[ "$(xray_agent_egress_get "${egress_id}" | jq -r '.available // false')" == "true" ]]
}

xray_agent_egress_effective_family_id() {
    local family="$1"
    local interface_name
    xray_agent_detect_network_capabilities
    if [[ "${family}" == "ipv4" ]]; then
        interface_name="${defaultIPv4Interface}"
    else
        interface_name="${defaultIPv6Interface}"
    fi
    if [[ -n "${warpInterface}" && "${interface_name}" == "${warpInterface}" ]]; then
        printf 'warp-%s-out\n' "${family}"
    elif [[ -n "${interface_name}" ]]; then
        printf 'native-%s-out\n' "${family}"
    fi
}

xray_agent_egress_outbound_tag() {
    local egress_id="$1"
    local preference="${2:-ipv4}"
    local network="${3:-tcp}"
    if [[ "${egress_id}" == *-auto-out ]]; then
        if [[ "${network}" == udp ]]; then
            printf '%s-udp-%s-first\n' "${egress_id%-out}" "${preference}"
        else
            printf '%s-%s-first\n' "${egress_id%-out}" "${preference}"
        fi
    else
        printf '%s\n' "${egress_id}"
    fi
}

xray_agent_egress_outbound_json_for_id() {
    local egress_id="$1"
    local preference="${2:-ipv4}"
    local network="${3:-tcp}"
    local entry tag family interface_name source_address
    if [[ "${egress_id}" == "blackhole-out" ]]; then
        xray_agent_egress_blackhole_outbound_json
        return
    fi
    entry="$(xray_agent_egress_get "${egress_id}")"
    [[ -n "${entry}" && "$(jq -r '.available' <<<"${entry}")" == "true" ]] || return 1
    tag="$(xray_agent_egress_outbound_tag "${egress_id}" "${preference}" "${network}")"
    family="$(jq -r '.family' <<<"${entry}")"
    interface_name="$(jq -r '.interface' <<<"${entry}")"
    source_address="$(jq -r '.sourceAddress' <<<"${entry}")"
    xray_agent_egress_outbound_json "${tag}" "${family}" "${preference}" "${interface_name}" "${source_address}" "${network}"
}

xray_agent_egress_effective_path_label() {
    local catalog_json ipv4_id ipv6_id
    catalog_json="$(xray_agent_egress_catalog_json)" || return 1
    ipv4_id="$(xray_agent_egress_effective_family_id ipv4)"
    ipv6_id="$(xray_agent_egress_effective_family_id ipv6)"
    jq -nr \
        --argjson catalog "${catalog_json}" \
        --arg ipv4 "${ipv4_id}" \
        --arg ipv6 "${ipv6_id}" '
          def label($id):
            ([ $catalog.egresses[] | select(.id == $id) ][0] // null) as $e
            | if $e == null then "不可用" else ($e.provider + "/" + $e.interface) end;
          "IPv4=" + label($ipv4) + "，IPv6=" + label($ipv6)
        '
}

xray_agent_egress_happy_eyeballs_json() {
    local preference="$1"
    local prioritize_ipv6=false
    [[ "${preference}" == "ipv6" ]] && prioritize_ipv6=true
    jq -nc \
        --argjson prioritizeIPv6 "${prioritize_ipv6}" \
        '{
          tryDelayMs:250,
          prioritizeIPv6:$prioritizeIPv6,
          interleave:1,
          maxConcurrentTry:4
        }'
}

xray_agent_egress_freedom_settings_json() {
    local family="$1"
    local preference="${2:-ipv4}"
    local network="${3:-tcp}"
    local settings_json
    case "${family}" in
        ipv4)
            jq -nc '{domainStrategy:"ForceIPv4"}'
            ;;
        ipv6)
            jq -nc '{domainStrategy:"ForceIPv6"}'
            ;;
        auto)
            settings_json='{"domainStrategy":"AsIs"}'
            if [[ "${network}" == udp ]]; then
                if [[ "${preference}" == ipv6 ]]; then
                    settings_json='{"domainStrategy":"ForceIPv6v4"}'
                else
                    settings_json='{"domainStrategy":"ForceIPv4v6"}'
                fi
            fi
            if declare -F xray_agent_xray_supports_freedom_final_rules >/dev/null 2>&1 &&
                xray_agent_xray_supports_freedom_final_rules; then
                jq -nc --argjson settings "${settings_json}" '$settings + {finalRules:[{action:"allow"}]}'
            else
                printf '%s\n' "${settings_json}"
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

xray_agent_egress_outbound_json() {
    local tag="$1"
    local family="$2"
    local preference="${3:-ipv4}"
    local interface_name="${4:-}"
    local source_address="${5:-}"
    local network="${6:-tcp}"
    local settings_json sockopt_json outbound_json happy_eyeballs_json

    case "${preference}" in
        ipv4 | ipv6) ;;
        *) return 1 ;;
    esac

    if [[ "${family}" == "auto" ]]; then
        declare -F xray_agent_xray_supports_safe_happy_eyeballs >/dev/null 2>&1 || return 1
        xray_agent_xray_supports_safe_happy_eyeballs || return 1
    fi

    settings_json="$(xray_agent_egress_freedom_settings_json "${family}" "${preference}" "${network}")" || return 1
    sockopt_json='{}'
    if [[ "${family}" == "auto" && "${network}" == tcp ]]; then
        happy_eyeballs_json="$(xray_agent_egress_happy_eyeballs_json "${preference}")" || return 1
        sockopt_json="$(jq -nc --argjson happyEyeballs "${happy_eyeballs_json}" '{domainStrategy:"UseIP",happyEyeballs:$happyEyeballs}')" || return 1
    fi
    if [[ -n "${interface_name}" ]]; then
        sockopt_json="$(jq -nc --argjson sockopt "${sockopt_json}" --arg interface "${interface_name}" '$sockopt + {interface:$interface}')" || return 1
    fi

    outbound_json="$(jq -nc \
        --arg tag "${tag}" \
        --argjson settings "${settings_json}" \
        '{protocol:"freedom",tag:$tag,settings:$settings}')" || return 1
    if [[ "$(jq -r 'length' <<<"${sockopt_json}")" -gt 0 ]]; then
        outbound_json="$(jq -nc --argjson outbound "${outbound_json}" --argjson sockopt "${sockopt_json}" '$outbound + {streamSettings:{sockopt:$sockopt}}')" || return 1
    fi
    if [[ -n "${source_address}" ]]; then
        outbound_json="$(jq -nc --argjson outbound "${outbound_json}" --arg sendThrough "${source_address}" '$outbound + {sendThrough:$sendThrough}')" || return 1
    fi
    printf '%s\n' "${outbound_json}"
}

xray_agent_egress_blackhole_outbound_json() {
    local tag="${1:-blackhole-out}"
    jq -nc --arg tag "${tag}" '{protocol:"blackhole",tag:$tag}'
}
