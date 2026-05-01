server {
    listen ${NGINX_HTTP_PORT};
    server_name ${SERVER_NAME};

    client_header_timeout ${NGINX_CLIENT_HEADER_TIMEOUT};
    client_body_timeout ${NGINX_CLIENT_BODY_TIMEOUT};
    keepalive_timeout ${NGINX_KEEPALIVE_TIMEOUT};

    location ${NGINX_XHTTP_PATH} {
        grpc_pass grpc://${NGINX_XHTTP_GRPC_TARGET};
        grpc_set_header Host ${XRAY_DOLLAR}host;
        grpc_set_header X-Real-IP ${XRAY_DOLLAR}proxy_protocol_addr;
        grpc_set_header X-Forwarded-For ${XRAY_DOLLAR}proxy_add_x_forwarded_for;
        grpc_set_header X-Forwarded-Proto ${XRAY_DOLLAR}scheme;
        grpc_set_header X-Forwarded-Host ${XRAY_DOLLAR}host;
        grpc_set_header X-Forwarded-Port ${XRAY_DOLLAR}server_port;
        grpc_read_timeout ${NGINX_GRPC_TIMEOUT};
        grpc_send_timeout ${NGINX_GRPC_TIMEOUT};
        grpc_socket_keepalive on;
        client_max_body_size 0;
    }

    location / {
        sub_filter ${XRAY_DOLLAR}proxy_host ${XRAY_DOLLAR}host;
        sub_filter_once off;
        proxy_pass ${UPSTREAM_URL};
        proxy_set_header Host ${UPSTREAM_HOST_HEADER};
        proxy_http_version 1.1;
        proxy_cache_bypass ${XRAY_DOLLAR}http_upgrade;
        proxy_ssl_server_name on;
        proxy_ssl_name ${UPSTREAM_TLS_NAME};
        proxy_ssl_protocols TLSv1.2 TLSv1.3;
        proxy_set_header Upgrade ${XRAY_DOLLAR}http_upgrade;
        proxy_set_header X-Real-IP ${XRAY_DOLLAR}proxy_protocol_addr;
        proxy_set_header X-Forwarded-For ${XRAY_DOLLAR}proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto ${XRAY_DOLLAR}scheme;
        proxy_set_header X-Forwarded-Host ${XRAY_DOLLAR}host;
        proxy_set_header X-Forwarded-Port ${XRAY_DOLLAR}server_port;
        proxy_connect_timeout ${NGINX_PROXY_CONNECT_TIMEOUT};
        proxy_send_timeout ${NGINX_PROXY_TIMEOUT};
        proxy_read_timeout ${NGINX_PROXY_TIMEOUT};
    }
}
