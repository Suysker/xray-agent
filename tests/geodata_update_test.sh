#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "${test_root}"' EXIT
export XRAY_AGENT_PROJECT_ROOT="${repo_root}"
export XRAY_AGENT_ETC_DIR="${test_root}/runtime"
export PATH="${test_root}/bin:${PATH}"
mkdir -p "${XRAY_AGENT_ETC_DIR}"/{lib,xray/conf} "${test_root}/bin"
cp "${repo_root}/lib/common.sh" "${repo_root}/lib/core.sh" "${XRAY_AGENT_ETC_DIR}/lib/"
cp "${repo_root}/VERSION" "${XRAY_AGENT_ETC_DIR}/VERSION"
source "${repo_root}/lib/common.sh"
source "${repo_root}/lib/system.sh"

cat >"${test_root}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -eu
output=
url=
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output="$2"; shift 2 ;;
        https://*) url="$1"; shift ;;
        *) shift ;;
    esac
done
case "${url}" in
    */releases)
        printf '%s\n' '[{"tag_name":"test-release"}]' >"${output}"
        printf 200
        ;;
    */geosite.dat)
        [[ "${GEODATA_TEST_MODE}" != download-site-failure ]] || exit 6
        printf new-site >"${output}"
        ;;
    */geoip.dat)
        [[ "${GEODATA_TEST_MODE}" != download-ip-failure ]] || exit 6
        printf new-ip >"${output}"
        ;;
    *) exit 2 ;;
esac
EOF

cat >"${XRAY_AGENT_ETC_DIR}/xray/xray" <<'EOF'
#!/usr/bin/env bash
set -eu
test "$1" = run
test "$2" = -test
test "$3" = -confdir
test -s "$4/09_routing.json"
test "$(cat "${XRAY_LOCATION_ASSET}/geosite.dat")" = new-site
test "$(cat "${XRAY_LOCATION_ASSET}/geoip.dat")" = new-ip
[[ "${GEODATA_TEST_MODE}" != config-failure ]]
EOF

cat >"${test_root}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -eu
test "$1" = restart
test "$2" = xray
test "$(cat "${GEODATA_TEST_RUNTIME}/xray/geosite.dat")" = new-site
test "$(cat "${GEODATA_TEST_RUNTIME}/xray/geoip.dat")" = new-ip
printf 'restart\n' >>"${GEODATA_TEST_RUNTIME}/restarts"
EOF

chmod +x "${test_root}/bin/curl" "${test_root}/bin/systemctl" "${XRAY_AGENT_ETC_DIR}/xray/xray"
printf '%s\n' '{"routing":{"rules":[]}}' >"${XRAY_AGENT_ETC_DIR}/xray/conf/09_routing.json"
export GEODATA_TEST_RUNTIME="${XRAY_AGENT_ETC_DIR}"
xray_agent_write_geodata_update_helper
test -s "${XRAY_AGENT_ETC_DIR}/auto_update_geodata.sh"

for mode in download-site-failure download-ip-failure config-failure success; do
    export GEODATA_TEST_MODE="${mode}"
    printf old-site >"${XRAY_AGENT_ETC_DIR}/xray/geosite.dat"
    printf old-ip >"${XRAY_AGENT_ETC_DIR}/xray/geoip.dat"
    rm -f "${XRAY_AGENT_ETC_DIR}/restarts"
    if bash "${XRAY_AGENT_ETC_DIR}/auto_update_geodata.sh" >"${test_root}/${mode}.log" 2>&1; then
        test "${mode}" = success
        test "$(cat "${XRAY_AGENT_ETC_DIR}/xray/geosite.dat")" = new-site
        test "$(cat "${XRAY_AGENT_ETC_DIR}/xray/geoip.dat")" = new-ip
        test "$(wc -l <"${XRAY_AGENT_ETC_DIR}/restarts")" = 1
    else
        if [[ "${mode}" == success ]]; then cat "${test_root}/${mode}.log" >&2; fi
        test "${mode}" != success
        test "$(cat "${XRAY_AGENT_ETC_DIR}/xray/geosite.dat")" = old-site
        test "$(cat "${XRAY_AGENT_ETC_DIR}/xray/geoip.dat")" = old-ip
        test ! -e "${XRAY_AGENT_ETC_DIR}/restarts"
    fi
    test -z "$(find "${XRAY_AGENT_ETC_DIR}/xray" -maxdepth 1 -name '.geodata-update.*' -print)"
done
printf 'geodata update tests passed\n'
