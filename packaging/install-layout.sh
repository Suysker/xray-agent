#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
TARGET_ROOT="${1:-/etc/xray-agent}"

mkdir -p "${TARGET_ROOT}"/{lib,templates,profiles,docs,verify,packaging}

cp -R "${PROJECT_ROOT}/lib/." "${TARGET_ROOT}/lib/"
cp -R "${PROJECT_ROOT}/templates/." "${TARGET_ROOT}/templates/"
cp -R "${PROJECT_ROOT}/profiles/." "${TARGET_ROOT}/profiles/"
cp -R "${PROJECT_ROOT}/docs/." "${TARGET_ROOT}/docs/"
cp -R "${PROJECT_ROOT}/verify/." "${TARGET_ROOT}/verify/"
cp -R "${PROJECT_ROOT}/packaging/." "${TARGET_ROOT}/packaging/"
cp "${PROJECT_ROOT}/install.sh" "${TARGET_ROOT}/install.sh"
cp "${PROJECT_ROOT}/README.md" "${TARGET_ROOT}/README.md"
cp "${PROJECT_ROOT}/VERSION" "${TARGET_ROOT}/VERSION"
cp "${PROJECT_ROOT}/LICENSE" "${TARGET_ROOT}/LICENSE"

chmod 700 "${TARGET_ROOT}/install.sh"
