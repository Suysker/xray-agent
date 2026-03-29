if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

xray_agent_render_nginx_stream_conf() {
    local reuse_443="$1"
    if [[ "${reuse_443}" != "y" ]]; then
        rm -f "${nginxConfigPath}alone.stream"
        return 0
    fi

    local formattedRealityServerNames realityDomainConfig=""
    formattedRealityServerNames=$(echo "${RealityServerNames}" | sed 's/"//g' | sed 's/,/ /g')
    for name in $formattedRealityServerNames; do
        realityDomainConfig="${realityDomainConfig}        ${name} reality_backend;\n"
    done

    export NGINX_STREAM_DEFAULT_TARGET="vision_backend"
    export NGINX_STREAM_SERVER_NAME_MAP="        ${domain} vision_backend;\n${realityDomainConfig}"
    export NGINX_STREAM_VISION_TARGET="127.0.0.1:${Port}"
    export NGINX_STREAM_REALITY_TARGET="127.0.0.1:${RealityPort:-443}"
    export NGINX_STREAM_PORT="443"
    export XRAY_DOLLAR='$'
    xray_agent_render_template "${XRAY_AGENT_TEMPLATE_DIR}/nginx/alone.stream.tpl" "${nginxConfigPath}alone.stream"
}
