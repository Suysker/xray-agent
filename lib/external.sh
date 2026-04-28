#!/usr/bin/env bash

if [[ -z "${XRAY_AGENT_PROJECT_ROOT:-}" ]]; then
    XRAY_AGENT_PROJECT_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

xray_agent_external_backtrace() {
    bash <(curl https://raw.githubusercontent.com/zhanghanyun/backtrace/main/install.sh -sSf)
}

xray_agent_external_hyperspeed() {
    bash <(curl -Lso- https://bench.im/hyperspeed)
}

xray_agent_external_hysteria_oneclick() {
    bash <(curl -fsSL https://get.hy2.sh)
}

xray_agent_external_kernel_bbr() {
    wget -N https://raw.githubusercontent.com/jinwyp/one_click_script/master/install_kernel.sh && bash install_kernel.sh
}

xray_agent_external_unlock_media() {
    bash <(curl -L -s check.unlock.media)
}

xray_agent_external_vps_info() {
    wget -q https://github.com/Aniverse/A/raw/i/a && bash a
}

xray_agent_external_warp_menu() {
    wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh
}
