if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_download_geodata() {
    local version
    version=$(curl -s https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases | jq -r '.[]|.tag_name' | head -1)
    rm /etc/xray-agent/xray/geo* >/dev/null 2>&1
    wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geosite.dat"
    wget -c -q --show-progress -P /etc/xray-agent/xray/ "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/geoip.dat"
}
