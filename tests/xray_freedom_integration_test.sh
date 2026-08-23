#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
xray_binary="${XRAY_AGENT_TEST_XRAY_BINARY:-${1:-}}"
[[ -x "${xray_binary}" ]] || {
    printf 'usage: XRAY_AGENT_TEST_XRAY_BINARY=/path/to/xray %s\n' "$0" >&2
    exit 2
}

temp_dir="$(mktemp -d)"
test_octet=$((($$ % 200) + 20))
ipv4_address="203.0.114.${test_octet}"
ipv6_address="2001:db9::${test_octet}"
vless_port=$((20000 + ($$ % 10000)))
socks_port=$((vless_port + 1))
target_port=$((vless_port + 2))
private_port=$((vless_port + 3))
uuid=11111111-1111-4111-8111-111111111111
server_pid=
client_pid=
ipv4_server_pid=
ipv6_server_pid=
private_server_pid=

cleanup() {
    for process_id in "${client_pid}" "${server_pid}" "${ipv4_server_pid}" "${ipv6_server_pid}" "${private_server_pid}"; do
        [[ -n "${process_id}" ]] && kill "${process_id}" >/dev/null 2>&1 || true
    done
    wait >/dev/null 2>&1 || true
    ip -4 address del "${ipv4_address}/32" dev lo >/dev/null 2>&1 || true
    ip -6 address del "${ipv6_address}/128" dev lo >/dev/null 2>&1 || true
    rm -rf -- "${temp_dir}"
}
trap cleanup EXIT

export XRAY_AGENT_PROJECT_ROOT="${repo_root}"
source "${repo_root}/lib/common.sh"
source "${repo_root}/lib/core.sh"
source "${repo_root}/lib/egress.sh"
source "${repo_root}/lib/routing.sh"
ctlPath="${xray_binary}"

ip -4 address add "${ipv4_address}/32" dev lo
ip -6 address add "${ipv6_address}/128" dev lo

start_http_server() {
    local family="$1"
    local address="$2"
    local port="$3"
    local response="$4"
    python3 -u - "${family}" "${address}" "${port}" "${response}" >"${temp_dir}/${response}-server.log" 2>&1 <<'PY' &
import socket
import sys

family_name, address, port, response = sys.argv[1:]
family = socket.AF_INET6 if family_name == "ipv6" else socket.AF_INET
server = socket.socket(family, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
if family == socket.AF_INET6:
    server.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
server.bind((address, int(port)))
server.listen(16)
while True:
    connection, _ = server.accept()
    with connection:
        connection.recv(4096)
        body = response.encode()
        connection.sendall(
            b"HTTP/1.1 200 OK\r\n"
            + f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n".encode()
            + body
        )
PY
    printf '%s\n' "$!"
}

wait_for_tcp() {
    local port="$1"
    local attempt
    for attempt in $(seq 1 50); do
        if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
            exec 3>&-
            return 0
        fi
        sleep 0.1
    done
    return 1
}

write_server_config() {
    local preference="$1"
    local outbound_tag="system-auto-${preference}-first"
    local auto_outbound blackhole_outbound private_rule default_tcp_rule
    auto_outbound="$(xray_agent_egress_outbound_json "${outbound_tag}" auto "${preference}")"
    blackhole_outbound="$(xray_agent_egress_blackhole_outbound_json)"
    private_rule="$(xray_agent_private_destination_rule_json)"
    default_tcp_rule="$(xray_agent_routing_rule_json '{}' tcp "${outbound_tag}")"
    jq -nc \
        --argjson autoOutbound "${auto_outbound}" \
        --argjson blackholeOutbound "${blackhole_outbound}" \
        --argjson privateRule "${private_rule}" \
        --argjson defaultTcpRule "${default_tcp_rule}" \
        --arg uuid "${uuid}" \
        --arg ipv4 "${ipv4_address}" \
        --arg ipv6 "${ipv6_address}" \
        --argjson vlessPort "${vless_port}" \
        '{
          log:{loglevel:"debug"},
          dns:{hosts:{"dual.xray.test":[$ipv4,$ipv6],"private.xray.test":"127.0.0.1"}},
          inbounds:[{
            listen:"127.0.0.1",
            port:$vlessPort,
            protocol:"vless",
            settings:{clients:[{id:$uuid}],decryption:"none"}
          }],
          outbounds:[$autoOutbound,$blackholeOutbound],
          routing:{domainStrategy:"IPOnDemand",rules:[$privateRule,$defaultTcpRule]}
        }' >"${temp_dir}/server.json"
}

ipv4_server_pid="$(start_http_server ipv4 "${ipv4_address}" "${target_port}" ipv4)"
ipv6_server_pid="$(start_http_server ipv6 "${ipv6_address}" "${target_port}" ipv6)"
private_server_pid="$(start_http_server ipv4 127.0.0.1 "${private_port}" private)"
sleep 0.2

write_server_config ipv4

jq -nc \
    --arg uuid "${uuid}" \
    --argjson vlessPort "${vless_port}" \
    --argjson socksPort "${socks_port}" \
    '{
      log:{loglevel:"warning"},
      inbounds:[{listen:"127.0.0.1",port:$socksPort,protocol:"socks",settings:{udp:false}}],
      outbounds:[{
        protocol:"vless",
        tag:"server",
        settings:{vnext:[{address:"127.0.0.1",port:$vlessPort,users:[{id:$uuid,encryption:"none"}]}]}
      }]
    }' >"${temp_dir}/client.json"

"${xray_binary}" run -test -config "${temp_dir}/server.json" >/dev/null
"${xray_binary}" run -test -config "${temp_dir}/client.json" >/dev/null
"${xray_binary}" run -config "${temp_dir}/server.json" >"${temp_dir}/server.log" 2>&1 &
server_pid=$!
"${xray_binary}" run -config "${temp_dir}/client.json" >"${temp_dir}/client.log" 2>&1 &
client_pid=$!
wait_for_tcp "${socks_port}"

response="$(curl -fsS --max-time 5 --socks5-hostname "127.0.0.1:${socks_port}" "http://dual.xray.test:${target_port}/")"
[[ "${response}" == "ipv4" ]]

kill "${ipv4_server_pid}"
wait "${ipv4_server_pid}" 2>/dev/null || true
ipv4_server_pid=
response="$(curl -fsS --max-time 8 --socks5-hostname "127.0.0.1:${socks_port}" "http://dual.xray.test:${target_port}/")"
[[ "${response}" == "ipv6" ]]

if curl -fsS --max-time 3 --socks5-hostname "127.0.0.1:${socks_port}" "http://private.xray.test:${private_port}/" >/dev/null 2>&1; then
    printf 'private destination was not blocked\n' >&2
    exit 1
fi

ipv4_server_pid="$(start_http_server ipv4 "${ipv4_address}" "${target_port}" ipv4)"
kill "${server_pid}"
wait "${server_pid}" 2>/dev/null || true
server_pid=
write_server_config ipv6
"${xray_binary}" run -test -config "${temp_dir}/server.json" >/dev/null
"${xray_binary}" run -config "${temp_dir}/server.json" >"${temp_dir}/server-ipv6-first.log" 2>&1 &
server_pid=$!
wait_for_tcp "${vless_port}"
response="$(curl -fsS --max-time 5 --socks5-hostname "127.0.0.1:${socks_port}" "http://dual.xray.test:${target_port}/")"
[[ "${response}" == "ipv6" ]]

kill "${ipv6_server_pid}"
wait "${ipv6_server_pid}" 2>/dev/null || true
ipv6_server_pid=
response="$(curl -fsS --max-time 8 --socks5-hostname "127.0.0.1:${socks_port}" "http://dual.xray.test:${target_port}/")"
[[ "${response}" == "ipv4" ]]

printf 'xray freedom integration tests passed: %s\n' "$(xray_agent_xray_version_number)"
