#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "${temp_dir}"' EXIT

export XRAY_AGENT_PROJECT_ROOT="${repo_root}"
export XRAY_AGENT_ETC_DIR="${temp_dir}/etc"
source "${repo_root}/lib/common.sh"
source "${repo_root}/lib/network.sh"
source "${repo_root}/lib/network_policy.sh"

rules_v4="${temp_dir}/rules-v4"
rules_v6="${temp_dir}/rules-v6"
: >"${rules_v4}"
: >"${rules_v6}"

xray_agent_network_policy_ip() {
    local family="$1"
    local action="$2"
    shift 2
    local rules_file
    [[ "${family}" == "-4" ]] && rules_file="${rules_v4}" || rules_file="${rules_v6}"
    case "${action}" in
        rule)
            local operation="$1"
            shift
            case "${operation}" in
                show)
                    cat "${rules_file}"
                    ;;
                add)
                    printf '%s: from %s lookup main\n' "$2" "$4" >>"${rules_file}"
                    ;;
                del)
                    awk -v priority="$2:" '$1 != priority' "${rules_file}" >"${rules_file}.tmp"
                    mv "${rules_file}.tmp" "${rules_file}"
                    ;;
            esac
            ;;
    esac
}

xray_agent_detect_network_capabilities() {
    warpDefaultIPv4=true
    warpDefaultIPv6=false
    nativeIPv4Address=192.0.2.20
    nativeIPv6Address=2001:db8::20
}

policy='{"defaultTcpEgress":"native-ipv4-out","defaultUdpEgress":"native-ipv4-out","rules":[]}'
xray_agent_network_policy_reconcile_egress_policy "${policy}"
xray_agent_network_policy_reconcile_egress_policy "${policy}"
[[ "$(wc -l <"${rules_v4}" | tr -d ' ')" == "1" ]]
jq -e '.rules == [{"family":4,"priority":32040,"source":"192.0.2.20/32","table":"main"}]' "$(xray_agent_network_policy_state_path)" >/dev/null

xray_agent_network_policy_cleanup
[[ ! -s "${rules_v4}" ]]
jq -e '.rules == []' "$(xray_agent_network_policy_state_path)" >/dev/null

printf '32040: from 198.51.100.99/32 lookup main\n' >"${rules_v4}"
if xray_agent_network_policy_reconcile_egress_policy "${policy}"; then
    exit 1
fi
grep -q '198.51.100.99/32' "${rules_v4}"
jq -e '.rules == []' "$(xray_agent_network_policy_state_path)" >/dev/null

printf 'network policy tests passed\n'
