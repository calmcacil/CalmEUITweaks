#!/usr/bin/env bash
set -euo pipefail
if command -v lua5.1 >/dev/null 2>&1 && command -v luac5.1 >/dev/null 2>&1; then
    exit 0
fi
: "${RUNNER_TEMP:?This installer is for GitHub-hosted Linux runners}"
: "${GITHUB_PATH:?GITHUB_PATH is required}"
# Build MIT-licensed Lua 5.1.5 without Ubuntu mirrors or readline dependencies.
revision=d2e7e7d4d43ff9068b279a617c5b2ca2c2771676
checksum=155ae33fa6867ce087200f429895855c261bbd202ec18f76db659c95548d5e40
archive="$RUNNER_TEMP/lua-5.1.5.tar.gz"
root="$RUNNER_TEMP/calm-ci/lua"
bin="$RUNNER_TEMP/calm-ci/bin"
curl --fail --silent --show-error --location --retry 3 \
    "https://codeload.github.com/LuaDist/lua/tar.gz/${revision}" \
    --output "$archive"
printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check
mkdir -p "$root" "$bin"
tar -xzf "$archive" --strip-components=1 -C "$root"
cmake -S "$root" -B "$root/build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DLUA_USE_READLINE=OFF -DLUA_USE_CURSES=OFF \
    -DLUA_USE_RELATIVE_LOADLIB=OFF
cmake --build "$root/build" --target lua luac --parallel 2
ln -sf "$root/build/lua" "$bin/lua5.1"
ln -sf "$root/build/luac" "$bin/luac5.1"
"$bin/lua5.1" -v
"$bin/luac5.1" -v
echo "$bin" >> "$GITHUB_PATH"
