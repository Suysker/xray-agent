if [[ -z "${XRAY_AGENT_PROJECT_ROOT}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_lock_path() {
    echo "/tmp/xray-agent.lock"
}

xray_agent_lock_acquire() {
    exec 9>"$(xray_agent_lock_path)"
    flock -n 9
}

xray_agent_lock_release() {
    flock -u 9 2>/dev/null || true
    rm -f "$(xray_agent_lock_path)"
}
