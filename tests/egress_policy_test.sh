#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "${temp_dir}"' EXIT

export XRAY_AGENT_PROJECT_ROOT="${repo_root}"
export XRAY_AGENT_ETC_DIR="${temp_dir}/etc"
test_xray_binary="${XRAY_AGENT_TEST_XRAY_BINARY:-}"
if [[ -n "${test_xray_binary}" ]]; then
    export XRAY_AGENT_SKIP_XRAY_CONFIG_TEST=false
else
    export XRAY_AGENT_SKIP_XRAY_CONFIG_TEST=true
fi
configPath="${temp_dir}/conf/"
mkdir -p "${configPath}"

source "${repo_root}/lib/common.sh"
source "${repo_root}/lib/network.sh"
source "${repo_root}/lib/network_policy.sh"
source "${repo_root}/lib/core.sh"
source "${repo_root}/lib/egress.sh"
source "${repo_root}/lib/routing.sh"

if [[ -n "${test_xray_binary}" ]]; then
    ctlPath="${test_xray_binary}"
else
    xray_agent_xray_supports_safe_happy_eyeballs() {
        return 0
    }

    xray_agent_xray_supports_freedom_final_rules() {
        return 0
    }
fi

xray_agent_detect_network_capabilities() {
    networkDetected=true
    routeIPv4=true
    routeIPv6=true
    defaultIPv4Interface=ens18
    defaultIPv6Interface=warp-random
    nativeIPv4Interface=ens18
    nativeIPv6Interface=
    nativeIPv4Address=203.0.114.10
    nativeIPv6Address=
    nativeHasIPv4=true
    nativeHasIPv6=false
    nativeRouteIPv4=true
    nativeRouteIPv6=false
    warpInterface=warp-random
    warpIPv4CSV=172.16.0.2
    warpIPv6CSV=2606:4700:110::2
    warpHasIPv4=true
    warpHasIPv6=true
    warpRouteIPv4=true
    warpRouteIPv6=true
    warpDefaultIPv4=false
    warpDefaultIPv6=true
    networkJSON='{}'
    if [[ "${native_family:-ipv4}" == "ipv6" ]]; then
        defaultIPv4Interface=warp-random
        defaultIPv6Interface=ens18
        nativeIPv4Interface=
        nativeIPv4Address=
        nativeHasIPv4=false
        nativeRouteIPv4=false
        nativeIPv6Interface=ens18
        nativeIPv6Address=2001:db9::10
        nativeHasIPv6=true
        nativeRouteIPv6=true
        warpDefaultIPv4=true
        warpDefaultIPv6=false
    fi
}

xray_agent_network_policy_reconcile_egress_policy() {
    return 0
}

default_policy="$(xray_agent_egress_default_policy_json)"
xray_agent_egress_policy_validate_json "${default_policy}"
jq -e '.schemaVersion == 2 and .defaultTcpEgress == "system-auto-out" and .defaultUdpEgress == "system-auto-out" and .defaultPreference == "ipv4"' <<<"${default_policy}" >/dev/null
native_family=ipv6
default_policy="$(xray_agent_egress_default_policy_json)"
xray_agent_egress_policy_validate_json "${default_policy}"
jq -e '.defaultPreference == "ipv6" and .defaultUdpEgress == "system-auto-out"' <<<"${default_policy}" >/dev/null
native_family=ipv4

policy="$(jq -nc '{
  schemaVersion:2,
  defaultTcpEgress:"system-auto-out",
  defaultPreference:"ipv6",
  defaultUdpEgress:"native-ipv4-out",
  rules:[{
    id:"openai-warp",
    match:{domain:["geosite:openai"]},
    tcpEgress:"warp-auto-out",
    preference:"ipv4",
    udpEgress:"warp-ipv4-out"
  }]
}')"
xray_agent_egress_policy_validate_json "${policy}"
xray_agent_routing_apply_policy_json "${policy}"

jq -e '
  [.outbounds[].tag] == [
    "system-auto-ipv6-first",
    "native-ipv4-out",
    "warp-auto-ipv4-first",
    "warp-ipv4-out",
    "blackhole-out"
  ]
' "${configPath}10_outbounds.json" >/dev/null
jq -e '
  .routing.domainStrategy == "IPOnDemand"
  and .routing.rules[0].outboundTag == "blackhole-out"
  and .routing.rules[1].network == "tcp"
  and .routing.rules[1].domain == ["geosite:openai"]
  and .routing.rules[1].outboundTag == "warp-auto-ipv4-first"
  and .routing.rules[2].network == "udp"
  and .routing.rules[-2].outboundTag == "system-auto-ipv6-first"
  and .routing.rules[-1].outboundTag == "native-ipv4-out"
' "${configPath}09_routing.json" >/dev/null
jq -e '.dns.queryStrategy == "UseIP"' "${configPath}11_dns.json" >/dev/null
jq -e '.defaultPreference == "ipv6"' "$(xray_agent_egress_policy_path)" >/dev/null
xray_agent_routing_policy_is_materialized "${policy}"
jq '.routing.domainStrategy="AsIs"' "${configPath}09_routing.json" >"${configPath}09_routing.json.tmp"
mv "${configPath}09_routing.json.tmp" "${configPath}09_routing.json"
if xray_agent_routing_policy_is_materialized "${policy}"; then
    exit 1
fi
xray_agent_egress_reconcile_current_policy
xray_agent_routing_policy_is_materialized "${policy}"

before_checksum="$(sha256sum "${configPath}09_routing.json" "${configPath}10_outbounds.json" "$(xray_agent_egress_policy_path)")"
invalid_policy="$(jq -c '.defaultUdpEgress="native-ipv6-out"' <<<"${policy}")"
if xray_agent_routing_apply_policy_json "${invalid_policy}"; then
    exit 1
fi
after_checksum="$(sha256sum "${configPath}09_routing.json" "${configPath}10_outbounds.json" "$(xray_agent_egress_policy_path)")"
[[ "${before_checksum}" == "${after_checksum}" ]]

combined_policy="$(jq '.rules[0].match.ip=["geoip:cn"] | .defaultUdpEgress="system-auto-out" | .rules[0].udpEgress="warp-auto-out"' <<<"${policy}")"
xray_agent_routing_apply_policy_json "${combined_policy}"
jq -e '
  .routing.rules as $rules
  | all("tcp", "udp"; . as $network |
      ([$rules[] | select(.network==$network and has("domain"))] | length)==1
      and ([$rules[] | select(.network==$network and .ip==["geoip:cn"])] | length)==1)
  and all($rules[]; (has("domain") and has("ip")) | not)
' "${configPath}09_routing.json" >/dev/null
jq -e '
  any(.outbounds[]; .tag=="system-auto-udp-ipv6-first" and .settings.domainStrategy=="ForceIPv6v4" and (.streamSettings.sockopt.happyEyeballs==null))
  and any(.outbounds[]; .tag=="warp-auto-udp-ipv4-first" and .settings.domainStrategy=="ForceIPv4v6" and .streamSettings.sockopt.interface=="warp-random")
' "${configPath}10_outbounds.json" >/dev/null

selection_count=0
xray_agent_egress_select() {
    if [[ "$1" == "tcp" ]]; then
        XRAY_AGENT_SELECTED_EGRESS=warp-auto-out
    else
        XRAY_AGENT_SELECTED_EGRESS=native-ipv4-out
    fi
    selection_count=$((selection_count + 1))
}
xray_agent_egress_select_preference() {
    XRAY_AGENT_SELECTED_PREFERENCE=ipv6
}

xray_agent_egress_add_domain_rule "${policy}" <<< $'menu-rule\nopenai'
menu_policy="${XRAY_AGENT_CANDIDATE_POLICY_JSON}"
jq -e '
  .rules[-1].id == "menu-rule"
  and .rules[-1].match.domain == ["geosite:openai"]
  and .rules[-1].tcpEgress == "warp-auto-out"
  and .rules[-1].preference == "ipv6"
  and .rules[-1].udpEgress == "native-ipv4-out"
' <<<"${menu_policy}" >/dev/null
[[ "${selection_count}" -eq 2 ]]

xray_agent_egress_add_domain_rule "${menu_policy}" <<< $'menu-rule\nexample.com,domain:example.org,geosite:openai,openai,full:only.example.net,regexp:^test[.]net$'
menu_policy="${XRAY_AGENT_CANDIDATE_POLICY_JSON}"
jq -e '
  ([.rules[] | select(.id == "menu-rule")] | length) == 1
  and .rules[-1].match.domain == (["domain:example.com","domain:example.org","geosite:openai","full:only.example.net","regexp:^test[.]net$"] | sort)
' <<<"${menu_policy}" >/dev/null
if xray_agent_domain_matches_json 'https://example.com/'; then
    printf 'URL incorrectly accepted as a domain\n' >&2
    exit 1
fi

xray_agent_egress_remove_rule "${menu_policy}" <<< 'menu-rule'
menu_policy="${XRAY_AGENT_CANDIDATE_POLICY_JSON}"
jq -e 'all(.rules[]; .id != "menu-rule")' <<<"${menu_policy}" >/dev/null

xray_agent_egress_set_warp_domains "${menu_policy}" 'example.com,geosite:openai'
menu_policy="${XRAY_AGENT_CANDIDATE_POLICY_JSON}"
xray_agent_egress_set_warp_domains "${menu_policy}" 'example.org,example.com,geosite:openai'
menu_policy="${XRAY_AGENT_CANDIDATE_POLICY_JSON}"
jq -e '
  ([.rules[] | select(.id=="warp-domains")] | length)==1
  and any(.rules[]; .id=="warp-domains" and .match.domain==["domain:example.com","domain:example.org","geosite:openai"] and .tcpEgress=="warp-auto-out" and .udpEgress=="warp-auto-out" and .preference=="ipv6")
' <<<"${menu_policy}" >/dev/null
warp_domains="$(jq -c '.rules[] | select(.id=="warp-domains")' <<<"${menu_policy}")"
xray_agent_egress_toggle_cn_warp "${menu_policy}"
menu_policy="${XRAY_AGENT_CANDIDATE_POLICY_JSON}"
jq -e '
  .rules[-1].id == "cn-egress"
  and .rules[-1].match.domain == ["geosite:cn"]
  and .rules[-1].match.ip == ["geoip:cn"]
  and .rules[-1].tcpEgress == "warp-auto-out"
  and .rules[-1].udpEgress == "warp-auto-out"
  and .rules[-1].preference == "ipv6"
' <<<"${menu_policy}" >/dev/null
xray_agent_egress_toggle_cn_warp "${menu_policy}"
menu_policy="${XRAY_AGENT_CANDIDATE_POLICY_JSON}"
jq -e 'all(.rules[]; .id!="cn-egress")' <<<"${menu_policy}" >/dev/null
[[ "$(jq -c '.rules[] | select(.id=="warp-domains")' <<<"${menu_policy}")" == "${warp_domains}" ]]
xray_agent_egress_set_warp_domains "${menu_policy}" ''
jq -e 'all(.rules[]; .id!="warp-domains")' <<<"${XRAY_AGENT_CANDIDATE_POLICY_JSON}" >/dev/null

printf 'egress policy tests passed\n'
