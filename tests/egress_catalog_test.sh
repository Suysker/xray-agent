#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export XRAY_AGENT_PROJECT_ROOT="${repo_root}"
export XRAY_AGENT_ETC_DIR="$(mktemp -d)"
trap 'rm -rf -- "${XRAY_AGENT_ETC_DIR}"' EXIT

source "${repo_root}/lib/common.sh"
source "${repo_root}/lib/network.sh"
source "${repo_root}/lib/core.sh"
source "${repo_root}/lib/egress.sh"

xray_agent_xray_supports_safe_happy_eyeballs() {
    return 0
}

xray_agent_xray_supports_freedom_final_rules() {
    return 0
}

xray_agent_interface_trace_response() {
    case "$1:$2" in
        4:ens-private) return 1 ;;
        6:ens-private) printf 'ip=2001:db8::10\nwarp=off\n' ;;
        4:wg-test) printf 'ip=198.51.100.10\nwarp=on\n' ;;
        6:wg-test) printf 'ip=2001:db8::20\nwarp=plus\n' ;;
        4:ens-warped) printf 'ip=198.51.100.20\nwarp=on\n' ;;
        4:wrong-family) printf 'ip=2001:db8::30\nwarp=off\n' ;;
        *) return 1 ;;
    esac
}

if xray_agent_interface_provider_egress_usable 4 ens-private 172.16.0.10 native; then
    exit 1
fi
xray_agent_interface_provider_egress_usable 6 ens-private 2001:db8::10 native
xray_agent_interface_provider_egress_usable 4 wg-test 172.16.0.20 warp
xray_agent_interface_provider_egress_usable 6 wg-test 2001:db8::20 warp
if xray_agent_interface_provider_egress_usable 4 ens-warped 172.16.0.30 native; then
    exit 1
fi
if xray_agent_interface_provider_egress_usable 4 wrong-family 172.16.0.40 native; then
    exit 1
fi
if xray_agent_interface_provider_egress_usable 6 wg-test '' warp; then
    exit 1
fi

set_network_case() {
    networkDetected=true
    routeIPv4="$1"
    routeIPv6="$2"
    defaultIPv4Interface="$3"
    defaultIPv6Interface="$4"
    nativeIPv4Interface="$5"
    nativeIPv6Interface="$6"
    nativeIPv4Address="$7"
    nativeIPv6Address="$8"
    nativeHasIPv4="$9"
    shift 9
    nativeHasIPv6="$1"
    warpInterface="$2"
    warpIPv4CSV="$3"
    warpIPv6CSV="$4"
    warpHasIPv4="$5"
    warpHasIPv6="$6"
    warpDefaultIPv4="$7"
    warpDefaultIPv6="$8"
    nativeRouteIPv4="${nativeHasIPv4}"
    nativeRouteIPv6="${nativeHasIPv6}"
    warpRouteIPv4="${warpHasIPv4}"
    warpRouteIPv6="${warpHasIPv6}"
    networkJSON='{}'
}

set_network_case true true ens3 wg-test ens3 '' 192.0.2.10 '' true false wg-test '' 2606:4700:110::2 false true false true
catalog="$(xray_agent_egress_catalog_json)"
jq -e '
  (.egresses[] | select(.id == "native-ipv4-out") | .available == true and .interface == "ens3")
  and (.egresses[] | select(.id == "warp-ipv6-out") | .available == true and .interface == "wg-test")
  and (.egresses[] | select(.id == "system-auto-out") | .available == true)
  and (.egresses[] | select(.id == "native-auto-out") | .available == false)
  and (.egresses[] | select(.id == "warp-auto-out") | .available == false)
' <<<"${catalog}" >/dev/null
[[ "$(xray_agent_egress_effective_family_id ipv4)" == "native-ipv4-out" ]]
[[ "$(xray_agent_egress_effective_family_id ipv6)" == "warp-ipv6-out" ]]

set_network_case true true ens9 ens9 ens9 ens9 198.51.100.7 2001:db8::7 true true wg-random 172.16.0.2 2606:4700:110::2 true true false false
catalog="$(xray_agent_egress_catalog_json)"
jq -e '
  (.egresses[] | select(.id == "native-auto-out") | .available == true and .interface == "ens9")
  and (.egresses[] | select(.id == "warp-auto-out") | .available == true and .interface == "wg-random")
' <<<"${catalog}" >/dev/null

outbound="$(xray_agent_egress_outbound_json_for_id warp-auto-out ipv6)"
jq -e '
  .tag == "warp-auto-ipv6-first"
  and .settings.domainStrategy == "AsIs"
  and .settings.finalRules == [{"action":"allow"}]
  and .streamSettings.sockopt.interface == "wg-random"
  and .streamSettings.sockopt.happyEyeballs.prioritizeIPv6 == true
' <<<"${outbound}" >/dev/null

printf 'egress catalog tests passed\n'
