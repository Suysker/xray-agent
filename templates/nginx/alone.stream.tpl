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

${NGINX_STREAM_EXTRA_UPSTREAMS}

    server {
${NGINX_STREAM_LISTEN_DIRECTIVES}
        ssl_preread on;
${NGINX_STREAM_PROXY_PROTOCOL_DIRECTIVE}
        proxy_pass ${XRAY_DOLLAR}backend_name;
    }
}
