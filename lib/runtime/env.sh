if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

XRAY_AGENT_LIB_DIR="${XRAY_AGENT_PROJECT_ROOT}/lib"
XRAY_AGENT_TEMPLATE_DIR="${XRAY_AGENT_PROJECT_ROOT}/templates"
XRAY_AGENT_PROFILE_DIR="${XRAY_AGENT_PROJECT_ROOT}/profiles"
XRAY_AGENT_DOCS_DIR="${XRAY_AGENT_PROJECT_ROOT}/docs"
XRAY_AGENT_VERIFY_DIR="${XRAY_AGENT_PROJECT_ROOT}/verify"
XRAY_AGENT_PACKAGING_DIR="${XRAY_AGENT_PROJECT_ROOT}/packaging"

XRAY_AGENT_ETC_DIR="/etc/xray-agent"
XRAY_AGENT_TLS_DIR="${XRAY_AGENT_ETC_DIR}/tls"
XRAY_AGENT_XRAY_DIR="${XRAY_AGENT_ETC_DIR}/xray"
XRAY_AGENT_XRAY_CONF_DIR="${XRAY_AGENT_XRAY_DIR}/conf"
XRAY_AGENT_XRAY_BINARY="${XRAY_AGENT_XRAY_DIR}/xray"

initVar() {
    installType='yum -y install'
    removeType='yum -y remove'
    upgrade="yum -y update"
    echoType='echo -e'
    xrayCoreCPUVendor=""
    domain=
    path=
    UUID=
    Port=
    totalProgress=1
    coreInstallType=
    currentInstallProtocolType=
    frontingType=
    centosVersion=
    release=
    updateReleaseInfoChange=
    nginxConfigPath=/etc/nginx/conf.d/
    configPath=/etc/xray-agent/xray/conf/
    ctlPath=/etc/xray-agent/xray/xray
    prereleaseStatus=false
    sslType=
    TLSDomain=
    RealityfrontingType=
    RealityPrivateKey=
    RealityPublicKey=
    RealityServerNames=
    RealityDestDomain=
    RealityPort=
    RealityShortID=
    XHTTPMode=auto
    reuse443=
}

checkBTPanel() {
    if pgrep -f "BT-Panel" >/dev/null 2>&1; then
        nginxConfigPath=/www/server/panel/vhost/nginx/
    fi
}

xrayAgentLoadFeatureFlags() {
    local feature_flags_path="/etc/xray-agent/feature-flags.env"
    if [[ -r "${feature_flags_path}" ]]; then
        # shellcheck disable=SC1090
        source "${feature_flags_path}"
    fi
}

xrayAgentPersistFeatureFlags() {
    local feature_flags_path="/etc/xray-agent/feature-flags.env"
    mkdir -p /etc/xray-agent
    cat <<EOF >"${feature_flags_path}"
XRAY_AGENT_ENABLE_FINALMASK=${XRAY_AGENT_ENABLE_FINALMASK:-false}
XRAY_AGENT_FINALMASK_MODE=${XRAY_AGENT_FINALMASK_MODE:-header}
XRAY_AGENT_FINALMASK_QUIC_PARAMS=${XRAY_AGENT_FINALMASK_QUIC_PARAMS:-off}
XRAY_AGENT_ENABLE_ECH=${XRAY_AGENT_ENABLE_ECH:-false}
XRAY_AGENT_ECH_CONFIG=${XRAY_AGENT_ECH_CONFIG:-example-ech-config}
XRAY_AGENT_ENABLE_VLESS_ENCRYPTION=${XRAY_AGENT_ENABLE_VLESS_ENCRYPTION:-false}
XRAY_AGENT_VLESS_ENCRYPTION_MODE=${XRAY_AGENT_VLESS_ENCRYPTION_MODE:-mlkem768}
XRAY_AGENT_BROWSER_HEADERS=${XRAY_AGENT_BROWSER_HEADERS:-chrome}
XRAY_AGENT_TRUSTED_X_FORWARDED_FOR=${XRAY_AGENT_TRUSTED_X_FORWARDED_FOR:-127.0.0.1}
XRAY_AGENT_TUN_PROCESS_NAMES=${XRAY_AGENT_TUN_PROCESS_NAMES:-curl,wget,bash}
EOF
}
