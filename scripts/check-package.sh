#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [[ $# -gt 0 ]]; then
    python3 scripts/check.py "$@"
else
    shopt -s nullglob
    archives=(.release/CalmEUITweaks-*.zip)
    [[ ${#archives[@]} -eq 1 ]] || { echo 'error: expected exactly one package' >&2; exit 1; }
    python3 scripts/check.py "${archives[0]}"
fi
