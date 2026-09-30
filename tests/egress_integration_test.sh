#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
xray_binary="${XRAY_AGENT_TEST_XRAY_BINARY:-${1:-}}"
[[ -x "${xray_binary}" ]] || { printf 'set XRAY_AGENT_TEST_XRAY_BINARY\n' >&2; exit 2; }
artifact_dir="${XRAY_AGENT_TEST_ARTIFACT_DIR:-$(mktemp -d /tmp/xray-egress-integration.XXXXXX)}"
mkdir -p "${artifact_dir}"
artifact_dir="$(cd "${artifact_dir}" && pwd)"
if [[ "${XRAY_AGENT_TEST_NETNS:-false}" != true ]]; then
    exec unshare --net env XRAY_AGENT_TEST_NETNS=true XRAY_AGENT_TEST_ARTIFACT_DIR="${artifact_dir}" \
        XRAY_AGENT_TEST_XRAY_BINARY="${xray_binary}" bash "$0"
fi

ip link set lo up
ip -4 address add 203.0.114.10/32 dev lo
ip -4 address add 203.0.114.11/32 dev lo
ip -6 address add 2001:db9::10/128 dev lo

export XRAY_AGENT_PROJECT_ROOT="${repo_root}"
source "${repo_root}/lib/common.sh"
source "${repo_root}/lib/core.sh"
source "${repo_root}/lib/network.sh"
source "${repo_root}/lib/network_policy.sh"
source "${repo_root}/lib/egress.sh"
source "${repo_root}/lib/routing.sh"
ctlPath="${xray_binary}"
configPath="${artifact_dir}/"

xray_agent_detect_network_capabilities() {
    networkDetected=true
    routeIPv4=true
    routeIPv6=true
    defaultIPv4Interface=lo
    defaultIPv6Interface=lo
    nativeIPv4Interface=lo
    nativeIPv6Interface=lo
    nativeIPv4Address=203.0.114.10
    nativeIPv6Address=2001:db9::10
    nativeHasIPv4=true
    nativeHasIPv6=true
    nativeRouteIPv4=true
    nativeRouteIPv6=true
    warpInterface=lo
    warpIPv4CSV=203.0.114.10
    warpIPv6CSV=2001:db9::10
    warpHasIPv4=true
    warpHasIPv6=true
    warpRouteIPv4=true
    warpRouteIPv6=true
    warpDefaultIPv4=false
    warpDefaultIPv6=false
    networkJSON='{}'
}

for preference in ipv4 ipv6; do
    policy="$(jq -nc --arg preference "${preference}" '{
      schemaVersion:2,defaultTcpEgress:"system-auto-out",defaultUdpEgress:"system-auto-out",defaultPreference:$preference,
      rules:[{id:"warp-domains",match:{domain:["domain:warp.test"],ip:["203.0.114.11/32"]},tcpEgress:"warp-auto-out",udpEgress:"warp-auto-out",preference:$preference}]
    }')"
    xray_agent_routing_documents_json "${policy}" >"${artifact_dir}/${preference}-documents.json"
done
python3 "${repo_root}/tests/egress_integration_probe.py" "${xray_binary}" "${artifact_dir}"
printf 'Artifacts: %s\n' "${artifact_dir}"
