if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_validate_non_empty() {
    [[ -n "$1" ]]
}

xray_agent_validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
}

xray_agent_validate_domain() {
    [[ "$1" =~ ^[A-Za-z0-9.-]+$ ]] && [[ "$1" == *.* ]]
}

xray_agent_validate_uuid() {
    [[ "$1" =~ ^[0-9a-fA-F-]{36}$ ]]
}

xray_agent_validate_path_segment() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

xray_agent_validate_csv() {
    [[ "$1" != *"  "* ]]
}
