if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

installCronTLS() {
    if [[ -f "/etc/xray-agent/install.sh" ]]; then
        crontab -l >/etc/xray-agent/backup_crontab.cron
        historyCrontab=$(sed '/install.sh/d;/acme.sh/d' /etc/xray-agent/backup_crontab.cron)
        echo "${historyCrontab}" >/etc/xray-agent/backup_crontab.cron
        echo "30 1 * * * /bin/bash /etc/xray-agent/install.sh RenewTLS >> /etc/xray-agent/crontab_tls.log 2>&1" >>/etc/xray-agent/backup_crontab.cron
        crontab /etc/xray-agent/backup_crontab.cron
    else
        crontab -l | grep -v 'install.sh RenewTLS' | crontab -
    fi
}

auto_update_geodata() {
    if [[ -f "/etc/xray-agent/xray/xray" ]] || [[ -f "/etc/xray-agent/xray/geosite.dat" ]] || [[ -f "/etc/xray-agent/xray/geoip.dat" ]]; then
        cat >/etc/xray-agent/auto_update_geodata.sh <<EOF
#!/bin/sh
wget -O /etc/xray-agent/xray/geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat && wget -O /etc/xray-agent/xray/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat && systemctl restart xray
EOF
        chmod +x /etc/xray-agent/auto_update_geodata.sh
        crontab -l >/etc/xray-agent/backup_crontab.cron
        historyCrontab=$(sed '/auto_update_geodata.sh/d' /etc/xray-agent/backup_crontab.cron)
        echo "${historyCrontab}" >/etc/xray-agent/backup_crontab.cron
        echo "30 1 * * 1 /bin/bash /etc/xray-agent/auto_update_geodata.sh >> /etc/xray-agent/crontab_geo.log 2>&1" >>/etc/xray-agent/backup_crontab.cron
        crontab /etc/xray-agent/backup_crontab.cron
    else
        crontab -l | grep -v 'auto_update_geodata.sh' | crontab -
    fi
}
