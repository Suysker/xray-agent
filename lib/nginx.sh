#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_nginx_status_line() {
    local active_upstream host_header legacy_count site_mode proxy_mode masquerade_source
    active_upstream="$(xray_agent_nginx_active_upstream_url "https://huggingface.co")"
    host_header="$(xray_agent_nginx_active_host_header "${active_upstream}")"
    legacy_count="$(xray_agent_nginx_legacy_backend_count)"
    proxy_mode="$(xray_agent_nginx_frontdoor_proxy_protocol 2>/dev/null || printf 'auto')"
    masquerade_source="$(xray_agent_nginx_masquerade_source_label 2>/dev/null || printf '外部兜底')"
    if xray_agent_nginx_active_site_enabled; then
        site_mode="本机/自有站点"
    else
        site_mode="外部伪装站"
    fi
    printf '网站fallback: %s  来源=%s  upstream=%s  Host=%s  HTTPS透传=%s  前门PROXY=%s\n' "${site_mode}" "${masquerade_source}" "${active_upstream}" "${host_header}" "${legacy_count}" "${proxy_mode}"
}

updateRedirectNginxConf() {
    xray_agent_blank
    echoContent skyBlue "进度  $2/${totalProgress} : 配置镜像站点，默认使用huggingface官网"
    local accept_proxy_protocol="false"
    rm -f "${nginxConfigPath}default.conf"
    if declare -F xray_agent_cleanup_default_nginx_site >/dev/null 2>&1; then
        xray_agent_cleanup_default_nginx_site
    fi
    if [[ "$1" == "Vision" ]]; then
        xray_agent_render_nginx_alone_conf "$1" "https://huggingface.co"
    fi
    xray_agent_nginx_print_proxy_protocol_preflight
    if ([[ "${coreInstallType}" == "1" ]] && [[ "$1" == "Reality" ]]) || ([[ "${coreInstallType}" == "2" ]] && [[ "$1" == "Vision" ]]) || [[ "${coreInstallType}" == "3" ]]; then
        xray_agent_blank
        echoContent red "=============================================================="
        echoContent red "检测到能够共用443端口的条件。"
        echoContent red "=============================================================="
        if xray_agent_nginx_prompt_enable_frontdoor "启用后 Nginx stream 将接管 TCP/443 并分流到 Xray/HTTPS 后端。"; then
            reuse443="y"
        else
            reuse443="n"
        fi
        if [[ "${reuse443}" == "y" ]]; then
            if [[ "${Port}" == "443" ]]; then
                customPortFunction "Vision"
            fi
            if [[ "${RealityPort}" == "443" ]]; then
                customPortFunction "Reality"
            fi
        fi
    fi
    if [[ "$1" == "Vision" && "${Port}" != "443" && "${reuse443}" != "y" ]]; then
        xray_agent_blank
        echoContent red "=============================================================="
        echoContent yellow "检测到 TLS 后端端口不是 443。若已把现有网站迁到本机 upstream，可让 Nginx 前门接管公网 443 后转发到 Xray。"
        echoContent yellow "启用后 Xray 后端是否接收 PROXY protocol 将按上方 preflight 判定。"
        echoContent red "=============================================================="
        if xray_agent_nginx_prompt_enable_frontdoor "是否让 Nginx 前门接管公网 443？"; then
            reuse443="y"
        else
            reuse443="n"
        fi
    fi
    if [[ "${reuse443}" == "y" ]] && ! xray_agent_nginx_confirm_frontdoor_takeover; then
        reuse443="n"
    fi
    xray_agent_render_nginx_stream_conf "${reuse443}"
    if [[ "${reuse443}" == "y" ]]; then
        accept_proxy_protocol="$(xray_agent_nginx_resolved_proxy_protocol_bool)"
    fi
    export XRAY_AGENT_FRONTDOOR_PROXY_PROTOCOL="${accept_proxy_protocol}"
    xray_agent_nginx_capability_summary
    if ! xray_agent_nginx_test_config; then
        echoContent red " ---> nginx -t 失败，请检查 Nginx 是否支持 http_v2/grpc/stream/ssl_preread。"
        [[ -f /tmp/xray-agent-nginx-test.log ]] && tail -n 20 /tmp/xray-agent-nginx-test.log
        return 1
    fi
    handleNginx stop
    handleNginx start
}

xray_agent_nginx_update_default_upstream() {
    local input_upstream mirror_url updated_json
    read -r -p "请输入新的外部伪装站URL或域名[回车取消]:" input_upstream
    [[ -n "${input_upstream}" ]] || {
        echoContent yellow " ---> 已取消"
        return 0
    }
    mirror_url="$(xray_agent_nginx_normalize_upstream_url "${input_upstream}")"
    if ! xray_agent_nginx_validate_upstream_url "${mirror_url}"; then
        echoContent red " ---> URL 不合法，示例: https://www.example.com/"
        return 0
    fi
    echoContent yellow "将使用外部伪装站 ${mirror_url}。真实同域站点通常比外部镜像更自然。"
    xray_agent_confirm_action "确认继续？" "y" || return 0
    updated_json="$(xray_agent_nginx_reverse_proxy_json | jq --arg url "${mirror_url}" '
      .default_upstream.url = $url
      | .sites = ((.sites // []) | map(select(.mode != "http_fallback")))
    ')"
    xray_agent_nginx_apply_reverse_proxy_update "${updated_json}" auto
}

xray_agent_nginx_register_site_upstream() {
    local input_upstream site_url host_header updated_json server_name
    read -r -p "请输入本机/自有网站 upstream[例 http://127.0.0.1:8080，回车取消]:" input_upstream
    [[ -n "${input_upstream}" ]] || {
        echoContent yellow " ---> 已取消"
        return 0
    }
    site_url="$(xray_agent_nginx_normalize_upstream_url "${input_upstream}")"
    if ! xray_agent_nginx_validate_upstream_url "${site_url}"; then
        echoContent red " ---> upstream 不合法，示例: http://127.0.0.1:8080"
        return 0
    fi
    read -r -p "请输入转发 Host[回车使用 ${domain}]:" host_header
    host_header="${host_header:-${domain}}"
    if ! xray_agent_nginx_validate_host_header "${host_header}"; then
        echoContent red " ---> Host 不合法"
        return 0
    fi
    server_name="${domain:-default}"
    echoContent yellow "将把浏览器 fallback 转发到 ${site_url}，Host=${host_header}"
    echoContent yellow "提示: 如果这是已有真实网站，建议让该 upstream 返回与 ${domain} 对齐的内容和证书行为。"
    xray_agent_confirm_action "确认继续？" "y" || return 0
    updated_json="$(xray_agent_nginx_reverse_proxy_json | jq --arg server "${server_name}" --arg url "${site_url}" --arg host "${host_header}" '
      .sites = ((.sites // []) | map(select(.mode != "http_fallback" or .server_name != $server)) + [{
        server_name:$server,
        mode:"http_fallback",
        upstream:$url,
        host:$host,
        enabled:true
      }])
    ')"
    xray_agent_nginx_apply_reverse_proxy_update "${updated_json}" auto
}

xray_agent_nginx_add_legacy_https_backend() {
    local server_name target updated_json legacy_count proxy_protocol_choice proxy_protocol_status
    if [[ ! -f "${nginxConfigPath}alone.stream" ]]; then
        echoContent yellow " ---> 当前未检测到 443 前门 stream 配置；将先登记后端，启用前门时再参与分流。"
    fi
    read -r -p "请输入需要透传的站点 SNI[例 www.example.com，回车取消]:" server_name
    [[ -n "${server_name}" ]] || {
        echoContent yellow " ---> 已取消"
        return 0
    }
    if ! xray_agent_validate_domain "${server_name}"; then
        echoContent red " ---> 域名不合法"
        return 0
    fi
    read -r -p "请输入该站点后端地址[例 127.0.0.1:8443]:" target
    if ! xray_agent_nginx_validate_stream_target "${target}"; then
        echoContent red " ---> 后端地址不合法"
        return 0
    fi
    echoContent yellow "请选择该 HTTPS 后端的 PROXY protocol 支持状态:"
    echoContent yellow "1. supported（已确认支持/监听 proxy_protocol）"
    echoContent yellow "2. unsupported（确认不支持）"
    echoContent yellow "3. unknown（未知，默认按不安全处理）"
    read -r -p "请输入[默认3]:" proxy_protocol_choice
    case "${proxy_protocol_choice:-3}" in
        1) proxy_protocol_status="supported" ;;
        2) proxy_protocol_status="unsupported" ;;
        *) proxy_protocol_status="unknown" ;;
    esac
    if [[ "${proxy_protocol_status}" != "supported" ]]; then
        echoContent yellow "提示: 只要存在 unknown/unsupported HTTPS 后端，auto 会推荐关闭全局前门 PROXY。"
    fi
    xray_agent_confirm_action "确认登记该 HTTPS 后端？" "y" || return 0
    updated_json="$(xray_agent_nginx_reverse_proxy_json | jq --arg server "${server_name}" --arg target "${target}" --arg proxy_protocol "${proxy_protocol_status}" '
        .sites = ((.sites // []) | map(select(.mode != "stream_tls" or .server_name != $server)) + [{
            server_name:$server,
            mode:"stream_tls",
            upstream:$target,
            proxy_protocol:$proxy_protocol,
            enabled:true
        }])
    ')"
    xray_agent_nginx_apply_reverse_proxy_update "${updated_json}" y || return 1
    legacy_count="$(xray_agent_nginx_legacy_backend_count)"
    echoContent yellow " ---> legacy HTTPS 后端数量: ${legacy_count}"
}

xray_agent_nginx_remove_legacy_https_backend() {
    local proxy_json count selected_index selected_server updated_json
    proxy_json="$(xray_agent_nginx_reverse_proxy_json)"
    count="$(printf '%s\n' "${proxy_json}" | jq -r '[.sites[]? | select(.enabled == true and .mode == "stream_tls")] | length')"
    if [[ "${count}" == "0" ]]; then
        echoContent yellow " ---> 暂无 legacy HTTPS 后端"
        return 0
    fi
    printf '%s\n' "${proxy_json}" | jq -r '.sites[]? | select(.enabled == true and .mode == "stream_tls") | "\(.server_name) -> \(.upstream) proxy_protocol=\(.proxy_protocol)"' | awk '{print NR"."$0}'
    read -r -p "请输入要删除的编号:" selected_index
    if ! [[ "${selected_index}" =~ ^[0-9]+$ ]] || [[ "${selected_index}" -lt 1 || "${selected_index}" -gt "${count}" ]]; then
        echoContent red " ---> 选择错误"
        return 0
    fi
    selected_server="$(printf '%s\n' "${proxy_json}" | jq -r --argjson idx "$((selected_index - 1))" '[.sites[]? | select(.enabled == true and .mode == "stream_tls")][$idx].server_name')"
    xray_agent_confirm_action "确认删除 HTTPS 后端 ${selected_server}？" "n" || return 0
    updated_json="$(printf '%s\n' "${proxy_json}" | jq --arg server "${selected_server}" '.sites = ((.sites // []) | map(select(.mode != "stream_tls" or .server_name != $server)))')"
    xray_agent_nginx_apply_reverse_proxy_update "${updated_json}" auto
}

xray_agent_nginx_print_proxy_protocol_affected() {
    local configfile tag raw_accept sock_accept
    echoContent skyBlue "-------------------------受影响后端-----------------------------"
    while IFS= read -r configfile; do
        [[ -f "${configfile}" ]] || continue
        tag="$(jq -r '.inbounds[0].tag // empty' "${configfile}" 2>/dev/null | tr -d '\r')"
        raw_accept="$(jq -r '.inbounds[0].streamSettings.rawSettings.acceptProxyProtocol // false' "${configfile}" 2>/dev/null | tr -d '\r')"
        sock_accept="$(jq -r '.inbounds[0].streamSettings.sockopt.acceptProxyProtocol // false' "${configfile}" 2>/dev/null | tr -d '\r')"
        echoContent yellow "Xray: ${configfile##*/} tag=${tag:-无} raw=${raw_accept} sockopt=${sock_accept}"
    done < <(xray_agent_nginx_xray_frontdoor_config_files)
    xray_agent_nginx_reverse_proxy_json | jq -r '
      .sites[]?
      | select(.enabled == true and .mode == "stream_tls")
      | "HTTPS透传: \(.server_name) -> \(.upstream) proxy_protocol=\(.proxy_protocol)"' |
        while IFS= read -r line; do echoContent yellow "${line}"; done
}

xray_agent_nginx_preflight_guide() {
    xray_agent_nginx_print_proxy_protocol_preflight
    echoContent skyBlue "-------------------------接入建议-----------------------------"
    echoContent yellow "脚本只维护 alone.conf、alone.stream 和 Xray inbound，不会自动重写宝塔、1Panel、OpenResty、Caddy、Apache 配置。"
    echoContent yellow "已有真实网站建议迁移到本机 HTTP upstream，例如 http://127.0.0.1:8080，再在本菜单注册为 fallback。"
    echoContent yellow "HTTPS SNI 透传后端只有在确认支持 PROXY protocol 时，才适合把全局前门 PROXY 开启。"
}

xray_agent_nginx_switch_frontdoor_proxy_protocol() {
    local selected_mode current_mode result_json updated_json
    result_json="$(xray_agent_nginx_resolved_proxy_protocol_json)"
    current_mode="$(printf '%s\n' "${result_json}" | jq -r '.configured')"
    xray_agent_nginx_print_proxy_protocol_preflight
    xray_agent_nginx_print_proxy_protocol_affected
    echoContent yellow "可选模式: auto / on / off"
    read -r -p "请输入新的前门 PROXY 模式[回车保持 ${current_mode}]:" selected_mode
    selected_mode="${selected_mode:-${current_mode}}"
    case "${selected_mode}" in
        auto | on | off) ;;
        *)
            echoContent red " ---> 模式不合法"
            return 0
            ;;
    esac
    result_json="$(xray_agent_nginx_proxy_protocol_recommendation_json | jq -c --arg configured "${selected_mode}" '
      .configured = $configured
      | if $configured == "on" then
          . + {resolved:"on", resolved_reason:"用户配置前门 PROXY=on"}
        elif $configured == "off" then
          . + {resolved:"off", resolved_reason:"用户配置前门 PROXY=off"}
        else
          . + {resolved:.recommended, resolved_reason:.reason}
        end')"
    echoContent yellow "将设置前门 PROXY: ${selected_mode}，当前生效: $(printf '%s\n' "${result_json}" | jq -r '.resolved')"
    xray_agent_confirm_action "确认同步重渲染 Nginx stream 和 Xray inbound？" "y" || return 0
    updated_json="$(xray_agent_nginx_reverse_proxy_json | jq --arg mode "${selected_mode}" '
      .frontdoor.proxy_protocol = $mode
      | .frontdoor.last_reason = "menu"
    ')"
    xray_agent_nginx_apply_reverse_proxy_update "${updated_json}" auto
}

xray_agent_nginx_status() {
    xray_agent_blank
    echoContent skyBlue "-------------------------网站/反代状态-----------------------"
    echoContent yellow "$(xray_agent_nginx_status_line)"
    echoContent yellow "Nginx配置目录: ${nginxConfigPath}"
    echoContent yellow "前门stream: $([[ -f "${nginxConfigPath}alone.stream" ]] && printf '已启用' || printf '未启用')"
    if [[ -f "$(xray_agent_nginx_reverse_proxy_file)" ]]; then
        echoContent yellow "反代注册文件: $(xray_agent_nginx_reverse_proxy_file)"
    else
        echoContent yellow "反代注册文件: 未创建"
    fi
    xray_agent_nginx_print_proxy_protocol_preflight
    xray_agent_nginx_reverse_proxy_json | jq -r '
      .sites[]?
      | select(.enabled == true)
      | if .mode == "http_fallback" then
          "HTTP fallback: \(.server_name) -> \(.upstream) Host=\(.host)"
        else
          "legacy HTTPS: \(.server_name) -> \(.upstream) proxy_protocol=\(.proxy_protocol)"
        end' | while IFS= read -r line; do echoContent yellow "${line}"; done
}

xray_agent_nginx_manage_menu() {
    if [[ "${coreInstallType}" != "1" ]] && [[ "${coreInstallType}" != "3" ]]; then
        xray_agent_error " ---> 未安装，请使用脚本安装"
    fi
    local selected_item
    xray_agent_tool_status_header "网站/反代管理"
    xray_agent_nginx_status
    echoContent red "=============================================================="
    echoContent yellow "1.查看网站/反代状态"
    echoContent yellow "2.注册本机/自有网站 upstream"
    echoContent yellow "3.修改外部伪装站 upstream"
    echoContent yellow "4.添加 legacy HTTPS SNI 后端"
    echoContent yellow "5.删除 legacy HTTPS SNI 后端"
    echoContent yellow "6.测试并重载 Nginx"
    echoContent yellow "7.检测现有网站/面板接入建议"
    echoContent yellow "8.切换前门 PROXY 模式"
    echoContent red "=============================================================="
    read -r -p "请输入:" selected_item
    case "${selected_item}" in
        1) xray_agent_nginx_status ;;
        2) xray_agent_nginx_register_site_upstream ;;
        3) xray_agent_nginx_update_default_upstream ;;
        4) xray_agent_nginx_add_legacy_https_backend ;;
        5) xray_agent_nginx_remove_legacy_https_backend ;;
        6) xray_agent_nginx_apply_with_rollback auto ;;
        7) xray_agent_nginx_preflight_guide ;;
        8) xray_agent_nginx_switch_frontdoor_proxy_protocol ;;
        *) echoContent red " ---> 选择错误" ;;
    esac
}

updateNginxBlog() {
    xray_agent_nginx_manage_menu "$@"
}
