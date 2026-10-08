#!/usr/bin/env bash
set -euo pipefail
: "${RUNNER_TEMP:?This installer is for GitHub-hosted Linux x64 runners}"
: "${GITHUB_PATH:?GITHUB_PATH is required}"
[[ $(uname -sm) == 'Linux x86_64' ]] || { echo 'error: expected Linux x64' >&2; exit 1; }
version=1.7.12
checksum=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
archive="$RUNNER_TEMP/actionlint_${version}_linux_amd64.tar.gz"
bin="$RUNNER_TEMP/calm-ci/bin"
curl --fail --silent --show-error --location --retry 3 \
    "https://github.com/rhysd/actionlint/releases/download/v${version}/actionlint_${version}_linux_amd64.tar.gz" \
    --output "$archive"
printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check
mkdir -p "$bin"
tar -xzf "$archive" -C "$bin" actionlint
echo "$bin" >> "$GITHUB_PATH"
