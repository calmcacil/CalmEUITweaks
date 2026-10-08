#!/usr/bin/env bash
set -euo pipefail
if command -v lua5.1 >/dev/null 2>&1 && command -v luac5.1 >/dev/null 2>&1; then
    exit 0
fi
# Hosted runners usually have usable apt metadata; refresh only if installation fails.
if ! sudo apt-get install -y --no-install-recommends lua5.1; then
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends lua5.1
fi
