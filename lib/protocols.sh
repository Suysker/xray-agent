#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_protocol_template_dir() {
    echo "${XRAY_AGENT_PROJECT_ROOT}/templates/xray"
}

xray_agent_share_template_dir() {
    echo "${XRAY_AGENT_PROJECT_ROOT}/templates/share"
}

xray_agent_reset_protocol_profile() {
    XRAY_AGENT_PROTOCOL_NAME=
    XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE=
    XRAY_AGENT_PROTOCOL_SHARE_TEMPLATE=
    XRAY_AGENT_PROTOCOL_PROTOCOL=
    XRAY_AGENT_PROTOCOL_TRANSPORT=
    XRAY_AGENT_PROTOCOL_SECURITY=
    XRAY_AGENT_PROTOCOL_FLOW=
    XRAY_AGENT_PROTOCOL_ADDRESS_SOURCE=
    XRAY_AGENT_PROTOCOL_PORT_SOURCE=
    XRAY_AGENT_PROTOCOL_SNI_SOURCE=
    XRAY_AGENT_PROTOCOL_PATH_SOURCE=
    XRAY_AGENT_PROTOCOL_MODE=
    XRAY_AGENT_PROTOCOL_ALPN=
    XRAY_AGENT_PROTOCOL_FP=
    XRAY_AGENT_PROTOCOL_CLIENT_KIND=
    XRAY_AGENT_PROTOCOL_CONFIG_FILE=
}

xray_agent_load_protocol_profile() {
    local profile_path="${XRAY_AGENT_PROFILE_DIR}/protocol/$1.profile"
    local key value
    if [[ ! -r "${profile_path}" ]]; then
        return 1
    fi

    xray_agent_reset_protocol_profile
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        case "${key}" in
            name) XRAY_AGENT_PROTOCOL_NAME="${value}" ;;
            inbound_template) XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE="${value}" ;;
            share_template) XRAY_AGENT_PROTOCOL_SHARE_TEMPLATE="${value}" ;;
            protocol) XRAY_AGENT_PROTOCOL_PROTOCOL="${value}" ;;
            transport) XRAY_AGENT_PROTOCOL_TRANSPORT="${value}" ;;
            security) XRAY_AGENT_PROTOCOL_SECURITY="${value}" ;;
            flow) XRAY_AGENT_PROTOCOL_FLOW="${value}" ;;
            address_source) XRAY_AGENT_PROTOCOL_ADDRESS_SOURCE="${value}" ;;
            port_source) XRAY_AGENT_PROTOCOL_PORT_SOURCE="${value}" ;;
            sni_source) XRAY_AGENT_PROTOCOL_SNI_SOURCE="${value}" ;;
            path_source) XRAY_AGENT_PROTOCOL_PATH_SOURCE="${value}" ;;
            mode) XRAY_AGENT_PROTOCOL_MODE="${value}" ;;
            alpn) XRAY_AGENT_PROTOCOL_ALPN="${value}" ;;
            fp) XRAY_AGENT_PROTOCOL_FP="${value}" ;;
            client_kind) XRAY_AGENT_PROTOCOL_CLIENT_KIND="${value}" ;;
            config_file) XRAY_AGENT_PROTOCOL_CONFIG_FILE="${value}" ;;
        esac
    done <"${profile_path}"
}

xray_agent_generate_clients_json() {
    local protocol="$1"
    local uuid_csv="$2"
    jq -nc --arg protocol "${protocol}" --arg uuidCsv "${uuid_csv}" '
      ($uuidCsv | split(",") | map(select(length > 0))) as $uuids
      | $uuids
      | map(
          if $protocol == "VLESS_TCP" then
            {id: ., flow: "xtls-rprx-vision"}
          elif $protocol == "VLESS_XHTTP" or $protocol == "VLESS_WS" then
            {id: .}
          elif $protocol == "VMESS_WS" then
            {id: ., alterId: 0}
          elif $protocol == "HYSTERIA2" then
            {auth: ., level: 0, email: .}
          else
            {id: .}
          end
        )'
}

generate_clients() {
    xray_agent_generate_clients_json "$1" "$2"
}

xray_agent_generate_vless_decryption() {
    local vlessenc_output
    if ! xray_agent_xray_supports_command vlessenc; then
        return 1
    fi
    vlessenc_output="$("${ctlPath}" vlessenc 2>/dev/null)" || return 1
    awk '
        /Authentication: ML-KEM-768/ {pq = 1; next}
        pq && /"decryption"/ {
            split($0, part, "\"")
            print part[4]
            exit
        }
    ' <<<"${vlessenc_output}"
}

xray_agent_vless_decryption_key_material() {
    local decryption="$1"
    printf '%s\n' "${decryption}" | awk -F '.' '{print $NF}'
}

xray_agent_vless_encryption_from_decryption() {
    local decryption="$1"
    local key_material generated_output client_key
    [[ -n "${decryption}" && "${decryption}" != "none" ]] || {
        printf 'none\n'
        return 0
    }
    key_material="$(xray_agent_vless_decryption_key_material "${decryption}")"
    case "${#key_material}" in
        43)
            generated_output="$("${ctlPath}" x25519 -i "${key_material}" 2>/dev/null)" || return 1
            client_key="$(xray_agent_parse_x25519_field "${generated_output}" "Public key")"
            ;;
        86)
            generated_output="$("${ctlPath}" mlkem768 -i "${key_material}" 2>/dev/null)" || return 1
            client_key="$(xray_agent_parse_x25519_field "${generated_output}" "Client")"
            ;;
        *)
            return 1
            ;;
    esac
    [[ -n "${client_key}" ]] || return 1
    printf 'mlkem768x25519plus.native.0rtt.%s\n' "${client_key}"
}

xray_agent_prepare_vless_encryption() {
    if [[ -n "${VLESSDecryption:-}" && "${VLESSDecryption}" != "none" ]]; then
        VLESSEncryption="$(xray_agent_vless_encryption_from_decryption "${VLESSDecryption}" || true)"
        [[ -n "${VLESSEncryption}" ]] && return 0
    fi
    VLESSDecryption="$(xray_agent_generate_vless_decryption || true)"
    if [[ -n "${VLESSDecryption}" ]]; then
        VLESSEncryption="$(xray_agent_vless_encryption_from_decryption "${VLESSDecryption}" || true)"
        [[ -n "${VLESSEncryption}" ]] && return 0
    fi
    VLESSDecryption="none"
    VLESSEncryption="none"
    echoContent yellow " ---> 当前 Xray-core 不支持或无法生成 VLESS Encryption，VLESS WS/XHTTP 将使用 encryption=none。"
}

xray_agent_generate_ech_material() {
    local ech_domain="$1"
    local ech_output
    if ! xray_agent_xray_supports_tls_ech; then
        return 1
    fi
    ech_output="$("${ctlPath}" tls ech --serverName "${ech_domain}" 2>/dev/null)" || return 1
    ECHConfigList="$(awk '/^ECH config list:/ {getline; gsub(/\r/, "", $0); print; exit}' <<<"${ech_output}")"
    ECHServerKeys="$(awk '/^ECH server keys:/ {getline; gsub(/\r/, "", $0); print; exit}' <<<"${ech_output}")"
    [[ -n "${ECHConfigList}" && -n "${ECHServerKeys}" ]]
}

xray_agent_prepare_tls_ech() {
    local ech_domain="${TLSDomain:-${domain:-}}"
    if [[ -n "${ECHServerKeys:-}" ]]; then
        ECHConfigList="$(xray_agent_tls_ech_config_list_value || true)"
        return 0
    fi
    [[ -n "${ech_domain}" ]] || return 0
    if ! xray_agent_generate_ech_material "${ech_domain}"; then
        ECHServerKeys=
        ECHConfigList=
        echoContent yellow " ---> 当前 Xray-core 不支持或无法生成 TLS ECH，TLS 分享不会输出 ech。"
    fi
}

xray_agent_tls_ech_server_keys_json_entry() {
    if [[ -n "${ECHServerKeys:-}" ]]; then
        printf ',\n          "echServerKeys": %s' "$(xray_agent_json_string "${ECHServerKeys}")"
    fi
}

xray_agent_vless_decryption_for_inbound() {
    case "$1" in
        direct) printf '%s\n' "${VLESSDecryption:-none}" ;;
        *) printf 'none\n' ;;
    esac
}

xray_agent_protocol_variant() {
    local requested_variant="${1:-}"
    if [[ -n "${requested_variant}" ]]; then
        echo "${requested_variant}"
    elif [[ "${coreInstallType}" == "2" ]]; then
        echo "reality"
    else
        echo "tls"
    fi
}

xray_agent_protocol_security_value() {
    local variant
    variant="$(xray_agent_protocol_variant "${1:-}")"
    case "${XRAY_AGENT_PROTOCOL_SECURITY}" in
        auto)
            if [[ "${variant}" == "reality" ]]; then
                echo "reality"
            else
                echo "tls"
            fi
            ;;
        *)
            echo "${XRAY_AGENT_PROTOCOL_SECURITY}"
            ;;
    esac
}

xray_agent_protocol_address_value() {
    local variant
    variant="$(xray_agent_protocol_variant "${1:-}")"
    case "${XRAY_AGENT_PROTOCOL_ADDRESS_SOURCE}" in
        domain)
            echo "${domain}"
            ;;
        public_ip)
            if [[ "${variant}" == "reality" ]]; then
                xray_agent_select_public_ip_for_reality
            else
                getPublicIP
            fi
            ;;
        auto)
            if [[ "${variant}" == "reality" ]]; then
                xray_agent_select_public_ip_for_reality
            else
                echo "${domain}"
            fi
            ;;
    esac
}

xray_agent_protocol_port_value() {
    local variant
    variant="$(xray_agent_protocol_variant "${1:-}")"

    if [[ "${reuse443}" == "y" ]]; then
        echo "443"
        return 0
    fi

    case "${XRAY_AGENT_PROTOCOL_PORT_SOURCE}" in
        Port)
            echo "${Port}"
            ;;
        RealityPort)
            echo "${RealityPort}"
            ;;
        hysteria2)
            echo "443"
            ;;
        auto)
            if [[ "${variant}" == "reality" ]]; then
                echo "${RealityPort}"
            else
                echo "${Port}"
            fi
            ;;
    esac
}

xray_agent_primary_reality_server_name() {
    echo "${RealityServerNames}" | sed 's/"//g' | awk -F ',' '{print $1}'
}

xray_agent_protocol_sni_value() {
    local variant
    variant="$(xray_agent_protocol_variant "${1:-}")"
    case "${XRAY_AGENT_PROTOCOL_SNI_SOURCE}" in
        domain)
            echo "${domain}"
            ;;
        reality_server_name)
            xray_agent_primary_reality_server_name
            ;;
        auto)
            if [[ "${variant}" == "reality" ]]; then
                xray_agent_primary_reality_server_name
            else
                echo "${domain}"
            fi
            ;;
    esac
}

xray_agent_protocol_path_value() {
    case "${XRAY_AGENT_PROTOCOL_PATH_SOURCE}" in
        path)
            echo "/${path}"
            ;;
        path_ws)
            echo "/${path}ws"
            ;;
        path_vws)
            echo "/${path}vws"
            ;;
        *)
            echo ""
            ;;
    esac
}

xray_agent_tls_fallbacks_json() {
    local ws_dest vmess_ws_dest nginx_dest
    ws_dest="$(xray_agent_loopback_endpoint 31297)"
    vmess_ws_dest="$(xray_agent_loopback_endpoint 31299)"
    nginx_dest="$(xray_agent_loopback_endpoint 31300)"
    jq -nc \
        --arg wsPath "${XRAY_FALLBACK_WS_PATH}" \
        --arg vmessWsPath "${XRAY_FALLBACK_VMESS_WS_PATH}" \
        --arg wsDest "${ws_dest}" \
        --arg vmessWsDest "${vmess_ws_dest}" \
        --arg nginxDest "${nginx_dest}" \
        '[{path:$wsPath,dest:$wsDest,xver:1},{path:$vmessWsPath,dest:$vmessWsDest,xver:1},{dest:$nginxDest,xver:0}]'
}

xray_agent_reality_fallbacks_json() {
    local xhttp_dest
    xhttp_dest="$(xray_agent_loopback_endpoint 31305)"
    jq -nc --arg xhttpDest "${xhttp_dest}" '[{dest:$xhttpDest,xver:0}]'
}

xray_agent_csv_json_array() {
    local csv_value="$1"
    csv_value="${csv_value//\"/}"
    jq -nc --arg csv "${csv_value}" '
      $csv
      | split(",")
      | map(gsub("^\\s+|\\s+$"; ""))
      | map(select(length > 0))'
}

xray_agent_short_ids_json_array() {
    local csv_value="$1"
    csv_value="${csv_value//\"/}"
    jq -nc --arg csv "${csv_value}" '
      ($csv
      | split(",")
      | map(gsub("^\\s+|\\s+$"; ""))
      | map(select(length > 0))) as $ids
      | if $ids == [] then [""] else $ids end'
}

xray_agent_generate_mldsa65_material() {
    local mldsa_output
    if ! xray_agent_xray_supports_command mldsa65; then
        return 1
    fi
    mldsa_output="$("${ctlPath}" mldsa65 2>/dev/null)" || return 1
    RealityMldsa65Seed="$(xray_agent_parse_x25519_field "${mldsa_output}" "Seed")"
    RealityMldsa65Verify="$(xray_agent_parse_x25519_field "${mldsa_output}" "Verify")"
    [[ -n "${RealityMldsa65Seed}" && -n "${RealityMldsa65Verify}" ]]
}

xray_agent_reality_target_certificate_length() {
    local target="$1"
    local tls_ping_output
    [[ -n "${target}" && -x "${ctlPath:-}" ]] || return 1
    tls_ping_output="$("${ctlPath}" tls ping "${target}" 2>/dev/null)" || return 1
    awk -F '[:(]' '/Certificate chain.*total length/ {gsub(/[^0-9]/, "", $2); print $2; exit}' <<<"${tls_ping_output}"
}

xray_agent_reality_target_allows_mldsa65() {
    local target="$1"
    local cert_length
    cert_length="$(xray_agent_reality_target_certificate_length "${target}" || true)"
    [[ -n "${cert_length}" ]] || return 1
    [[ "${cert_length}" -le 3500 ]]
}

xray_agent_prepare_reality_mldsa65() {
    if [[ -n "${RealityMldsa65Seed:-}" ]]; then
        RealityMldsa65Verify="$(xray_agent_reality_mldsa65_verify_value || true)"
        return 0
    fi
    if ! xray_agent_reality_target_allows_mldsa65 "${RealityDestDomain}"; then
        RealityMldsa65Seed=
        RealityMldsa65Verify=
        echoContent yellow " ---> Reality 目标 TLS 预检不适合启用 ML-DSA-65，已跳过 pqv。建议更换证书链更短且行为稳定的 target。"
        return 0
    fi
    if ! xray_agent_generate_mldsa65_material; then
        RealityMldsa65Seed=
        RealityMldsa65Verify=
        echoContent yellow " ---> 当前 Xray-core 不支持或无法生成 ML-DSA-65，Reality 分享不会输出 pqv。"
    fi
}

xray_agent_reality_mldsa65_seed_json_entry() {
    if [[ -n "${RealityMldsa65Seed:-}" ]]; then
        printf ',\n          "mldsa65Seed": %s' "$(xray_agent_json_string "${RealityMldsa65Seed}")"
    fi
}

xray_agent_render_vless_tcp_tls_inbound() {
    local clients_json="$1"
    local accept_proxy_protocol="$2"
    local sniffing_json="$3"
    xray_agent_load_protocol_profile "vless_tcp_tls"
    xray_agent_export_xray_network_template_vars
    export XRAY_CLIENTS_JSON="${clients_json}"
    export XRAY_FALLBACK_WS_PATH="/${path}ws"
    export XRAY_FALLBACK_VMESS_WS_PATH="/${path}vws"
    export XRAY_FALLBACKS_JSON
    export XRAY_SOCKOPT_JSON
    export XRAY_SNIFFING_JSON="${sniffing_json}"
    export XRAY_INBOUND_PORT="${Port}"
    export XRAY_INBOUND_TAG="VLESSTCP"
    export XRAY_ACCEPT_PROXY_PROTOCOL="${accept_proxy_protocol}"
    export XRAY_TLS_DOMAIN="${TLSDomain}"
    export XRAY_VLESS_DECRYPTION
    export XRAY_TLS_ECH_SERVER_KEYS_JSON_ENTRY
    XRAY_FALLBACKS_JSON="$(xray_agent_tls_fallbacks_json)"
    XRAY_SOCKOPT_JSON="$(xray_agent_sockopt_with_proxy_protocol "${accept_proxy_protocol}")"
    XRAY_VLESS_DECRYPTION="$(xray_agent_vless_decryption_for_inbound fallback)"
    XRAY_TLS_ECH_SERVER_KEYS_JSON_ENTRY="$(xray_agent_tls_ech_server_keys_json_entry)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}

xray_agent_render_vless_ws_legacy_config() {
    xray_agent_load_protocol_profile "vless_ws_tls"
    xray_agent_export_xray_network_template_vars
    export XRAY_CLIENTS_JSON="$1"
    export XRAY_SNIFFING_JSON="$2"
    export XRAY_WS_PATH="/${path}ws"
    export XRAY_VLESS_DECRYPTION
    XRAY_VLESS_DECRYPTION="$(xray_agent_vless_decryption_for_inbound direct)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}

xray_agent_render_vmess_ws_legacy_config() {
    xray_agent_load_protocol_profile "vmess_ws_tls"
    xray_agent_export_xray_network_template_vars
    export XRAY_CLIENTS_JSON="$1"
    export XRAY_SNIFFING_JSON="$2"
    export XRAY_WS_PATH="/${path}vws"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}

xray_agent_render_vless_reality_tcp_inbound() {
    local clients_json="$1"
    local accept_proxy_protocol="$2"
    local sniffing_json="$3"
    xray_agent_load_protocol_profile "vless_reality_tcp"
    xray_agent_export_xray_network_template_vars
    export XRAY_CLIENTS_JSON="${clients_json}"
    export XRAY_FALLBACKS_JSON
    export XRAY_SOCKOPT_JSON
    export XRAY_SNIFFING_JSON="${sniffing_json}"
    export XRAY_INBOUND_PORT="${RealityPort}"
    export XRAY_INBOUND_TAG="VLESSReality"
    export XRAY_ACCEPT_PROXY_PROTOCOL="${accept_proxy_protocol}"
    export XRAY_REALITY_TARGET="${RealityDestDomain}"
    export XRAY_REALITY_SERVER_NAMES_JSON
    export XRAY_REALITY_PRIVATE_KEY="${RealityPrivateKey}"
    export XRAY_REALITY_SHORT_IDS_JSON
    export XRAY_REALITY_MLDSA65_SEED_JSON_ENTRY
    export XRAY_VLESS_DECRYPTION
    XRAY_FALLBACKS_JSON="$(xray_agent_reality_fallbacks_json)"
    XRAY_SOCKOPT_JSON="$(xray_agent_sockopt_with_proxy_protocol "${accept_proxy_protocol}")"
    XRAY_REALITY_SERVER_NAMES_JSON="$(xray_agent_csv_json_array "${RealityServerNames}")"
    XRAY_REALITY_SHORT_IDS_JSON="$(xray_agent_short_ids_json_array "${RealityShortID}")"
    XRAY_REALITY_MLDSA65_SEED_JSON_ENTRY="$(xray_agent_reality_mldsa65_seed_json_entry)"
    XRAY_VLESS_DECRYPTION="$(xray_agent_vless_decryption_for_inbound fallback)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}

xray_agent_render_vless_xhttp_inbound() {
    local clients_json="$1"
    local inbound_port="$2"
    local sniffing_json="$3"
    xray_agent_load_protocol_profile "vless_xhttp"
    xray_agent_export_xray_network_template_vars
    export XRAY_CLIENTS_JSON="${clients_json}"
    export XRAY_INBOUND_PORT="${inbound_port}"
    export XRAY_INBOUND_TAG="VLESSXHTTP"
    export XRAY_XHTTP_PATH="/${path}"
    export XRAY_SOCKOPT_JSON
    export XRAY_SNIFFING_JSON="${sniffing_json}"
    export XRAY_VLESS_DECRYPTION
    XRAY_SOCKOPT_JSON="$(xray_agent_sockopt_with_proxy_protocol "false")"
    XRAY_VLESS_DECRYPTION="$(xray_agent_vless_decryption_for_inbound direct)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}

xray_agent_hysteria2_default_masquerade_url() {
    local include_existing="${1:-true}"
    local candidate

    if declare -F xray_agent_nginx_real_site_masquerade_url >/dev/null 2>&1; then
        candidate="$(xray_agent_nginx_real_site_masquerade_url)"
        if [[ -n "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    fi

    if [[ "${include_existing}" == "true" && -n "${Hysteria2MasqueradeURL:-}" ]]; then
        printf '%s\n' "${Hysteria2MasqueradeURL}"
        return 0
    fi

    candidate="$(xray_agent_hysteria2_nginx_masquerade_url)"
    if [[ -n "${candidate}" ]]; then
        printf '%s\n' "${candidate}"
        return 0
    fi

    candidate="$(xray_agent_hysteria2_reality_masquerade_url)"
    if [[ -n "${candidate}" ]]; then
        printf '%s\n' "${candidate}"
        return 0
    fi

    if declare -F xray_agent_nginx_masquerade_context_json >/dev/null 2>&1; then
        candidate="$(xray_agent_nginx_masquerade_context_json | jq -r 'select(.source != "real-site") | .masquerade_url // empty')"
        if [[ -n "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    fi

    printf ''
}

xray_agent_hysteria2_nginx_masquerade_url() {
    local nginx_file="${nginxConfigPath:-}/alone.conf"
    [[ -f "${nginx_file}" ]] || return 0
    awk '$1 == "proxy_pass" && $2 ~ /^https?:\/\// {gsub(";","",$2); print $2; exit}' "${nginx_file}"
}

xray_agent_hysteria2_reality_masquerade_url() {
    local target="${RealityDestDomain:-}"
    target="${target//\"/}"
    [[ -n "${target}" ]] || return 0
    target="${target%%,*}"
    target="${target#https://}"
    target="${target#http://}"
    target="${target%%/*}"
    target="${target%%:*}"
    [[ -n "${target}" ]] || return 0
    printf 'https://%s/\n' "${target}"
}

xray_agent_hysteria2_domain_candidates() {
    {
        if [[ -n "${domain:-}" ]]; then
            xray_agent_cert_normalize_domain "${domain}"
        fi
        if [[ -n "${TLSDomain:-}" ]]; then
            xray_agent_cert_normalize_domain "${TLSDomain}"
        fi
        if declare -F xray_agent_cert_inventory_domains >/dev/null 2>&1; then
            xray_agent_cert_inventory_domains
        elif [[ -d "${XRAY_AGENT_TLS_DIR:-/etc/xray-agent/tls}" ]]; then
            local cert_file
            for cert_file in "${XRAY_AGENT_TLS_DIR:-/etc/xray-agent/tls}"/*.crt; do
                [[ -f "${cert_file}" ]] && basename "${cert_file}" .crt
            done
        fi
    } | sed '/^\*$/d;/^$/d' | awk '!seen[$0]++'
}

xray_agent_hysteria2_domain_valid() {
    local candidate="$1"
    [[ -n "${candidate}" ]] || return 1
    [[ "${candidate}" != *" "* && "${candidate}" != *"/"* && "${candidate}" != *":"* ]] || return 1
    [[ "${candidate}" == *.* ]] || return 1
    [[ "${candidate}" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || return 1
    [[ "${candidate}" != *..* ]] || return 1
}

xray_agent_hysteria2_cert_pair_exists() {
    local cert_domain="$1"
    [[ -f "${XRAY_AGENT_TLS_DIR:-/etc/xray-agent/tls}/${cert_domain}.crt" &&
        -f "${XRAY_AGENT_TLS_DIR:-/etc/xray-agent/tls}/${cert_domain}.key" ]]
}

xray_agent_hysteria2_domain_candidate_status() {
    local candidate="$1"
    local current_tls="${TLSDomain:-}"
    local days_left match_status

    if xray_agent_hysteria2_cert_pair_exists "${candidate}"; then
        if days_left="$(xray_agent_cert_days_left "${XRAY_AGENT_TLS_DIR:-/etc/xray-agent/tls}/${candidate}.crt" 2>/dev/null)"; then
            match_status="$(xray_agent_cert_key_match_status "${XRAY_AGENT_TLS_DIR:-/etc/xray-agent/tls}/${candidate}.crt" "${XRAY_AGENT_TLS_DIR:-/etc/xray-agent/tls}/${candidate}.key")"
            printf '证书文件完整，到期剩余=%s天，私钥=%s\n' "${days_left}" "${match_status}"
        else
            printf '证书文件完整\n'
        fi
    elif [[ -n "${current_tls}" && "${candidate}" == "${domain:-}" ]] && xray_agent_hysteria2_cert_pair_exists "${current_tls}"; then
        printf '使用当前 TLS 证书: %s\n' "${current_tls}"
    elif [[ -n "$(xray_agent_cert_acme_dir "${candidate}")" ]]; then
        printf 'acme 记录存在，可安装证书文件\n'
    else
        printf '需要申请或安装证书\n'
    fi
}

xray_agent_hysteria2_read_custom_domain() {
    local input_domain normalized_domain
    while true; do
        echoContent yellow "请输入 Hysteria2 使用的域名[必须是自己控制且可签发证书的真实域名]:"
        read -r -p "域名:" input_domain
        normalized_domain="$(xray_agent_cert_normalize_domain "${input_domain}")"
        if xray_agent_hysteria2_domain_valid "${normalized_domain}"; then
            XRAY_AGENT_HYSTERIA2_SELECTED_DOMAIN="${normalized_domain}"
            return 0
        fi
        echoContent red " ---> 域名不合法，请输入真实域名，例如 example.com"
    done
}

xray_agent_hysteria2_select_tls_domain() {
    local candidates=()
    local selected_item candidate_index normalized_input
    XRAY_AGENT_HYSTERIA2_SELECTED_DOMAIN=
    mapfile -t candidates < <(xray_agent_hysteria2_domain_candidates)

    if [[ "${#candidates[@]}" -eq 0 ]]; then
        xray_agent_hysteria2_read_custom_domain
        return $?
    fi

    echoContent skyBlue "-------------------------Hysteria2证书域名---------------------"
    echoContent yellow "请选择 Hysteria2 使用的域名。回车使用推荐项，也可以输入 0 自定义。"
    for candidate_index in "${!candidates[@]}"; do
        echoContent yellow "$((candidate_index + 1)).${candidates[$candidate_index]} ($(xray_agent_hysteria2_domain_candidate_status "${candidates[$candidate_index]}"))"
    done
    echoContent yellow "0.自定义域名"
    read -r -p "请选择[回车=1]:" selected_item
    selected_item="${selected_item:-1}"

    if [[ "${selected_item}" == "0" ]]; then
        xray_agent_hysteria2_read_custom_domain
        return $?
    fi
    if [[ "${selected_item}" =~ ^[0-9]+$ ]] && ((selected_item >= 1 && selected_item <= ${#candidates[@]})); then
        XRAY_AGENT_HYSTERIA2_SELECTED_DOMAIN="${candidates[$((selected_item - 1))]}"
        return 0
    fi

    normalized_input="$(xray_agent_cert_normalize_domain "${selected_item}")"
    if xray_agent_hysteria2_domain_valid "${normalized_input}"; then
        XRAY_AGENT_HYSTERIA2_SELECTED_DOMAIN="${normalized_input}"
        return 0
    fi

    echoContent red " ---> 选择错误"
    return 1
}

xray_agent_hysteria2_prompt_mbps() {
    local label="$1"
    local direction_hint="$2"
    local default_value="${3:-0}"
    local input_value
    while true; do
        read -r -p "${label}[Mbps，${direction_hint}，回车默认${default_value}，0=不写Brutal参数]:" input_value
        input_value="${input_value:-${default_value}}"
        if [[ "${input_value}" =~ ^[0-9]+$ ]]; then
            printf '%s\n' "${input_value}"
            return 0
        fi
        echoContent red " ---> 请输入整数 Mbps" >&2
    done
}

xray_agent_hysteria2_prepare_tls_domain() {
    local previous_domain="${domain:-}" previous_tls_domain="${TLSDomain:-}" selected_domain
    xray_agent_hysteria2_select_tls_domain || return 1
    selected_domain="${XRAY_AGENT_HYSTERIA2_SELECTED_DOMAIN}"
    [[ -n "${selected_domain:-}" ]] || xray_agent_error " ---> Hysteria2 域名不可为空"
    domain="${selected_domain}"
    if [[ "${selected_domain}" == "${previous_domain}" && -n "${previous_tls_domain}" ]]; then
        TLSDomain="${previous_tls_domain}"
    else
        TLSDomain="${selected_domain}"
    fi

    if [[ ! -f "${XRAY_AGENT_TLS_DIR}/${TLSDomain}.crt" || ! -f "${XRAY_AGENT_TLS_DIR}/${TLSDomain}.key" ]]; then
        installTLS 1 0
    fi
}

xray_agent_hysteria2_prepare_runtime() {
    local reuse_hysteria2_config="n"
    local default_masquerade_url input_masquerade_url
    xray_agent_hysteria2_prepare_tls_domain
    echoContent yellow " ---> Hysteria2 需要当前 Xray-core 支持 protocol=hysteria；旧内核请先用菜单12升级"
    if ! xray_agent_xray_supports_hysteria2; then
        echoContent red " ---> 当前 Xray-core 不支持内置 Hysteria2，请先通过菜单12升级到正式版 v26.3.27 或更新版本。"
        return 1
    fi
    if [[ "$(xray_agent_public_ip_total_count)" -gt 1 ]]; then
        echoContent yellow " ---> 检测到多个公网 IP。Hysteria2/UDP 在多出口场景可能需要你确认系统路由和云防火墙，避免 UDP 回复源地址不一致。"
    fi
    checkUDPPort 443
    allowPort 443 udp

    if [[ -n "${Hysteria2MasqueradeURL:-}" ]]; then
        read -r -p "读取到上次 Hysteria2 配置，是否继续使用？[Y/n]:" reuse_hysteria2_config
        reuse_hysteria2_config="${reuse_hysteria2_config:-y}"
    fi

    if [[ "${reuse_hysteria2_config}" != "y" ]]; then
        default_masquerade_url="$(xray_agent_hysteria2_default_masquerade_url false)"
        if [[ -n "${default_masquerade_url}" ]]; then
            echoContent yellow "请输入 Hysteria2 伪装站 URL，[回车使用 ${default_masquerade_url}]:"
        else
            echoContent yellow "请输入 Hysteria2 伪装站 URL[例如 https://www.example.com/]:"
        fi
        read -r -p "URL:" input_masquerade_url
        Hysteria2MasqueradeURL="${input_masquerade_url:-${default_masquerade_url}}"
        [[ -n "${Hysteria2MasqueradeURL}" ]] || xray_agent_error " ---> Hysteria2 伪装站 URL 不可为空"
        echoContent yellow " ---> Hysteria2 Brutal 带宽按服务端视角填写：服务端上行≈客户端下载，服务端下行≈客户端上传。"
        echoContent yellow " ---> 填 0 或直接回车表示不写 Brutal 参数，不是自动测速；不确定就保持 0。"
        Hysteria2BrutalUpMbps="$(xray_agent_hysteria2_prompt_mbps "服务端上行带宽" "约等于客户端下载" "${Hysteria2BrutalUpMbps:-0}")"
        Hysteria2BrutalDownMbps="$(xray_agent_hysteria2_prompt_mbps "服务端下行带宽" "约等于客户端上传" "${Hysteria2BrutalDownMbps:-0}")"
    fi

    Hysteria2Port=443
}

xray_agent_hysteria2_finalmask_suffix() {
    local up_mbps="${Hysteria2BrutalUpMbps:-0}"
    local down_mbps="${Hysteria2BrutalDownMbps:-0}"
    local quic_params

    if [[ "${up_mbps}" == "0" && "${down_mbps}" == "0" ]]; then
        printf ''
        return 0
    fi
    if ! xray_agent_xray_supports_finalmask; then
        echoContent yellow " ---> 当前 Xray-core 不支持 finalmask.quicParams，Hysteria2 Brutal 参数已跳过。"
        printf ''
        return 0
    fi

    quic_params="$(jq -nc \
        --arg up "${up_mbps} mbps" \
        --arg down "${down_mbps} mbps" \
        --argjson useUp "$([[ "${up_mbps}" == "0" ]] && echo false || echo true)" \
        --argjson useDown "$([[ "${down_mbps}" == "0" ]] && echo false || echo true)" \
        '{
          quicParams:
            ({congestion:"brutal"}
            + (if $useUp then {brutalUp:$up} else {} end)
            + (if $useDown then {brutalDown:$down} else {} end))
        }')"
    printf ',\n        "finalmask": %s' "${quic_params}"
}

xray_agent_render_hysteria2_inbound() {
    local clients_json="$1"
    local sniffing_json="$2"
    xray_agent_load_protocol_profile "hysteria2"
    xray_agent_export_xray_network_template_vars
    export XRAY_HYSTERIA2_CLIENTS_JSON="${clients_json}"
    export XRAY_HYSTERIA2_MASQUERADE_URL_JSON
    export XRAY_HYSTERIA2_FINALMASK_SUFFIX
    export XRAY_SNIFFING_JSON="${sniffing_json}"
    export XRAY_TLS_DOMAIN="${TLSDomain}"
    export XRAY_TLS_ECH_SERVER_KEYS_JSON_ENTRY
    XRAY_HYSTERIA2_MASQUERADE_URL_JSON="$(xray_agent_json_string "${Hysteria2MasqueradeURL:-$(xray_agent_hysteria2_default_masquerade_url)}")"
    XRAY_HYSTERIA2_FINALMASK_SUFFIX="$(xray_agent_hysteria2_finalmask_suffix)"
    XRAY_TLS_ECH_SERVER_KEYS_JSON_ENTRY="$(xray_agent_tls_ech_server_keys_json_entry)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/inbounds/${XRAY_AGENT_PROTOCOL_INBOUND_TEMPLATE}" "${configPath}${XRAY_AGENT_PROTOCOL_CONFIG_FILE}"
}

xray_agent_hysteria2_render_from_current_users() {
    local clients_json sniffing_json
    if [[ -z "${UUID:-}" ]]; then
        xray_agent_prepare_uuid
    fi
    xray_agent_hysteria2_prepare_runtime
    clients_json="$(xray_agent_generate_clients_json "HYSTERIA2" "${UUID}")"
    sniffing_json="$(xray_agent_default_sniffing_json)"
    xray_agent_render_hysteria2_inbound "${clients_json}" "${sniffing_json}"
}

xray_agent_hysteria2_enable_or_reconfigure() {
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    if [[ -z "${coreInstallType}" ]]; then
        echoContent red " ---> 未安装 Xray-core 套餐，请先安装 TLS 或 Reality 套餐"
        return 1
    fi
    xray_agent_hysteria2_render_from_current_users
    reloadCore
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    echoContent green " ---> Hysteria2 已启用，UDP/443"
}

xray_agent_hysteria2_uninstall() {
    local hysteria2_file="${configPath}09_Hysteria2_inbounds.json"
    if [[ -f "${hysteria2_file}" ]]; then
        xray_agent_hysteria2_status_summary
        xray_agent_confirm "确认卸载 Hysteria2 inbound？[y/N]:" "n" || return 0
        rm -f "${hysteria2_file}"
        reloadCore
        echoContent green " ---> Hysteria2 已卸载"
    else
        echoContent yellow " ---> Hysteria2 未安装"
    fi
}

xray_agent_hysteria2_client_count() {
    local hysteria2_file="${configPath}09_Hysteria2_inbounds.json"
    [[ -f "${hysteria2_file}" ]] || {
        printf '0\n'
        return 0
    }
    jq -r '[.inbounds[0].settings.clients[]?] | length' "${hysteria2_file}" 2>/dev/null | tr -d '\r'
}

xray_agent_hysteria2_status_summary() {
    local hysteria2_file="${configPath}09_Hysteria2_inbounds.json"
    echoContent skyBlue "-------------------------Hysteria2状态-----------------------------"
    if [[ ! -f "${hysteria2_file}" ]]; then
        echoContent yellow "状态: 未安装"
        echoContent yellow "默认端口: UDP/443，与 TCP/443 不冲突"
        return 0
    fi
    echoContent yellow "状态: 已安装"
    echoContent yellow "监听: UDP/${Hysteria2Port:-443}"
    echoContent yellow "证书域名: ${TLSDomain:-未检测}"
    echoContent yellow "伪装站: ${Hysteria2MasqueradeURL:-未检测}"
    echoContent yellow "Brutal上行: ${Hysteria2BrutalUpMbps:-0} Mbps"
    echoContent yellow "Brutal下行: ${Hysteria2BrutalDownMbps:-0} Mbps"
    echoContent yellow "账号数量: $(xray_agent_hysteria2_client_count)"
    echoContent yellow "UDP/443占用: $(xray_agent_port_owner UDP 443)"
}

xray_agent_hysteria2_show_accounts() {
    local hysteria2_file="${configPath}09_Hysteria2_inbounds.json"
    readConfigHostPathUUID
    if [[ ! -f "${hysteria2_file}" ]]; then
        echoContent yellow " ---> Hysteria2 未安装"
        return 0
    fi
    jq -r '.inbounds[0].settings.clients[]?.auth' "${hysteria2_file}" | tr -d '\r' | while read -r auth; do
        [[ -n "${auth}" ]] || continue
        xray_agent_blank
        echoContent skyBlue " ---> 账号:${auth}"
        defaultBase64Code hysteria2 "${auth}"
    done
}

xray_agent_hysteria2_manage_menu() {
    local hysteria2_status
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    xray_agent_tool_status_header "Hysteria2管理"
    xray_agent_hysteria2_status_summary
    echoContent red "=============================================================="
    echoContent yellow "1.查看 Hysteria2 账号"
    echoContent yellow "2.启用或重配 Hysteria2"
    echoContent yellow "3.卸载 Hysteria2"
    echoContent red "=============================================================="
    read -r -p "请输入:" hysteria2_status
    case "${hysteria2_status}" in
        1) xray_agent_hysteria2_show_accounts ;;
        2)
            echoContent yellow "启用/重配会重写 Hysteria2 inbound，账号将复用当前 UUID/auth 列表。"
            xray_agent_confirm "确认继续？[Y/n]:" "y" && xray_agent_hysteria2_enable_or_reconfigure
            ;;
        3) xray_agent_hysteria2_uninstall ;;
    esac
}
