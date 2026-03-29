#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERIFY_TOOL_DIR=

ensure_jq() {
    local candidate
    if command -v jq >/dev/null 2>&1; then
        return 0
    fi
    for candidate in \
        /mnt/c/Users/*/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_*/jq.exe \
        /c/Users/*/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_*/jq.exe; do
        [[ -f "${candidate}" ]] || continue
        VERIFY_TOOL_DIR=$(mktemp -d)
        cat >"${VERIFY_TOOL_DIR}/jq" <<'EOF'
#!/usr/bin/env bash
set -e
jq_exe="__JQ_EXE__"
converted_args=()
for arg in "$@"; do
    if [[ "${arg}" == /* && -e "${arg}" ]] && command -v wslpath >/dev/null 2>&1; then
        converted_args+=("$(wslpath -w "${arg}")")
    else
        converted_args+=("${arg}")
    fi
done
exec "${jq_exe}" "${converted_args[@]}"
EOF
        sed -i "s|__JQ_EXE__|${candidate//|/\\|}|g" "${VERIFY_TOOL_DIR}/jq"
        chmod +x "${VERIFY_TOOL_DIR}/jq"
        export PATH="${VERIFY_TOOL_DIR}:${PATH}"
        return 0
    done
    echo "jq is required for verify/share-link-check.sh" >&2
    exit 1
}

ensure_jq
source "${ROOT_DIR}/install.sh"

trap 'rm -rf "${VERIFY_TOOL_DIR:-}"' EXIT

initVar
domain="example.com"
path="demo"
Port=443
RealityPort=8443
coreInstallType=3
RealityPublicKey="public-key"
RealityServerNames="www.cloudflare.com"
RealityShortID="1234abcd"

uri_tcp="$(xray_agent_build_vless_uri "vless_tcp_tls" "11111111-1111-1111-1111-111111111111")"
uri_reality="$(xray_agent_build_vless_uri "vless_reality_tcp" "11111111-1111-1111-1111-111111111111")"
uri_xhttp_tls="$(xray_agent_build_vless_uri "vless_xhttp" "11111111-1111-1111-1111-111111111111" "tls")"
uri_xhttp_reality="$(xray_agent_build_vless_uri "vless_xhttp" "11111111-1111-1111-1111-111111111111" "reality")"

[[ "${uri_tcp}" == vless://*type=tcp* ]]
[[ "${uri_reality}" == *security=reality* ]]
[[ "${uri_xhttp_tls}" == *type=xhttp* ]]
[[ "${uri_xhttp_reality}" == *pbk=public-key* ]]

jq empty <<<"$(xray_agent_build_clash_meta_vless "vless_tcp_tls" "11111111-1111-1111-1111-111111111111")"
jq empty <<<"$(xray_agent_build_sing_box_vless "vless_reality_tcp" "11111111-1111-1111-1111-111111111111")"
[[ "$(xray_agent_print_vmess_share "11111111-1111-1111-1111-111111111111")" == *vmess://* ]]

echo "PASS share-link-check"
