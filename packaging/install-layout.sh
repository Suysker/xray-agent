#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
TARGET_ROOT="${1:-/etc/xray-agent}"

rm -rf \
    "${TARGET_ROOT}/lib/common" \
    "${TARGET_ROOT}/lib/runtime" \
    "${TARGET_ROOT}/lib/system" \
    "${TARGET_ROOT}/lib/tls" \
    "${TARGET_ROOT}/lib/core" \
    "${TARGET_ROOT}/lib/nginx" \
    "${TARGET_ROOT}/lib/protocols" \
    "${TARGET_ROOT}/lib/accounts" \
    "${TARGET_ROOT}/lib/routing" \
    "${TARGET_ROOT}/lib/features" \
    "${TARGET_ROOT}/lib/apps" \
    "${TARGET_ROOT}/lib/external" \
    "${TARGET_ROOT}/lib/experimental" \
    "${TARGET_ROOT}/profiles/experimental" \
    "${TARGET_ROOT}/templates/xray/snippets" \
    "${TARGET_ROOT}/templates/cron" \
    "${TARGET_ROOT}/templates/packages" \
    "${TARGET_ROOT}/verify" \
    "${TARGET_ROOT}/scripts"

mkdir -p "${TARGET_ROOT}"/{lib,templates,profiles,docs,packaging}

cp -R "${PROJECT_ROOT}/lib/." "${TARGET_ROOT}/lib/"
cp -R "${PROJECT_ROOT}/templates/." "${TARGET_ROOT}/templates/"
cp -R "${PROJECT_ROOT}/profiles/." "${TARGET_ROOT}/profiles/"
cp -R "${PROJECT_ROOT}/docs/." "${TARGET_ROOT}/docs/"
cp -R "${PROJECT_ROOT}/packaging/." "${TARGET_ROOT}/packaging/"
cp "${PROJECT_ROOT}/install.sh" "${TARGET_ROOT}/install.sh"
cp "${PROJECT_ROOT}/README.md" "${TARGET_ROOT}/README.md"
cp "${PROJECT_ROOT}/VERSION" "${TARGET_ROOT}/VERSION"
cp "${PROJECT_ROOT}/LICENSE" "${TARGET_ROOT}/LICENSE"

bash "${TARGET_ROOT}/packaging/upgrade.sh" "${TARGET_ROOT}"
chmod 700 "${TARGET_ROOT}/install.sh"
