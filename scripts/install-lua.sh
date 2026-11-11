#!/usr/bin/env bash
set -euo pipefail
if command -v lua5.1 >/dev/null 2>&1 && command -v luac5.1 >/dev/null 2>&1; then
    exit 0
fi
: "${RUNNER_TEMP:?This installer is for GitHub-hosted Linux x64 runners}"
: "${GITHUB_PATH:?GITHUB_PATH is required}"
[[ $(uname -sm) == 'Linux x86_64' ]] || { echo 'error: expected Linux x64' >&2; exit 1; }
# Match the Lua 5.1 binaries pinned for local development in mise.lock.
version=54f813a
bin="$RUNNER_TEMP/calm-ci/bin"
mkdir -p "$bin"
for tool in lua luac; do
    if [[ $tool == lua ]]; then
        checksum=93039e6a015589eb3aaad14f7cfbd53d776c109f8ac1235385036ce8953ce0e3
    else
        checksum=fd85ceca9a0b107c15a860a57533aeed81c152f25ed033ac69a3b4746278348e
    fi
    target="$bin/${tool}5.1"
    curl --fail --silent --show-error --location --retry 3 \
        "https://github.com/dyne/luabinaries/releases/download/${version}/${tool}51" \
        --output "$target"
    printf '%s  %s\n' "$checksum" "$target" | sha256sum --check
    chmod +x "$target"
    "$target" -v
done
echo "$bin" >> "$GITHUB_PATH"
