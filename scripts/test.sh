#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Existing test fixtures resolve files relative to a parent containing CalmEUITweaks.
test_parent=$(mktemp -d)
trap 'rm -rf -- "$test_parent"' EXIT
ln -s "$root" "$test_parent/CalmEUITweaks"
cd "$test_parent"
for test in CalmEUITweaks/tests/*.lua; do
    lua5.1 "$test"
done
