#!/usr/bin/env bash
set -euo pipefail
if command -v lua5.1 >/dev/null 2>&1 && command -v luac5.1 >/dev/null 2>&1; then
    exit 0
fi
: "${RUNNER_TEMP:?This installer is for GitHub-hosted Ubuntu x64 runners}"
: "${GITHUB_PATH:?GITHUB_PATH is required}"
[[ $(uname -sm) == 'Linux x86_64' ]] || { echo 'error: expected Linux x64' >&2; exit 1; }
# Download directly to avoid apt mirror selection and metadata refresh failures.
checksum=0d4d3678caf1dfa3f201d35203388da5e5aa393b153aec03c1e474f8cf6a476c
archive="$RUNNER_TEMP/lua5.1_5.1.5-9build2_amd64.deb"
root="$RUNNER_TEMP/calm-ci/lua"
curl --fail --silent --show-error --location --retry 3 \
    'https://archive.ubuntu.com/ubuntu/pool/universe/l/lua5.1/lua5.1_5.1.5-9build2_amd64.deb' \
    --output "$archive"
printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check
mkdir -p "$root"
dpkg-deb --extract "$archive" "$root"
"$root/usr/bin/lua5.1" -v
"$root/usr/bin/luac5.1" -v
echo "$root/usr/bin" >> "$GITHUB_PATH"
