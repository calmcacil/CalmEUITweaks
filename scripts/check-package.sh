#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python_bin=${PYTHON_BIN:-python3}
if [[ $# -gt 0 ]]; then
    "$python_bin" scripts/check.py "$@"
else
    shopt -s nullglob
    archives=(.release/CalmEUITweaks-*.zip)
    [[ ${#archives[@]} -eq 1 ]] || { echo 'error: expected exactly one package' >&2; exit 1; }
    "$python_bin" scripts/check.py "${archives[0]}"
fi
