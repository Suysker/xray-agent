#!/usr/bin/env bash
set -euo pipefail

TARGET_ROOT="${1:-/etc/xray-agent}"

mkdir -p \
    "${TARGET_ROOT}/lib" \
    "${TARGET_ROOT}/templates/xray/base" \
    "${TARGET_ROOT}/templates/xray/inbounds" \
    "${TARGET_ROOT}/templates/xray/outbounds" \
    "${TARGET_ROOT}/templates/xray/extras" \
    "${TARGET_ROOT}/templates/nginx" \
    "${TARGET_ROOT}/templates/share" \
    "${TARGET_ROOT}/templates/systemd" \
    "${TARGET_ROOT}/profiles/install" \
    "${TARGET_ROOT}/profiles/protocol" \
    "${TARGET_ROOT}/profiles/routing" \
    "${TARGET_ROOT}/profiles/subscription" \
    "${TARGET_ROOT}/docs" \
    "${TARGET_ROOT}/packaging"

move_if_missing() {
    local old_path="$1"
    local new_path="$2"
    if [[ -f "${old_path}" && ! -f "${new_path}" ]]; then
        mv "${old_path}" "${new_path}"
    fi
}

legacy_template_dir="${TARGET_ROOT}/templates/xray"
legacy_profile_dir="${TARGET_ROOT}/profiles"
legacy_template_targets=(
    "00_log.json.tpl:base/00_log.json.tpl"
    "01_policy.json.tpl:base/01_policy.json.tpl"
    "09_routing.json.tpl:base/09_routing.json.tpl"
    "10_outbounds.json.tpl:base/10_outbounds.json.tpl"
    "11_dns.json.tpl:base/11_dns.json.tpl"
    "inbound_vless_tls_vision.json.tpl:inbounds/02_vless_tcp_tls.json.tpl"
    "inbound_vless_ws_tls.json.tpl:inbounds/03_vless_ws_tls.json.tpl"
    "inbound_vmess_ws_tls.json.tpl:inbounds/05_vmess_ws_tls.json.tpl"
    "inbound_vless_reality_vision.json.tpl:inbounds/07_vless_reality_tcp.json.tpl"
    "inbound_vless_xhttp_tls.json.tpl:inbounds/08_vless_xhttp.json.tpl"
)

for mapping in "${legacy_template_targets[@]}"; do
    old_name="${mapping%%:*}"
    new_name="${mapping#*:}"
    move_if_missing \
        "${legacy_template_dir}/${old_name}" \
        "${legacy_template_dir}/${new_name}"
done

legacy_profile_names=(
    "server_hysteria2.env"
    "server_reality_vision.env"
    "server_reality_xhttp.env"
    "server_tls_vision.env"
    "server_tls_ws_vless.env"
    "server_tls_ws_vmess.env"
    "server_tls_xhttp.env"
    "local_tun.env"
)

legacy_feature_wrappers=(
    "browser_dialer.sh"
    "ech.sh"
    "finalmask.sh"
    "hysteria2.sh"
    "trusted_xff.sh"
    "tun.sh"
    "vless_enc.sh"
)

legacy_flat_helpers=(
    "env.sh"
    "firewall.sh"
    "profiles.sh"
    "sniffing.sh"
    "sockopt.sh"
    "users.sh"
    "xray_core.sh"
)

for legacy_name in "${legacy_profile_names[@]}"; do
    rm -f "${legacy_profile_dir}/${legacy_name}"
done

for legacy_name in "${legacy_feature_wrappers[@]}"; do
    rm -f "${TARGET_ROOT}/lib/features/${legacy_name}"
done

for legacy_name in "${legacy_flat_helpers[@]}"; do
    rm -f "${TARGET_ROOT}/lib/${legacy_name}"
done

rm -rf \
    "${TARGET_ROOT}/lib/common" \
    "${TARGET_ROOT}/lib/runtime" \
    "${TARGET_ROOT}/lib/system" \
    "${TARGET_ROOT}/lib/tls" \
    "${TARGET_ROOT}/lib/core" \
    "${TARGET_ROOT}/lib/nginx" \
    "${TARGET_ROOT}/lib/protocols" \
    "${TARGET_ROOT}/lib/accounts" \
    "${TARGET_ROOT}/lib/routing" \
    "${TARGET_ROOT}/lib/features" \
    "${TARGET_ROOT}/lib/apps" \
    "${TARGET_ROOT}/lib/external" \
    "${TARGET_ROOT}/lib/experimental" \
    "${TARGET_ROOT}/profiles/experimental" \
    "${TARGET_ROOT}/templates/xray/snippets" \
    "${TARGET_ROOT}/templates/cron" \
    "${TARGET_ROOT}/templates/packages" \
    "${TARGET_ROOT}/verify" \
    "${TARGET_ROOT}/scripts"

rm -f \
    "${TARGET_ROOT}/templates/xray/inbounds/12_hysteria2.json.tpl" \
    "${TARGET_ROOT}/templates/xray/inbounds/20_tun.json.tpl" \
    "${TARGET_ROOT}/templates/xray/extras/access_log_off.patch.json" \
    "${TARGET_ROOT}/templates/xray/extras/access_log_on.patch.json" \
    "${TARGET_ROOT}/templates/xray/extras/sniffing_off.patch.json" \
    "${TARGET_ROOT}/templates/xray/extras/sniffing_on.patch.json" \
    "${TARGET_ROOT}/templates/xray/extras/sockopt.patch.json" \
    "${TARGET_ROOT}/templates/nginx/mirror_replace.sed.tpl"
