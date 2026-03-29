if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

XRAY_AGENT_VERSION="${XRAY_AGENT_VERSION:-$(tr -d '\r\n' <"${XRAY_AGENT_PROJECT_ROOT}/VERSION" 2>/dev/null)}"
XRAY_AGENT_PROJECT_NAME="${XRAY_AGENT_PROJECT_NAME:-xray-agent}"
XRAY_AGENT_PROJECT_OWNER="${XRAY_AGENT_PROJECT_OWNER:-Suysker}"
XRAY_AGENT_PROJECT_REPO="${XRAY_AGENT_PROJECT_REPO:-https://github.com/Suysker/xray-agent}"
XRAY_AGENT_PROJECT_RAW_INSTALL_URL="${XRAY_AGENT_PROJECT_RAW_INSTALL_URL:-https://raw.githubusercontent.com/Suysker/xray-agent/master/install.sh}"

xray_agent_project_root() {
    echo "${XRAY_AGENT_PROJECT_ROOT}"
}

echoContent() {
    case "$1" in
        red)
            echo -e "\033[31m$2\033[0m"
            ;;
        skyBlue)
            echo -e "\033[36m$2\033[0m"
            ;;
        green)
            echo -e "\033[32m$2\033[0m"
            ;;
        white)
            echo -e "\033[37m$2\033[0m"
            ;;
        magenta)
            echo -e "\033[35m$2\033[0m"
            ;;
        yellow)
            echo -e "\033[33m$2\033[0m"
            ;;
    esac
}

xray_agent_log() {
    local color="${1:-white}"
    local message="$2"
    echoContent "${color}" "${message}"
}

xray_agent_confirm() {
    local prompt="$1"
    local default_value="${2:-n}"
    local answer
    read -r -p "${prompt}" answer
    answer="${answer:-${default_value}}"
    [[ "${answer}" == "y" ]]
}

xray_agent_error() {
    echoContent red "$1"
    exit 0
}
