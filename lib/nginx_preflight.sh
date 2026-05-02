#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_nginx_script_stream_proxy_protocol_state() {
    local stream_file="${nginxConfigPath:-/etc/nginx/conf.d/}alone.stream"
    if [[ ! -f "${stream_file}" ]]; then
        printf 'absent\n'
    elif grep -Eq '^[[:space:]]*proxy_protocol[[:space:]]+on[[:space:]]*;' "${stream_file}"; then
        printf 'on\n'
    else
        printf 'off\n'
    fi
}

xray_agent_nginx_scan_dirs() {
    if [[ -n "${XRAY_AGENT_NGINX_SCAN_DIRS:-}" ]]; then
        printf '%s\n' "${XRAY_AGENT_NGINX_SCAN_DIRS}" | tr ':' '\n' | sed '/^$/d'
        return 0
    fi
    printf '%s\n' \
        "${nginxConfigPath:-/etc/nginx/conf.d/}" \
        /etc/nginx/conf.d \
        /etc/nginx/sites-enabled \
        /etc/nginx/sites-available \
        /etc/openresty/conf.d \
        /usr/local/openresty/nginx/conf \
        /usr/local/openresty/nginx/conf/conf.d \
        /www/server/panel/vhost/nginx \
        /www/server/nginx/conf \
        /opt/1panel/apps/openresty/openresty/conf \
        /opt/1panel/apps/openresty/openresty/conf/conf.d \
        /opt/1panel/apps/openresty/openresty/www/sites \
        /etc/caddy \
        /etc/apache2/sites-enabled \
        /etc/apache2/sites-available \
        /etc/httpd/conf.d
}

xray_agent_nginx_config_files() {
    local scan_dir
    while IFS= read -r scan_dir; do
        [[ -n "${scan_dir}" && -d "${scan_dir}" ]] || continue
        find "${scan_dir}" -maxdepth 4 -type f \( -name "*.conf" -o -name "Caddyfile" -o -name "*.caddy" \) 2>/dev/null
    done < <(xray_agent_nginx_scan_dirs) | awk '!seen[$0]++'
}

xray_agent_nginx_is_script_config_file() {
    local config_file="$1"
    [[ "${config_file}" == "${nginxConfigPath:-/etc/nginx/conf.d/}alone.conf" ||
        "${config_file}" == "${nginxConfigPath:-/etc/nginx/conf.d/}alone.stream" ]]
}

xray_agent_nginx_file_has_proxy_protocol_listen() {
    local config_file="$1"
    awk '
      {
        line = tolower($0)
      }
      line ~ /^[[:space:]]*listen[[:space:]]/ &&
      line ~ /proxy_protocol/ &&
      line ~ /(^|[^0-9])443([^0-9]|$)/ {
        found = 1
      }
      END {
        exit(found ? 0 : 1)
      }
    ' "${config_file}"
}

xray_agent_nginx_file_has_https_listen() {
    local config_file="$1"
    grep -Eiq '^[[:space:]]*listen[[:space:]]+443([^0-9]|$)|^[[:space:]]*listen[[:space:]][^;#]*[^0-9]443([^0-9]|$)|<VirtualHost[[:space:]][^>]*:443|^[^#]*:443[[:space:]]*\{' "${config_file}"
}

xray_agent_nginx_matching_config_files() {
    local mode="$1"
    local config_file
    while IFS= read -r config_file; do
        [[ -n "${config_file}" && -r "${config_file}" ]] || continue
        xray_agent_nginx_is_script_config_file "${config_file}" && continue
        case "${mode}" in
            proxy_protocol)
                xray_agent_nginx_file_has_proxy_protocol_listen "${config_file}" && printf '%s\n' "${config_file}"
                ;;
            https)
                xray_agent_nginx_file_has_https_listen "${config_file}" && printf '%s\n' "${config_file}"
                ;;
        esac
    done < <(xray_agent_nginx_config_files)
}

xray_agent_nginx_detect_frontends_json() {
    {
        [[ -d /www/server/panel ]] && printf '宝塔面板\n'
        [[ -d /opt/1panel ]] && printf '1Panel\n'
        { command -v openresty >/dev/null 2>&1 || [[ -d /usr/local/openresty || -d /etc/openresty ]]; } && printf 'OpenResty\n'
        { command -v caddy >/dev/null 2>&1 || [[ -d /etc/caddy ]]; } && printf 'Caddy\n'
        { command -v apache2 >/dev/null 2>&1 || command -v httpd >/dev/null 2>&1 || [[ -d /etc/apache2 || -d /etc/httpd ]]; } && printf 'Apache\n'
    } | awk '!seen[$0]++' | jq -R -s 'split("\n") | map(select(length > 0))'
}

xray_agent_nginx_stream_site_stats_json() {
    xray_agent_nginx_reverse_proxy_json | jq -c '
      [.sites[]? | select(.enabled == true and .mode == "stream_tls")] as $stream
      | [.sites[]? | select(.enabled == true and .mode == "http_fallback")] as $http
      | {
          stream_total: ($stream | length),
          stream_supported: ($stream | map(select(.proxy_protocol == "supported")) | length),
          stream_unknown_or_unsupported: ($stream | map(select(.proxy_protocol != "supported")) | length),
          http_total: ($http | length)
        }'
}

xray_agent_nginx_preflight_json() {
    local proxy_json configured script_state port443_owner proxy_files https_files panels stats
    proxy_json="$(xray_agent_nginx_reverse_proxy_json)"
    configured="$(printf '%s\n' "${proxy_json}" | jq -r '.frontdoor.proxy_protocol // "auto"')"
    script_state="$(xray_agent_nginx_script_stream_proxy_protocol_state)"
    port443_owner="$(xray_agent_port_owner TCP 443 2>/dev/null || printf '未检测\n')"
    proxy_files="$(xray_agent_nginx_matching_config_files proxy_protocol | jq -R -s 'split("\n") | map(select(length > 0))')"
    https_files="$(xray_agent_nginx_matching_config_files https | jq -R -s 'split("\n") | map(select(length > 0))')"
    panels="$(xray_agent_nginx_detect_frontends_json)"
    stats="$(xray_agent_nginx_stream_site_stats_json)"
    jq -nc \
        --arg configured "${configured}" \
        --arg script_state "${script_state}" \
        --arg port443_owner "${port443_owner}" \
        --argjson proxy_files "${proxy_files}" \
        --argjson https_files "${https_files}" \
        --argjson panels "${panels}" \
        --argjson stats "${stats}" \
        '{
          configured:$configured,
          script_stream:$script_state,
          port443_owner:$port443_owner,
          proxy_protocol_config_files:$proxy_files,
          https_config_files:$https_files,
          detected_frontends:$panels,
          site_stats:$stats
        }'
}

xray_agent_nginx_proxy_protocol_recommendation_json() {
    local preflight_json
    preflight_json="$(xray_agent_nginx_preflight_json)"
    printf '%s\n' "${preflight_json}" | jq -c '
      . as $p
      | ($p.proxy_protocol_config_files | length) as $proxy_configs
      | ($p.https_config_files | length) as $https_configs
      | ($p.site_stats.stream_total // 0) as $stream_total
      | ($p.site_stats.stream_unknown_or_unsupported // 0) as $stream_unsafe
      | if $p.script_stream == "on" then
          $p + {recommended:"on", source:"alone.stream", reason:"已有脚本托管 alone.stream 明确启用 proxy_protocol on，继续开启"}
        elif $p.script_stream == "off" then
          $p + {recommended:"off", source:"alone.stream", reason:"已有脚本托管 alone.stream 未启用 proxy_protocol on，继续关闭"}
        elif $proxy_configs > 0 then
          $p + {recommended:"on", source:"nginx-config", reason:"检测到现有网站/面板配置已在 443 listen 中启用 proxy_protocol，默认开启"}
        elif $stream_unsafe > 0 then
          $p + {recommended:"off", source:"registered-site", reason:"检测到已注册 HTTPS 后端未声明支持 PROXY protocol，避免打坏后端"}
        elif $stream_total > 0 and $https_configs == 0 then
          $p + {recommended:"on", source:"registered-site", reason:"已注册 HTTPS 后端全部声明支持 PROXY protocol，默认开启"}
        elif $stream_total == 0 and $https_configs == 0 then
          $p + {recommended:"on", source:"clean-or-http-fallback", reason:"未检测到普通 HTTPS 后端；纯净机或仅 HTTP fallback upstream 默认开启"}
        else
          $p + {recommended:"off", source:"https-unknown", reason:"检测到普通 HTTPS 后端或第三方面板站点，但无法确认支持 PROXY protocol，默认关闭"}
        end'
}

xray_agent_nginx_resolved_proxy_protocol_json() {
    xray_agent_nginx_proxy_protocol_recommendation_json | jq -c '
      if .configured == "on" then
        . + {resolved:"on", resolved_reason:"用户配置前门 PROXY=on"}
      elif .configured == "off" then
        . + {resolved:"off", resolved_reason:"用户配置前门 PROXY=off"}
      else
        . + {resolved:.recommended, resolved_reason:.reason}
      end'
}

xray_agent_nginx_resolved_proxy_protocol_mode() {
    xray_agent_nginx_resolved_proxy_protocol_json | jq -r '.resolved'
}

xray_agent_nginx_resolved_proxy_protocol_bool() {
    if [[ "$(xray_agent_nginx_resolved_proxy_protocol_mode)" == "on" ]]; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

xray_agent_nginx_frontdoor_proxy_protocol() {
    xray_agent_nginx_resolved_proxy_protocol_json | jq -r '"\(.configured)->\(.resolved)"'
}

xray_agent_nginx_print_proxy_protocol_preflight() {
    local result_json
    result_json="$(xray_agent_nginx_resolved_proxy_protocol_json)"
    echoContent skyBlue "-------------------------443前门预检-----------------------------"
    echoContent yellow "TCP/443占用: $(printf '%s\n' "${result_json}" | jq -r '.port443_owner')"
    echoContent yellow "脚本 alone.stream: $(printf '%s\n' "${result_json}" | jq -r '.script_stream')"
    echoContent yellow "前门PROXY配置: $(printf '%s\n' "${result_json}" | jq -r '.configured')  推荐: $(printf '%s\n' "${result_json}" | jq -r '.recommended')  生效: $(printf '%s\n' "${result_json}" | jq -r '.resolved')"
    echoContent yellow "原因: $(printf '%s\n' "${result_json}" | jq -r '.resolved_reason')"
    printf '%s\n' "${result_json}" | jq -r '.site_stats | "已注册站点: HTTP fallback=\(.http_total) HTTPS透传=\(.stream_total) HTTPS未知/不支持=\(.stream_unknown_or_unsupported)"' |
        while IFS= read -r line; do echoContent yellow "${line}"; done
    printf '%s\n' "${result_json}" | jq -r '.detected_frontends[]?' |
        while IFS= read -r panel; do echoContent yellow "检测到第三方前端: ${panel}（只输出接入建议，不自动改配置）"; done
    printf '%s\n' "${result_json}" | jq -r '.https_config_files[]?' |
        while IFS= read -r config_file; do echoContent yellow "HTTPS配置: ${config_file}"; done
    if [[ "$(printf '%s\n' "${result_json}" | jq -r '.source')" == "https-unknown" ]]; then
        echoContent yellow "建议: 先把现有网站迁移到本机 HTTP upstream 后在菜单注册，或确认 HTTPS 后端支持 PROXY protocol 后再开启。"
    fi
}

xray_agent_nginx_confirm_frontdoor_takeover() {
    local port443_owner
    port443_owner="$(xray_agent_port_owner TCP 443 2>/dev/null || printf '未检测')"
    case "${port443_owner}" in
        空闲 | nginx/* | xray/* | 未检测*)
            return 0
            ;;
    esac
    echoContent red " ---> TCP/443 当前由 ${port443_owner} 占用，不适合由脚本直接接管。"
    echoContent yellow " ---> 请先把现有网站迁移到本机后端 upstream 后注册，或为 Xray 选择非 443 后端端口。"
    return 1
}

xray_agent_nginx_frontdoor_prompt_default() {
    if [[ "$(xray_agent_nginx_resolved_proxy_protocol_json | jq -r '.recommended')" == "on" ]]; then
        printf 'y\n'
    else
        printf 'n\n'
    fi
}

xray_agent_nginx_prompt_enable_frontdoor() {
    local prompt_title="$1"
    local default_answer
    default_answer="$(xray_agent_nginx_frontdoor_prompt_default)"
    echoContent yellow "${prompt_title}"
    xray_agent_prompt_yes_no "是否启用 443 前门？" "${default_answer}"
}
