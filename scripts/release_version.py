"""Validate supported versions and the identity/channel of a published release."""

import argparse
import json
from pathlib import Path
import re
import sys

VERSION_PATTERN = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-alpha\.(0|[1-9][0-9]*))?"


def valid_version(version):
    return isinstance(version, str) and re.fullmatch(VERSION_PATTERN, version) is not None


def channel_configs(version, requested):
    if not valid_version(version) or requested not in ("automatic", "stable", "alpha"):
        raise ValueError("Expected a supported current version and automatic, stable or alpha channel")
    current = "alpha" if "-alpha." in version else "stable"
    configs = {"stable": "release-please-config.json", "alpha": ".github/release-please-alpha-config.json"}
    return configs[current], configs[current if requested == "automatic" else requested]


def validate_release(release, tag, identity=None):
    if not tag.startswith("v") or not valid_version(tag[1:]):
        raise ValueError("Expected vX.Y.Z or vX.Y.Z-alpha.N")
    if release.get("tagName") != tag or release.get("isDraft") is not False or not release.get("publishedAt"):
        raise ValueError("Release must be published and match the requested tag")
    if release.get("isPrerelease") is not ("-alpha." in tag):
        raise ValueError("Alpha tags require a prerelease; stable tags require a stable release")
    if not release.get("id") or (identity and release.get("id") != identity):
        raise ValueError("Release identity changed or is missing")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", nargs="?")
    parser.add_argument("--identity")
    parser.add_argument("--select-channels", choices=("automatic", "stable", "alpha"))
    args = parser.parse_args()
    try:
        if args.select_channels:
            manifest = json.loads(Path(".release-please-manifest.json").read_text())
            release_config, pr_config = channel_configs(manifest["."], args.select_channels)
            print(f"release_config={release_config}\npr_config={pr_config}")
        elif args.tag:
            validate_release(json.load(sys.stdin), args.tag, args.identity)
        else:
            parser.error("a release tag or --select-channels is required")
    except (ValueError, AttributeError) as error:
        parser.exit(1, f"error: {error}\n")
