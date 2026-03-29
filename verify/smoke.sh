#!/usr/bin/env bash
set -euo pipefail

bash -n install.sh
find lib packaging verify -name "*.sh" -print0 | xargs -0 -n1 bash -n
echo "PASS smoke"
