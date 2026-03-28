stream {
    map ${XRAY_DOLLAR}ssl_preread_server_name ${XRAY_DOLLAR}backend_name {
        default ${NGINX_STREAM_DEFAULT_TARGET};
${NGINX_STREAM_SERVER_NAME_MAP}
    }

    upstream vision_backend {
        server ${NGINX_STREAM_VISION_TARGET};
    }

    upstream reality_backend {
        server ${NGINX_STREAM_REALITY_TARGET};
    }

    server {
        listen ${NGINX_STREAM_PORT};
        listen [::]:${NGINX_STREAM_PORT};
        ssl_preread on;
        proxy_protocol on;
        proxy_pass ${XRAY_DOLLAR}backend_name;
    }
}
