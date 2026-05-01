#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_nginx_profile_dir() {
    printf '%s/nginx\n' "${XRAY_AGENT_PROFILE_DIR:-${XRAY_AGENT_PROJECT_ROOT}/profiles}"
}

xray_agent_nginx_reverse_proxy_file() {
    printf '%s/reverse_proxies.custom.json\n' "$(xray_agent_nginx_profile_dir)"
}

xray_agent_nginx_default_reverse_proxy_json() {
    jq -nc '{
      version:1,
      frontdoor:{proxy_protocol:"auto",last_reason:""},
      default_upstream:{url:"https://huggingface.co"},
      sites:[]
    }'
}

xray_agent_nginx_normalize_reverse_proxy_json() {
    local domain_name="${domain:-}"
    jq -c --arg domain "${domain_name}" '
      def valid_proxy_mode($value):
        if $value == "on" or $value == "off" or $value == "auto" then $value else "auto" end;
      def legacy_http_site:
        if (.site_upstream.enabled == true and ((.site_upstream.url // "") | length > 0)) then
          [{
            server_name: (if ($domain | length) > 0 then $domain else "default" end),
            mode: "http_fallback",
            upstream: .site_upstream.url,
            host: (.site_upstream.host // $domain),
            enabled: true
          }]
        else [] end;
      def legacy_stream_sites:
        (.legacy_https_backends // [])
        | map(select(.enabled == true and ((.server_name // "") | length > 0) and ((.target // "") | length > 0))
          | {
              server_name: .server_name,
              mode: "stream_tls",
              upstream: .target,
              proxy_protocol: (if (.proxy_protocol_required == true or .proxy_protocol_supported == true) then "supported" else "unknown" end),
              enabled: true
            });
      def normalize_site:
        if (.mode // "") == "stream_tls" then
          {
            server_name: (.server_name // ""),
            mode: "stream_tls",
            upstream: (.upstream // .target // ""),
            proxy_protocol: (if (.proxy_protocol // "") == "supported" then "supported" elif (.proxy_protocol // "") == "unsupported" then "unsupported" else "unknown" end),
            enabled: (.enabled // true)
          }
        else
          {
            server_name: (.server_name // (if ($domain | length) > 0 then $domain else "default" end)),
            mode: "http_fallback",
            upstream: (.upstream // .url // ""),
            host: (.host // $domain),
            enabled: (.enabled // true)
          }
        end;
      ((legacy_http_site + legacy_stream_sites + (.sites // [])) | map(normalize_site)) as $sites
      | {
          version: 1,
          frontdoor: {
            proxy_protocol: valid_proxy_mode(.frontdoor.proxy_protocol // "auto"),
            last_reason: (.frontdoor.last_reason // "")
          },
          default_upstream: {
            url: (.default_upstream.url // "https://huggingface.co")
          },
          sites: (
            reduce ($sites[]? | select((.upstream // "") | length > 0)) as $site
              ({}; .[(($site.mode // "") + "|" + ($site.server_name // ""))] = $site)
            | [.[]]
          )
        }
    '
}

xray_agent_nginx_reverse_proxy_json() {
    local proxy_file
    proxy_file="$(xray_agent_nginx_reverse_proxy_file)"
    if [[ -r "${proxy_file}" ]] && jq -e '.version == 1' "${proxy_file}" >/dev/null 2>&1; then
        xray_agent_nginx_normalize_reverse_proxy_json <"${proxy_file}"
        return 0
    fi
    xray_agent_nginx_default_reverse_proxy_json
}

xray_agent_nginx_save_reverse_proxy_json() {
    local json_content="$1"
    local proxy_file proxy_dir
    proxy_file="$(xray_agent_nginx_reverse_proxy_file)"
    proxy_dir="$(dirname "${proxy_file}")"
    mkdir -p "${proxy_dir}"
    printf '%s\n' "${json_content}" | xray_agent_nginx_normalize_reverse_proxy_json | jq . >"${proxy_file}"
    chmod 600 "${proxy_file}" 2>/dev/null || true
}

xray_agent_nginx_frontdoor_proxy_protocol_config() {
    xray_agent_nginx_reverse_proxy_json | jq -r '.frontdoor.proxy_protocol // "auto"'
}

xray_agent_nginx_set_frontdoor_proxy_protocol() {
    local mode="$1"
    local reason="${2:-manual}"
    local updated_json
    case "${mode}" in
        on | off | auto) ;;
        *) return 1 ;;
    esac
    updated_json="$(xray_agent_nginx_reverse_proxy_json | jq --arg mode "${mode}" --arg reason "${reason}" '
      .frontdoor.proxy_protocol = $mode
      | .frontdoor.last_reason = $reason
    ')"
    xray_agent_nginx_save_reverse_proxy_json "${updated_json}"
}

xray_agent_nginx_url_host() {
    local upstream_url="$1"
    upstream_url="${upstream_url#http://}"
    upstream_url="${upstream_url#https://}"
    upstream_url="${upstream_url%%/*}"
    upstream_url="${upstream_url%%:*}"
    printf '%s\n' "${upstream_url}"
}

xray_agent_nginx_active_site_enabled() {
    xray_agent_nginx_active_http_site_json | jq -e '.enabled == true and ((.upstream // "") | length > 0)' >/dev/null
}

xray_agent_nginx_active_http_site_json() {
    local proxy_json
    proxy_json="$(xray_agent_nginx_reverse_proxy_json)"
    printf '%s\n' "${proxy_json}" | jq -c --arg domain "${domain:-}" '
      [.sites[]? | select(.enabled == true and .mode == "http_fallback" and ((.upstream // "") | length > 0))] as $sites
      | (($sites | map(select(.server_name == $domain)) | .[0]) // $sites[0] // empty)
    '
}

xray_agent_nginx_active_upstream_url() {
    local fallback_url="${1:-https://huggingface.co}"
    local proxy_json active_site
    proxy_json="$(xray_agent_nginx_reverse_proxy_json)"
    active_site="$(xray_agent_nginx_active_http_site_json)"
    if [[ -n "${active_site}" ]]; then
        printf '%s\n' "${active_site}" | jq -r '.upstream'
        return 0
    fi
    printf '%s\n' "${proxy_json}" | jq -r --arg fallback "${fallback_url}" '(.default_upstream.url // "") as $url | if ($url | length) > 0 then $url else $fallback end'
}

xray_agent_nginx_active_host_header() {
    local upstream_url="$1"
    local active_site host_header
    active_site="$(xray_agent_nginx_active_http_site_json)"
    if [[ -n "${active_site}" ]]; then
        host_header="$(printf '%s\n' "${active_site}" | jq -r '.host // empty')"
        printf '%s\n' "${host_header:-${domain}}"
        return 0
    fi
    printf '$proxy_host\n'
}

xray_agent_nginx_active_tls_name() {
    local upstream_url="$1"
    local host_header="$2"
    if [[ "${host_header}" == "\$proxy_host" ]]; then
        printf '%s\n' "${host_header}"
        return 0
    fi
    printf '%s\n' "${host_header:-$(xray_agent_nginx_url_host "${upstream_url}")}"
}

xray_agent_nginx_legacy_backend_count() {
    xray_agent_nginx_reverse_proxy_json | jq -r '[.sites[]? | select(.enabled == true and .mode == "stream_tls")] | length'
}

xray_agent_nginx_current_upstream_url() {
    local nginx_file="${nginxConfigPath}alone.conf"
    [[ -f "${nginx_file}" ]] || return 0
    awk '$1 == "proxy_pass" && $2 ~ /^https?:\/\// {gsub(";","",$2); print $2; exit}' "${nginx_file}"
}

xray_agent_nginx_normalize_upstream_url() {
    local upstream_url="$1"
    if [[ "${upstream_url}" != http://* && "${upstream_url}" != https://* ]]; then
        upstream_url="https://${upstream_url}"
    fi
    printf '%s\n' "${upstream_url}"
}

xray_agent_nginx_validate_upstream_url() {
    [[ "$1" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?(/.*)?$ ]] &&
        [[ "$1" != *[[:space:]\;\{\}]* ]]
}

xray_agent_nginx_validate_host_header() {
    [[ -z "$1" || "$1" =~ ^[A-Za-z0-9.-]+$ ]]
}

xray_agent_nginx_validate_stream_target() {
    [[ "$1" =~ ^([A-Za-z0-9.-]+|\[[0-9A-Fa-f:.]+\]):[0-9]+$ ]]
}
