xray_agent_firewall_comment() {
    echo "xray-agent"
}

allowPort() {
    local port="$1"
    local type="${2:-tcp}"
    if systemctl status netfilter-persistent 2>/dev/null | grep -q "active (exited)"; then
        local update_firewall_status=
        if ! iptables -L | grep -q "${port}"; then
            update_firewall_status=true
            iptables -I INPUT -p "${type}" --dport "${port}" -m comment --comment "allow ${port}($(xray_agent_firewall_comment))" -j ACCEPT
        fi
        if ! ip6tables -L | grep -q "${port}"; then
            update_firewall_status=true
            ip6tables -I INPUT -p "${type}" --dport "${port}" -m comment --comment "allow ${port}($(xray_agent_firewall_comment))" -j ACCEPT
        fi
        if [[ "${update_firewall_status}" == "true" ]]; then
            netfilter-persistent save
        fi
    elif systemctl status ufw 2>/dev/null | grep -q "active (exited)"; then
        if ufw status | grep -q "Status: active" && ! ufw status | grep -q "${port}/${type}"; then
            sudo ufw allow "${port}/${type}"
            sudo ufw allow from any to any proto ipv6 "${type}" port "${port}"
        fi
    elif systemctl status firewalld 2>/dev/null | grep -q "active (running)"; then
        local update_firewall_status=
        if ! firewall-cmd --list-ports --permanent | grep -qw "${port}/${type}"; then
            update_firewall_status=true
            firewall-cmd --zone=public --add-port="${port}/${type}" --permanent
        fi
        if [[ "${update_firewall_status}" == "true" ]]; then
            firewall-cmd --reload
        fi
    fi
}

xray_agent_allow_port_safe() {
    local port="$1"
    local protocol="${2:-tcp}"
    allowPort "${port}" "${protocol}"
}
