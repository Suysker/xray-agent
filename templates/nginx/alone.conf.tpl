server {
    listen ${NGINX_HTTP_PORT};
    server_name ${SERVER_NAME};

    client_header_timeout 1071906480m;
    keepalive_timeout 1071906480m;

    location ${NGINX_XHTTP_PATH} {
        proxy_pass http://127.0.0.1:31305;
        proxy_http_version 1.1;
        proxy_set_header Host ${XRAY_DOLLAR}host;
        proxy_set_header X-Real-IP ${XRAY_DOLLAR}proxy_protocol_addr;
        proxy_set_header X-Forwarded-For ${XRAY_DOLLAR}proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto ${XRAY_DOLLAR}scheme;
        proxy_set_header X-Forwarded-Host ${XRAY_DOLLAR}host;
        proxy_set_header X-Forwarded-Port ${XRAY_DOLLAR}server_port;
        proxy_read_timeout 1071906480m;
        proxy_send_timeout 1071906480m;
        client_body_timeout 1071906480m;
        client_max_body_size 0;
    }

    location / {
        add_header Strict-Transport-Security "max-age=15552000; preload" always;
        sub_filter ${XRAY_DOLLAR}proxy_host ${XRAY_DOLLAR}host;
        sub_filter_once off;
        proxy_pass ${UPSTREAM_URL};
        proxy_set_header Host ${XRAY_DOLLAR}proxy_host;
        proxy_http_version 1.1;
        proxy_cache_bypass ${XRAY_DOLLAR}http_upgrade;
        proxy_ssl_server_name on;
        proxy_ssl_name ${XRAY_DOLLAR}proxy_host;
        proxy_ssl_protocols TLSv1.2 TLSv1.3;
        proxy_set_header Upgrade ${XRAY_DOLLAR}http_upgrade;
        proxy_set_header X-Real-IP ${XRAY_DOLLAR}proxy_protocol_addr;
        proxy_set_header X-Forwarded-For ${XRAY_DOLLAR}proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto ${XRAY_DOLLAR}scheme;
        proxy_set_header X-Forwarded-Host ${XRAY_DOLLAR}host;
        proxy_set_header X-Forwarded-Port ${XRAY_DOLLAR}server_port;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
