#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
bash scripts/check-static.sh
bash scripts/test.sh
shellcheck scripts/*.sh
actionlint
