if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_apply_sysctl_defaults() {
    if ! grep -q "net.ipv4.tcp_fastopen=3" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv4.tcp_fastopen=3" >>/etc/sysctl.conf
    fi
    sysctl -p >/dev/null 2>&1 || true
}
