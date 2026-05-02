#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

XRAY_AGENT_XHTTP_VISION_FLOW="xtls-rprx-vision"

xray_agent_xray_current_release_channel() {
    local version tag response_file prerelease
    version="$(xray_agent_xray_version_number 2>/dev/null || true)"
    [[ -n "${version}" ]] || {
        printf 'unknown\n'
        return 0
    }
    tag="v${version}"

    if [[ -n "${XRAY_AGENT_TEST_RELEASES_JSON:-}" ]]; then
        prerelease="$(printf '%s\n' "${XRAY_AGENT_TEST_RELEASES_JSON}" | jq -r --arg tag "${tag}" '.[]? | select(.tag_name == $tag) | .prerelease // empty' 2>/dev/null | head -1)"
    else
        response_file="$(mktemp)"
        if xray_agent_github_fetch_releases "XTLS/Xray-core" "${response_file}" >/dev/null 2>&1; then
            prerelease="$(jq -r --arg tag "${tag}" '.[]? | select(.tag_name == $tag) | .prerelease // empty' "${response_file}" 2>/dev/null | head -1)"
        fi
        rm -f "${response_file:-}"
    fi

    case "${prerelease}" in
        true) printf 'prerelease\n' ;;
        false) printf 'stable\n' ;;
        *) printf 'unknown\n' ;;
    esac
}

xray_agent_vless_encryption_resolved_value() {
    if [[ -z "${VLESSEncryption:-}" && -n "${VLESSDecryption:-}" && "${VLESSDecryption}" != "none" ]]; then
        VLESSEncryption="$(xray_agent_vless_encryption_from_decryption "${VLESSDecryption}" 2>/dev/null || true)"
    fi
    printf '%s\n' "${VLESSEncryption:-none}"
}

xray_agent_vless_encryption_enabled() {
    local encryption
    encryption="$(xray_agent_vless_encryption_resolved_value)"
    [[ -n "${encryption}" && "${encryption}" != "none" ]]
}

xray_agent_xhttp_inbound_path() {
    if [[ -n "${configPath:-}" ]]; then
        printf '%s08_VLESS_XHTTP_inbounds.json\n' "${configPath}"
    elif declare -F xray_agent_xhttp_inbound_file >/dev/null 2>&1; then
        xray_agent_xhttp_inbound_file
    else
        printf '08_VLESS_XHTTP_inbounds.json\n'
    fi
}

xray_agent_xhttp_inbound_has_vision_flow() {
    local inbound_file="${1:-$(xray_agent_xhttp_inbound_path)}"
    [[ -f "${inbound_file}" ]] || return 1
    jq -e --arg flow "${XRAY_AGENT_XHTTP_VISION_FLOW}" '
        any(.inbounds[0].settings.clients[]?; .flow? == $flow)
    ' "${inbound_file}" >/dev/null 2>&1
}

xray_agent_xhttp_vision_flow_for_new_config() {
    [[ "${XRAY_AGENT_XHTTP_DISABLE_VISION_FLOW:-false}" == "true" ]] && return 0
    xray_agent_vless_encryption_enabled || return 0
    printf '%s\n' "${XRAY_AGENT_XHTTP_VISION_FLOW}"
}

xray_agent_xhttp_vision_flow_for_share() {
    local inbound_file flow
    inbound_file="$(xray_agent_xhttp_inbound_path)"
    if [[ -f "${inbound_file}" ]]; then
        if xray_agent_xhttp_inbound_has_vision_flow "${inbound_file}"; then
            printf '%s\n' "${XRAY_AGENT_XHTTP_VISION_FLOW}"
        fi
        return 0
    fi
    flow="$(xray_agent_xhttp_vision_flow_for_new_config)"
    [[ -n "${flow}" ]] && printf '%s\n' "${flow}"
}

xray_agent_xhttp_vless_client_json() {
    local uuid="$1"
    local flow
    flow="$(xray_agent_xhttp_vision_flow_for_share)"
    if [[ -n "${flow}" ]]; then
        jq -nc --arg id "${uuid}" --arg flow "${flow}" '{id:$id, flow:$flow}'
    else
        jq -nc --arg id "${uuid}" '{id:$id}'
    fi
}

xray_agent_xhttp_should_validate_vision_flow() {
    [[ "${XRAY_AGENT_XHTTP_DISABLE_VISION_FLOW:-false}" != "true" ]] &&
        xray_agent_vless_encryption_enabled
}

xray_agent_reality_tls_ping_address() {
    local target="$1"
    target="${target//\"/}"
    target="${target#https://}"
    target="${target#http://}"
    target="${target%%/*}"
    target="${target%%,*}"
    if [[ "${target}" =~ ^\[([^]]+)\](:[0-9]+)?$ ]]; then
        if [[ -n "${BASH_REMATCH[2]}" ]]; then
            printf '[%s]%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        else
            printf '%s\n' "${BASH_REMATCH[1]}"
        fi
    else
        printf '%s\n' "${target}"
    fi
}

xray_agent_reality_tls_ping_host() {
    xray_agent_reality_tls_ping_address "$@"
}

xray_agent_reality_tls_ping_output() {
    local target="$1"
    local address
    if [[ -n "${XRAY_AGENT_TEST_TLS_PING_OUTPUT:-}" ]]; then
        printf '%s\n' "${XRAY_AGENT_TEST_TLS_PING_OUTPUT}"
        return 0
    fi
    address="$(xray_agent_reality_tls_ping_address "${target}")"
    [[ -n "${address}" && -x "${ctlPath:-}" ]] || return 1
    if command -v timeout >/dev/null 2>&1; then
        timeout 10 "${ctlPath}" tls ping "${address}" 2>/dev/null
    else
        "${ctlPath}" tls ping "${address}" 2>/dev/null
    fi
}

xray_agent_reality_tls_ping_certificate_length_from_output() {
    awk '
        BEGIN { IGNORECASE = 1 }
        /Certificate chain/ && /total length/ {
            line = $0
            sub(/^.*total length[^0-9]*/, "", line)
            sub(/[^0-9].*$/, "", line)
            if (line != "") {
                print line
                exit
            }
        }
    '
}

xray_agent_reality_tls_ping_supports_mlkem_from_output() {
    grep -Eqi 'X25519MLKEM768|X25519[[:space:]-]*ML[[:space:]-]*KEM[[:space:]-]*768|ML-KEM-768'
}

xray_agent_reality_target_pq_status_json() {
    local target="$1"
    local output cert_length mlkem mldsa summary reason
    if ! output="$(xray_agent_reality_tls_ping_output "${target}")"; then
        jq -nc '{tls_ping:"failed", certificate_length:null, x25519mlkem768:false, mldsa65_allowed:false, summary:"unknown", reason:"tls ping failed"}'
        return 0
    fi

    cert_length="$(printf '%s\n' "${output}" | xray_agent_reality_tls_ping_certificate_length_from_output)"
    if printf '%s\n' "${output}" | xray_agent_reality_tls_ping_supports_mlkem_from_output; then
        mlkem=true
    else
        mlkem=false
    fi

    if [[ -n "${cert_length}" && "${cert_length}" -ge 3500 ]]; then
        mldsa=true
        if [[ "${mlkem}" == "true" ]]; then
            summary="complete"
            reason="target supports X25519MLKEM768 and certificate chain length is 3500+"
        else
            summary="partial"
            reason="certificate chain length is 3500+, but X25519MLKEM768 was not detected"
        fi
    elif [[ -n "${cert_length}" ]]; then
        mldsa=false
        summary="unsuitable"
        reason="certificate chain is shorter than 3500 and cannot hide ML-DSA-65 signature"
    else
        mldsa=false
        summary="unknown"
        reason="certificate chain length was not detected"
    fi

    jq -nc \
        --argjson certLength "$(if [[ -n "${cert_length}" ]]; then printf '%s' "${cert_length}"; else printf 'null'; fi)" \
        --argjson mlkem "${mlkem}" \
        --argjson mldsa "${mldsa}" \
        --arg summary "${summary}" \
        --arg reason "${reason}" \
        '{tls_ping:"ok", certificate_length:$certLength, x25519mlkem768:$mlkem, mldsa65_allowed:$mldsa, summary:$summary, reason:$reason}'
}

xray_agent_reality_target_certificate_length() {
    local status_json
    status_json="$(xray_agent_reality_target_pq_status_json "$1")"
    printf '%s\n' "${status_json}" | jq -r '.certificate_length // empty'
}

xray_agent_reality_target_supports_x25519mlkem768() {
    local status_json
    status_json="$(xray_agent_reality_target_pq_status_json "$1")"
    [[ "$(printf '%s\n' "${status_json}" | jq -r '.x25519mlkem768')" == "true" ]]
}

xray_agent_reality_target_allows_mldsa65() {
    local status_json
    status_json="$(xray_agent_reality_target_pq_status_json "$1")"
    [[ "$(printf '%s\n' "${status_json}" | jq -r '.mldsa65_allowed')" == "true" ]]
}

xray_agent_reality_target_pq_summary() {
    local target="$1"
    local status_json summary cert_length reason
    [[ -n "${target}" ]] || return 0
    status_json="$(xray_agent_reality_target_pq_status_json "${target}")"
    summary="$(printf '%s\n' "${status_json}" | jq -r '.summary')"
    cert_length="$(printf '%s\n' "${status_json}" | jq -r '.certificate_length // "未知"')"
    reason="$(printf '%s\n' "${status_json}" | jq -r '.reason')"
    case "${summary}" in
        complete)
            printf 'Reality PQ: 完整条件满足，证书链长度=%s，支持 X25519MLKEM768，可启用 ML-DSA-65\n' "${cert_length}"
            ;;
        partial)
            printf 'Reality PQ: 部分增强，证书链长度=%s，可启用 ML-DSA-65；未检测到 X25519MLKEM768\n' "${cert_length}"
            ;;
        unsuitable)
            printf 'Reality PQ: 未启用 ML-DSA-65，证书链长度=%s，低于 3500，无法隐藏 ML-DSA-65 签名\n' "${cert_length}"
            ;;
        *)
            printf 'Reality PQ: 未完成目标预检，%s\n' "${reason}"
            ;;
    esac
}
