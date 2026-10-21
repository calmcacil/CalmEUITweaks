#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python_bin=${PYTHON_BIN:-python3}
luac_bin=${LUAC_BIN:-luac5.1}
"$python_bin" scripts/check.py
while IFS= read -r -d '' file; do
    "$luac_bin" -p "$file"
done < <(find core functions macros compatability options tests -name '*.lua' -print0)
