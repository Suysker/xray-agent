#!/usr/bin/env bash
set -euo pipefail

TARGET_ROOT="${1:-/etc/xray-agent}"

if [[ -n "${TARGET_ROOT}" && "${TARGET_ROOT}" == /etc/xray-agent* ]]; then
    rm -rf "${TARGET_ROOT}"
fi
