#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "${temp_dir}"' EXIT

export XRAY_AGENT_PROJECT_ROOT="${repo_root}"
export XRAY_AGENT_PROFILE_DIR="${repo_root}/profiles"
configPath="${temp_dir}/"

source "${repo_root}/lib/common.sh"
source "${repo_root}/lib/network.sh"
source "${repo_root}/lib/core.sh"
source "${repo_root}/lib/routing.sh"

xray_agent_detect_network_capabilities() {
    routeIPv4="${routeIPv4:-true}"
    routeIPv6="${routeIPv6:-true}"
    warpHasIPv4="${warpHasIPv4:-false}"
    warpHasIPv6="${warpHasIPv6:-false}"
}

test_profile_dir="${temp_dir}/profiles"
mkdir -p "${test_profile_dir}/routing"
printf 'name=crlf\r\ndns_query_strategy=UseIP\r\noutbound_order=IPv6-out,IPv4-out,blackhole-out\r\n' >"${test_profile_dir}/routing/crlf.profile"
XRAY_AGENT_PROFILE_DIR="${test_profile_dir}"
xray_agent_load_routing_profile "crlf"
[[ "${XRAY_AGENT_ROUTING_DNS_QUERY_STRATEGY}" == "UseIP" ]]
[[ "${XRAY_AGENT_ROUTING_OUTBOUND_ORDER}" == "IPv6-out,IPv4-out,blackhole-out" ]]
XRAY_AGENT_PROFILE_DIR="${repo_root}/profiles"

xray_agent_xray_supports_happy_eyeballs() {
    return 1
}

legacy_ipv4="$(xray_agent_render_outbound_by_tag "IPv4-out")"
jq -e '.settings.domainStrategy == "UseIPv4" and (.streamSettings | not)' <<<"${legacy_ipv4}" >/dev/null

xray_agent_xray_supports_happy_eyeballs() {
    return 0
}

modern_ipv6="$(xray_agent_render_outbound_by_tag "IPv6-out")"
jq -e '
  .settings.domainStrategy == "AsIs"
  and .streamSettings.sockopt.domainStrategy == "UseIP"
  and .streamSettings.sockopt.happyEyeballs.prioritizeIPv6 == true
  and .streamSettings.sockopt.happyEyeballs.tryDelayMs == 250
' <<<"${modern_ipv6}" >/dev/null

cat >"${configPath}10_ipv4_outbounds.json" <<'JSON'
{
  "outbounds": [
    {"tag":"IPv4-out","protocol":"freedom","settings":{"domainStrategy":"UseIPv4"}},
    {"tag":"warp-out","protocol":"freedom","settings":{"domainStrategy":"UseIP"}},
    {"tag":"cn-out","protocol":"freedom","settings":{"domainStrategy":"UseIP"}},
    {"tag":"blackhole-out","protocol":"blackhole"},
    {"tag":"IPv6-out","protocol":"freedom","settings":{"domainStrategy":"UseIPv6"}}
  ]
}
JSON

cat >"${configPath}11_dns.json" <<'JSON'
{
  "dns": {
    "servers": ["localhost", "1.1.1.1"],
    "queryStrategy": "UseIPv6"
  }
}
JSON

xray_agent_apply_routing_profile "ipv6_first"

actual_tags="$(jq -r '[.outbounds[].tag] | join(",")' "${configPath}10_ipv4_outbounds.json")"
[[ "${actual_tags}" == "IPv6-out,IPv4-out,blackhole-out,warp-out,cn-out" ]]
jq -e '
  .outbounds[0].settings.domainStrategy == "AsIs"
  and .outbounds[0].streamSettings.sockopt.domainStrategy == "UseIP"
  and .outbounds[0].streamSettings.sockopt.happyEyeballs.prioritizeIPv6 == true
' "${configPath}10_ipv4_outbounds.json" >/dev/null
jq -e '.dns.servers == ["localhost", "1.1.1.1"] and .dns.queryStrategy == "UseIP"' "${configPath}11_dns.json" >/dev/null

routeIPv4=false
routeIPv6=true
[[ "$(xray_agent_default_dns_query_strategy)" == "UseIP" ]]

printf 'routing profile tests passed\n'
