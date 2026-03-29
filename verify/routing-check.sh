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
    echo "jq is required for verify/routing-check.sh" >&2
    exit 1
}

ensure_jq
source "${ROOT_DIR}/install.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}" "${VERIFY_TOOL_DIR:-}"' EXIT

initVar
configPath="${TMP_DIR}/conf/"
nginxConfigPath="${TMP_DIR}/nginx/"
mkdir -p "${configPath}" "${nginxConfigPath}"

render_routing_base() {
    export XRAY_OUTBOUNDS_JSON
    export XRAY_ROUTING_DOMAIN_STRATEGY="AsIs"
    export XRAY_ROUTING_RULES_JSON
    XRAY_OUTBOUNDS_JSON="$(xray_agent_default_outbounds_json)"
    XRAY_ROUTING_RULES_JSON="$(xray_agent_default_routing_rules_json)"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/09_routing.json.tpl" "${configPath}09_routing.json"
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/xray/base/10_outbounds.json.tpl" "${configPath}10_ipv4_outbounds.json"
}

curl() {
    if [[ "$*" == *" -6 "* ]] || [[ "$*" == *"cdn-cgi/trace"* ]]; then
        printf 'ip=2001:db8::1\n'
    else
        command curl "$@"
    fi
}

ip() {
    printf '1: wgcf: <POINTOPOINT>\n'
}

reloadCore() { :; }

render_routing_base
printf '4\n' | ipv6Routing
first_tag=$(jq -r '.outbounds[0].tag' "${configPath}10_ipv4_outbounds.json" | tr -d '\r')
[[ "${first_tag}" == "IPv6-out" ]]

render_routing_base
printf '4\n' | blacklist
grep -q '"outboundTag": "cn-blackhole"' "${configPath}09_routing.json"
grep -q '"tag": "cn-blackhole"' "${configPath}10_ipv4_outbounds.json"

render_routing_base
printf '4\n' | warpRouting
grep -q '"outboundTag": "cn-out"' "${configPath}09_routing.json"
grep -q '"tag": "cn-out"' "${configPath}10_ipv4_outbounds.json"

echo "PASS routing-check"
