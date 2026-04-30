#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_unique_nonempty_lines() {
    awk 'NF && !seen[$0]++'
}

xray_agent_csv_from_lines() {
    xray_agent_unique_nonempty_lines | paste -sd, -
}

xray_agent_csv_to_lines() {
    printf '%s\n' "$1" | tr ',' '\n' | sed '/^$/d'
}

xray_agent_csv_first() {
    xray_agent_csv_to_lines "$1" | head -1
}

xray_agent_csv_count() {
    xray_agent_csv_to_lines "$1" | awk 'END {print NR + 0}'
}

xray_agent_truthy_from_value() {
    [[ -n "$1" ]] && printf 'true\n' || printf 'false\n'
}

xray_agent_detect_system() {
    local os_id os_like os_version issue_text
    os_id=
    os_like=
    os_version=

    if [[ -r /etc/os-release ]]; then
        os_id="$(awk -F= '$1 == "ID" {gsub(/"/, "", $2); print tolower($2); exit}' /etc/os-release)"
        os_like="$(awk -F= '$1 == "ID_LIKE" {gsub(/"/, "", $2); print tolower($2); exit}' /etc/os-release)"
        os_version="$(awk -F= '$1 == "VERSION_ID" {gsub(/"/, "", $2); print $2; exit}' /etc/os-release)"
    fi

    if [[ -z "${os_id}" ]]; then
        issue_text="$(cat /etc/issue /proc/version 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        case "${issue_text}" in
            *debian*) os_id=debian ;;
            *ubuntu*) os_id=ubuntu ;;
            *centos* | *red\ hat* | *rhel* | *rocky* | *alma*) os_id=centos ;;
        esac
    fi

    osID="${os_id}"
    osVersionID="${os_version}"
    case " ${os_id} ${os_like} " in
        *" ubuntu "*)
            release="ubuntu"
            installType='apt -y install'
            upgrade="apt update"
            updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
            removeType='apt -y autoremove'
            case "${os_version}" in
                16.*) release= ;;
            esac
            ;;
        *" debian "*)
            release="debian"
            installType='apt -y install'
            upgrade="apt update"
            updateReleaseInfoChange='apt-get --allow-releaseinfo-change update'
            removeType='apt -y autoremove'
            ;;
        *" centos "* | *" rhel "* | *" fedora "* | *" rocky "* | *" almalinux "*)
            mkdir -p /etc/yum.repos.d
            release="centos"
            installType='yum -y install'
            removeType='yum -y remove'
            upgrade="yum update -y --skip-broken"
            if [[ -f "/etc/centos-release" ]] && command -v rpm >/dev/null 2>&1; then
                centosVersion=$(rpm -q centos-release | awk -F "[-]" '{print $3}' | awk -F "[.]" '{print $1}')
                if [[ -z "${centosVersion}" ]] && grep </etc/centos-release -q -i "release 8"; then
                    centosVersion=8
                fi
            fi
            ;;
        *)
            release=
            ;;
    esac
}

xray_agent_default_interface_for_family() {
    local family="$1"
    local probe_target route_interface
    command -v ip >/dev/null 2>&1 || return 0
    if [[ "${family}" == "4" ]]; then
        probe_target="1.1.1.1"
    else
        probe_target="2606:4700:4700::1111"
    fi
    route_interface="$(ip -"${family}" route get "${probe_target}" 2>/dev/null | awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i == "dev") {
                    print $(i + 1)
                    exit
                }
            }
        }
    ')"
    if [[ -n "${route_interface}" ]]; then
        printf '%s\n' "${route_interface}"
        return 0
    fi
    ip -"${family}" route show default 2>/dev/null | awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i == "dev") {
                    print $(i + 1)
                    exit
                }
            }
        }
    '
}

xray_agent_bool_from_match() {
    [[ "$1" == "$2" && -n "$1" ]] && printf 'true\n' || printf 'false\n'
}

xray_agent_loopback_address_for_family() {
    local family="$1"
    command -v ip >/dev/null 2>&1 || return 0
    ip -o -"${family}" addr show dev lo 2>/dev/null |
        awk '{split($4, addr, "/"); print addr[1]}' |
        awk -v family="${family}" '
            family == "4" && $0 == "127.0.0.1" {print; exit}
            family == "6" && $0 == "::1" {print; exit}
        '
}

xray_agent_interface_addresses() {
    local family="$1"
    local interface_name="$2"

    command -v ip >/dev/null 2>&1 || return 0
    ip -o -"${family}" addr show dev "${interface_name}" scope global 2>/dev/null |
        awk '{split($4, addr, "/"); print addr[1]}'
}

xray_agent_parse_public_ipv4() {
    awk '
        $0 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {
            split($0, octet, ".")
            if (octet[1] <= 255 && octet[2] <= 255 && octet[3] <= 255 && octet[4] <= 255) print
        }
    '
}

xray_agent_parse_public_ipv6() {
    awk 'index($0, ":") > 0 && $0 !~ /^[[:space:]]*$/ {print}'
}

xray_agent_curl_public_ip() {
    local family="$1"
    local url="$2"
    local response
    response="$(curl -fsS --connect-timeout 3 --max-time 5 -"${family}" "${url}" 2>/dev/null || true)"
    if [[ "${url}" == *cdn-cgi/trace* ]]; then
        printf '%s\n' "${response}" | awk -F= '$1 == "ip" {print $2; exit}'
    else
        printf '%s\n' "${response}" | head -1 | tr -d '\r'
    fi
}

xray_agent_public_ips_for_family() {
    local family="$1"
    local parser

    if [[ "${family}" == "4" ]]; then
        parser=xray_agent_parse_public_ipv4
    else
        parser=xray_agent_parse_public_ipv6
    fi

    command -v curl >/dev/null 2>&1 || return 0
    {
        xray_agent_curl_public_ip "${family}" "https://www.cloudflare.com/cdn-cgi/trace"
        xray_agent_curl_public_ip "${family}" "https://api64.ipify.org"
        xray_agent_curl_public_ip "${family}" "https://ifconfig.co/ip"
    } | "${parser}" | xray_agent_unique_nonempty_lines
}

xray_agent_warp_interface_candidates() {
    command -v ip >/dev/null 2>&1 || return 0
    ip -o link show 2>/dev/null |
        awk -F': ' '{split($2, name, "@"); print name[1]}' |
        awk '$0 == "WARP" || $0 == "wgcf" || $0 == "warp" || $0 ~ /^warp[0-9]+$/'
}

xray_agent_detect_warp_interface() {
    local candidate ipv4_list ipv6_list
    while IFS= read -r candidate; do
        [[ -n "${candidate}" ]] || continue
        ipv4_list="$(xray_agent_interface_addresses 4 "${candidate}" | xray_agent_csv_from_lines)"
        ipv6_list="$(xray_agent_interface_addresses 6 "${candidate}" | xray_agent_csv_from_lines)"
        if [[ -n "${ipv4_list}${ipv6_list}" ]]; then
            warpInterface="${candidate}"
            warpIPv4CSV="${ipv4_list}"
            warpIPv6CSV="${ipv6_list}"
            return 0
        fi
    done < <(xray_agent_warp_interface_candidates)

    warpInterface=
    warpIPv4CSV=
    warpIPv6CSV=
    return 1
}

xray_agent_detect_warp_route_mode() {
    warpDefaultIPv4="false"
    warpDefaultIPv6="false"
    warpMode="none"

    [[ -n "${warpInterface}" ]] || return 0

    warpDefaultIPv4="$(xray_agent_bool_from_match "${defaultIPv4Interface}" "${warpInterface}")"
    warpDefaultIPv6="$(xray_agent_bool_from_match "${defaultIPv6Interface}" "${warpInterface}")"

    if [[ "${warpDefaultIPv4}" == "true" && "${warpDefaultIPv6}" == "true" ]]; then
        warpMode="default_dual"
    elif [[ "${warpDefaultIPv4}" == "true" ]]; then
        warpMode="default_ipv4"
    elif [[ "${warpDefaultIPv6}" == "true" ]]; then
        warpMode="default_ipv6"
    else
        warpMode="dedicated"
    fi
}

xray_agent_warp_mode_label() {
    case "${warpMode:-none}" in
        default_dual) printf 'IPv4/IPv6默认路由已走WARP\n' ;;
        default_ipv4) printf 'IPv4默认路由已走WARP，IPv6未接管\n' ;;
        default_ipv6) printf 'IPv6默认路由已走WARP，IPv4未接管\n' ;;
        dedicated) printf '专用接口，默认路由未走WARP\n' ;;
        *) printf '未检测到可用WARP接口\n' ;;
    esac
}

xray_agent_route_mode_label() {
    if [[ "${routeIPv4}" == "true" && "${routeIPv6}" == "true" ]]; then
        printf 'IPv4/IPv6 双栈\n'
    elif [[ "${routeIPv4}" == "true" ]]; then
        printf 'IPv4-only\n'
    elif [[ "${routeIPv6}" == "true" ]]; then
        printf 'IPv6-only\n'
    else
        printf '无可用默认路由\n'
    fi
}

xray_agent_internal_loopback_host() {
    xray_agent_detect_network_capabilities
    if [[ "${routeIPv4}" != "true" && "${loopbackIPv6}" == "true" ]]; then
        printf '::1\n'
    elif [[ "${loopbackIPv4}" == "true" ]]; then
        printf '127.0.0.1\n'
    elif [[ "${loopbackIPv6}" == "true" ]]; then
        printf '::1\n'
    else
        printf '127.0.0.1\n'
    fi
}

xray_agent_internal_loopback_authority() {
    local host
    host="$(xray_agent_internal_loopback_host)"
    if [[ "${host}" == *:* ]]; then
        printf '[%s]\n' "${host}"
    else
        printf '%s\n' "${host}"
    fi
}

xray_agent_loopback_endpoint() {
    local port="$1"
    printf '%s:%s\n' "$(xray_agent_internal_loopback_authority)" "${port}"
}

xray_agent_public_listen_address() {
    xray_agent_detect_network_capabilities
    if [[ "${routeIPv6}" == "true" ]]; then
        printf '::\n'
    else
        printf '0.0.0.0\n'
    fi
}

xray_agent_nginx_stream_listen_directives() {
    local port="$1"
    xray_agent_detect_network_capabilities
    if [[ "${routeIPv4}" == "true" || "${routeIPv6}" != "true" ]]; then
        printf '        listen %s;\n' "${port}"
    fi
    if [[ "${routeIPv6}" == "true" ]]; then
        printf '        listen [::]:%s;\n' "${port}"
    fi
}

xray_agent_adguard_nameserver() {
    xray_agent_detect_network_capabilities
    if [[ "${routeIPv4}" != "true" && "${loopbackIPv6}" == "true" ]]; then
        printf '::1\n'
    elif [[ "${loopbackIPv4}" == "true" ]]; then
        printf '127.0.0.1\n'
    elif [[ "${loopbackIPv6}" == "true" ]]; then
        printf '::1\n'
    else
        printf '127.0.0.1\n'
    fi
}

xray_agent_fallback_public_dns() {
    xray_agent_detect_network_capabilities
    if [[ "${routeIPv4}" != "true" && "${routeIPv6}" == "true" ]]; then
        printf '2606:4700:4700::1111\n'
    else
        printf '8.8.8.8\n'
    fi
}

xray_agent_warp_domain_strategy() {
    xray_agent_detect_network_capabilities
    if [[ "${warpHasIPv4}" == "true" && "${warpHasIPv6}" != "true" ]]; then
        printf 'UseIPv4\n'
    elif [[ "${warpHasIPv6}" == "true" && "${warpHasIPv4}" != "true" ]]; then
        printf 'UseIPv6\n'
    else
        printf 'UseIP\n'
    fi
}

xray_agent_export_xray_network_template_vars() {
    export XRAY_PUBLIC_LISTEN_ADDRESS
    export XRAY_INTERNAL_LISTEN_ADDRESS
    export XRAY_INTERNAL_TARGET_ADDRESS
    XRAY_PUBLIC_LISTEN_ADDRESS="$(xray_agent_public_listen_address)"
    XRAY_INTERNAL_LISTEN_ADDRESS="$(xray_agent_internal_loopback_host)"
    XRAY_INTERNAL_TARGET_ADDRESS="${XRAY_INTERNAL_LISTEN_ADDRESS}"
}

xray_agent_public_ip_total_count() {
    xray_agent_detect_network_capabilities
    printf '%s\n' "$(( $(xray_agent_csv_count "${publicIPv4CSV}") + $(xray_agent_csv_count "${publicIPv6CSV}") ))"
}

xray_agent_detect_network_capabilities() {
    local refresh="${1:-}"
    if [[ "${networkDetected:-false}" == "true" && "${refresh}" != "--refresh" ]]; then
        return 0
    fi

    defaultIPv4Interface="$(xray_agent_default_interface_for_family 4 | head -1)"
    defaultIPv6Interface="$(xray_agent_default_interface_for_family 6 | head -1)"
    publicIPv4CSV="$(xray_agent_public_ips_for_family 4 | xray_agent_csv_from_lines)"
    publicIPv6CSV="$(xray_agent_public_ips_for_family 6 | xray_agent_csv_from_lines)"
    loopbackIPv4Address="$(xray_agent_loopback_address_for_family 4 | head -1)"
    loopbackIPv6Address="$(xray_agent_loopback_address_for_family 6 | head -1)"

    routeIPv4="$(xray_agent_truthy_from_value "${defaultIPv4Interface}")"
    routeIPv6="$(xray_agent_truthy_from_value "${defaultIPv6Interface}")"
    publicIPv4="$(xray_agent_truthy_from_value "${publicIPv4CSV}")"
    publicIPv6="$(xray_agent_truthy_from_value "${publicIPv6CSV}")"
    loopbackIPv4="$(xray_agent_truthy_from_value "${loopbackIPv4Address}")"
    loopbackIPv6="$(xray_agent_truthy_from_value "${loopbackIPv6Address}")"
    hasIPv4="${routeIPv4}"
    hasIPv6="${routeIPv6}"
    xray_agent_detect_warp_interface || true
    xray_agent_detect_warp_route_mode
    hasWarp="$(xray_agent_truthy_from_value "${warpInterface}")"
    warpHasIPv4="$(xray_agent_truthy_from_value "${warpIPv4CSV}")"
    warpHasIPv6="$(xray_agent_truthy_from_value "${warpIPv6CSV}")"

    if command -v jq >/dev/null 2>&1; then
        networkJSON="$(jq -nc \
            --arg hasIPv4 "${hasIPv4}" \
            --arg hasIPv6 "${hasIPv6}" \
            --arg routeIPv4 "${routeIPv4}" \
            --arg routeIPv6 "${routeIPv6}" \
            --arg publicIPv4 "${publicIPv4}" \
            --arg publicIPv6 "${publicIPv6}" \
            --arg loopbackIPv4 "${loopbackIPv4}" \
            --arg loopbackIPv6 "${loopbackIPv6}" \
            --arg defaultIPv4Interface "${defaultIPv4Interface}" \
            --arg defaultIPv6Interface "${defaultIPv6Interface}" \
            --arg loopbackIPv4Address "${loopbackIPv4Address}" \
            --arg loopbackIPv6Address "${loopbackIPv6Address}" \
            --arg publicIPv4Csv "${publicIPv4CSV}" \
            --arg publicIPv6Csv "${publicIPv6CSV}" \
            --arg warpInterface "${warpInterface}" \
            --arg warpIPv4Csv "${warpIPv4CSV}" \
            --arg warpIPv6Csv "${warpIPv6CSV}" \
            --arg warpDefaultIPv4 "${warpDefaultIPv4}" \
            --arg warpDefaultIPv6 "${warpDefaultIPv6}" \
            --arg warpMode "${warpMode}" \
            '{
              hasIPv4: ($hasIPv4 == "true"),
              hasIPv6: ($hasIPv6 == "true"),
              routeIPv4: ($routeIPv4 == "true"),
              routeIPv6: ($routeIPv6 == "true"),
              publicIPv4Available: ($publicIPv4 == "true"),
              publicIPv6Available: ($publicIPv6 == "true"),
              loopbackIPv4: ($loopbackIPv4 == "true"),
              loopbackIPv6: ($loopbackIPv6 == "true"),
              defaultIPv4Interface: $defaultIPv4Interface,
              defaultIPv6Interface: $defaultIPv6Interface,
              loopbackIPv4Address: $loopbackIPv4Address,
              loopbackIPv6Address: $loopbackIPv6Address,
              publicIPv4: ($publicIPv4Csv | split(",") | map(select(length > 0))),
              publicIPv6: ($publicIPv6Csv | split(",") | map(select(length > 0))),
              warp: {
                interface: $warpInterface,
                ipv4: ($warpIPv4Csv | split(",") | map(select(length > 0))),
                ipv6: ($warpIPv6Csv | split(",") | map(select(length > 0))),
                defaultIPv4: ($warpDefaultIPv4 == "true"),
                defaultIPv6: ($warpDefaultIPv6 == "true"),
                mode: $warpMode
              }
            }')"
    else
        networkJSON=
    fi
    networkDetected=true
}

xray_agent_public_ip_candidates() {
    xray_agent_detect_network_capabilities
    xray_agent_csv_to_lines "${publicIPv4CSV}"
    xray_agent_csv_to_lines "${publicIPv6CSV}"
}

xray_agent_reality_public_address_candidates() {
    xray_agent_detect_network_capabilities
    if [[ "${warpDefaultIPv4}" != "true" ]]; then
        xray_agent_csv_to_lines "${publicIPv4CSV}"
    fi
    if [[ "${warpDefaultIPv6}" != "true" ]]; then
        xray_agent_csv_to_lines "${publicIPv6CSV}"
    fi
}

xray_agent_get_public_ip() {
    xray_agent_detect_network_capabilities
    if [[ -n "${publicIPv4CSV}" ]]; then
        xray_agent_csv_first "${publicIPv4CSV}"
    else
        xray_agent_csv_first "${publicIPv6CSV}"
    fi
}

xray_agent_select_public_ip_for_reality() {
    local candidates count selected_index selected_ip index
    if [[ -n "${selectedRealityPublicIP:-}" ]]; then
        printf '%s\n' "${selectedRealityPublicIP}"
        return 0
    fi

    candidates="$(xray_agent_reality_public_address_candidates | xray_agent_unique_nonempty_lines)"
    count="$(printf '%s\n' "${candidates}" | sed '/^$/d' | awk 'END {print NR + 0}')"
    if [[ "${count}" == "0" ]]; then
        if [[ "${warpDefaultIPv4}" == "true" || "${warpDefaultIPv6}" == "true" ]]; then
            if [[ -t 0 ]]; then
                echoContent yellow " ---> 检测到默认路由已走 WARP，自动公网 IP 可能是 WARP 出口。" >&2
                read -r -p "请输入服务器真实入站公网 IP 或域名:" selected_ip
                if [[ -n "${selected_ip}" ]]; then
                    selectedRealityPublicIP="${selected_ip}"
                    printf '%s\n' "${selectedRealityPublicIP}"
                    return 0
                fi
            fi
            echoContent red " ---> 默认路由已走 WARP，无法可靠自动判断服务器入站公网地址，Reality 分享地址未生成。" >&2
            return 1
        fi
        echoContent red " ---> 未检测到公网 IPv4/IPv6，Reality 分享地址无法生成。请检查公网网络或手动配置域名解析。" >&2
        return 1
    elif [[ "${count}" == "1" ]]; then
        selectedRealityPublicIP="$(printf '%s\n' "${candidates}" | sed '/^$/d' | head -1)"
        printf '%s\n' "${selectedRealityPublicIP}"
        return 0
    fi

    if [[ ! -t 0 ]]; then
        selectedRealityPublicIP="$(printf '%s\n' "${candidates}" | sed '/^$/d' | head -1)"
        echoContent yellow " ---> 检测到多个公网 IP，非交互环境默认使用 ${selectedRealityPublicIP}" >&2
        printf '%s\n' "${selectedRealityPublicIP}"
        return 0
    fi

    echoContent yellow "检测到多个公网 IP，请选择 Reality 分享地址:" >&2
    index=0
    while IFS= read -r selected_ip; do
        [[ -n "${selected_ip}" ]] || continue
        index=$((index + 1))
        printf '%s.%s\n' "${index}" "${selected_ip}" >&2
    done <<<"${candidates}"
    read -r -p "请输入编号[默认1]:" selected_index
    selected_index="${selected_index:-1}"
    if ! [[ "${selected_index}" =~ ^[0-9]+$ ]] || [[ "${selected_index}" -lt 1 || "${selected_index}" -gt "${count}" ]]; then
        selected_index=1
    fi
    selectedRealityPublicIP="$(printf '%s\n' "${candidates}" | sed '/^$/d' | awk -v target="${selected_index}" 'NR == target {print; exit}')"
    printf '%s\n' "${selectedRealityPublicIP}"
}

xray_agent_network_summary() {
    xray_agent_detect_network_capabilities --refresh
    echoContent skyBlue "-------------------------网络探测-----------------------------"
    echoContent yellow "出站栈: $(xray_agent_route_mode_label)"
    if [[ -n "${publicIPv4CSV}" ]]; then
        echoContent green "IPv4公网: ${publicIPv4CSV}"
    else
        echoContent yellow "IPv4公网: 未检测到"
    fi
    if [[ -n "${publicIPv6CSV}" ]]; then
        echoContent green "IPv6公网: ${publicIPv6CSV}"
    else
        echoContent yellow "IPv6公网: 未检测到"
    fi
    if [[ -n "${defaultIPv4Interface}${defaultIPv6Interface}" ]]; then
        echoContent yellow "默认接口: IPv4=${defaultIPv4Interface:-无} IPv6=${defaultIPv6Interface:-无}"
    fi
    echoContent yellow "本机回环: IPv4=${loopbackIPv4Address:-无} IPv6=${loopbackIPv6Address:-无}"
    if [[ -n "${warpInterface}" ]]; then
        echoContent green "WARP接口: ${warpInterface} IPv4=${warpIPv4CSV:-无} IPv6=${warpIPv6CSV:-无}"
        echoContent yellow "WARP模式: $(xray_agent_warp_mode_label)"
    else
        echoContent yellow "WARP接口: 未检测到可用接口"
    fi
}

xray_agent_has_ipv6() {
    xray_agent_detect_network_capabilities
    [[ "${routeIPv6}" == "true" ]]
}

xray_agent_detect_usable_warp_interface() {
    xray_agent_detect_network_capabilities
    [[ -n "${warpInterface}" ]] || return 1
    printf '%s\n' "${warpInterface}"
}
