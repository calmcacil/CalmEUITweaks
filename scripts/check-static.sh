#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 scripts/check.py
while IFS= read -r -d '' file; do
    luac5.1 -p "$file"
done < <(find core functions macros compatability options tests -name '*.lua' -print0)
