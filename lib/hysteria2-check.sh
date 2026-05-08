#!/usr/bin/env bash

set -u

XRAY_AGENT_CHECK_ROOT="${XRAY_AGENT_CHECK_ROOT:-/etc/xray-agent}"
XRAY_AGENT_CHECK_INSTALL="${XRAY_AGENT_CHECK_ROOT}/install.sh"

if [[ ! -r "${XRAY_AGENT_CHECK_INSTALL}" ]]; then
    printf 'xray-agent: skip Hysteria2 REDIRECT check, install.sh not found: %s\n' "${XRAY_AGENT_CHECK_INSTALL}" >&2
    exit 0
fi

# Load the installed runtime without entering the interactive menu.
# shellcheck source=/etc/xray-agent/install.sh
if ! source "${XRAY_AGENT_CHECK_INSTALL}"; then
    printf 'xray-agent: failed to load install.sh for Hysteria2 REDIRECT check\n' >&2
    exit 1
fi

initVar
readConfigHostPathUUID

if [[ -z "${Hysteria2HopPorts:-}" ]]; then
    printf 'xray-agent: Hysteria2 udpHop is not enabled, skip REDIRECT check\n'
    exit 0
fi

xray_agent_hysteria2_repair_hop_redirects
