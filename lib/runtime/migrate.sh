if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_run_legacy_migrations() {
    mkdir -p /etc/xray-agent/tls /etc/xray-agent/xray/conf
    if [[ -f "/etc/xray-agent/xray/conf/10_outbounds.json" ]] && [[ ! -f "/etc/xray-agent/xray/conf/10_ipv4_outbounds.json" ]]; then
        mv /etc/xray-agent/xray/conf/10_outbounds.json /etc/xray-agent/xray/conf/10_ipv4_outbounds.json
    fi
}
