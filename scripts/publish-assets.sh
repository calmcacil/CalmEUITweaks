#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

: "${RELEASE_TAG:?RELEASE_TAG is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

archive_name="CalmEUITweaks-${RELEASE_TAG}.zip"
archive=".release/$archive_name"
metadata=.release/release.json
expected_metadata=.release/release.expected.json
checksums=.release/checksums.txt

[[ -f "$archive" ]] || { printf 'error: %s is missing\n' "$archive" >&2; exit 1; }
bash scripts/check-package.sh "$archive" "${RELEASE_TAG#v}"

jq -n \
    --arg version "$RELEASE_TAG" \
    --arg filename "$archive_name" \
    '{
      releases: [{
        name: "Calm UI Tweaks",
        version: $version,
        filename: $filename,
        nolib: false,
        metadata: [
          {flavor: "forever", interface: 16001}
        ]
      }]
    }' > "$expected_metadata"
cp "$expected_metadata" "$metadata"

assets=$(gh release view "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" --json assets --jq '.assets[].name')
mapfile -t remote_assets <<< "$assets"

has_remote_asset() {
    local expected=$1
    local asset
    for asset in "${remote_assets[@]}"; do
        [[ "$asset" == "$expected" ]] && return 0
    done
    return 1
}

reuse_or_upload() {
    local name=$1
    local path=$2
    if has_remote_asset "$name"; then
        printf 'reusing existing release asset %s\n' "$name"
        gh release download "$RELEASE_TAG" \
            --repo "$GITHUB_REPOSITORY" \
            --pattern "$name" \
            --dir .release \
            --clobber
    else
        printf 'uploading missing release asset %s\n' "$name"
        gh release upload "$RELEASE_TAG" "$path" --repo "$GITHUB_REPOSITORY"
    fi
}

reuse_or_upload "$archive_name" "$archive"
reuse_or_upload release.json "$metadata"

bash scripts/check-package.sh "$archive" "${RELEASE_TAG#v}"
diff -u <(jq -S . "$expected_metadata") <(jq -S . "$metadata")

(
    cd .release
    sha256sum "$archive_name" release.json > checksums.txt
)

if has_remote_asset checksums.txt; then
    printf 'verifying existing release asset checksums.txt\n'
    gh release download "$RELEASE_TAG" \
        --repo "$GITHUB_REPOSITORY" \
        --pattern checksums.txt \
        --dir .release \
        --clobber
    [[ $(wc -l < "$checksums") -eq 2 ]] || { printf 'error: checksums.txt must contain two entries\n' >&2; exit 1; }
    diff -u <(printf '%s\n' "$archive_name" release.json | sort) <(awk '{print $2}' "$checksums" | sort)
    (
        cd .release
        sha256sum --check checksums.txt
    )
else
    printf 'uploading missing release asset checksums.txt\n'
    gh release upload "$RELEASE_TAG" "$checksums" --repo "$GITHUB_REPOSITORY"
fi
