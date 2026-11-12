"""Regression checks for release channel and identity validation."""

import unittest
import json
from pathlib import Path

from release_version import channel_configs, valid_version, validate_release


class ReleaseVersionTests(unittest.TestCase):
    def test_requested_channel_never_changes_channel_of_merged_release(self):
        stable = "release-please-config.json"
        alpha = ".github/release-please-alpha-config.json"
        for version, request, expected in (
                ("1.0.1", "automatic", (stable, stable)),
                ("1.0.1", "alpha", (stable, alpha)),
                ("1.1.0-alpha.1", "automatic", (alpha, alpha)),
                ("1.1.0-alpha.1", "stable", (alpha, stable))):
            with self.subTest(version=version, request=request):
                self.assertEqual(channel_configs(version, request), expected)

    def test_reject_unsupported_channel_selection(self):
        for version, request in (("1.0.0", "beta"), ("1.0.0-beta.1", "alpha")):
            with self.subTest(version=version, request=request), self.assertRaises(ValueError):
                channel_configs(version, request)

    def test_channel_configs_preserve_shared_release_settings(self):
        root = Path(__file__).resolve().parent.parent
        stable = json.loads((root / "release-please-config.json").read_text())
        alpha = json.loads((root / ".github/release-please-alpha-config.json").read_text())
        self.assertIs(stable["packages"]["."]["prerelease"], False)
        self.assertIs(alpha["packages"]["."]["prerelease"], True)
        self.assertIs(alpha["packages"]["."]["draft"], True)
        self.assertIs(alpha["packages"]["."]["force-tag-creation"], True)
        self.assertNotIn("draft", stable["packages"]["."])
        self.assertEqual(alpha["packages"]["."]["prerelease-type"], "alpha.1")
        self.assertEqual(stable["packages"]["."]["versioning"], "prerelease")
        self.assertEqual(alpha["packages"]["."]["versioning"], "prerelease")
        del alpha["packages"]["."]["prerelease-type"]
        del alpha["packages"]["."]["draft"]
        del alpha["packages"]["."]["force-tag-creation"]
        alpha["packages"]["."]["prerelease"] = False
        self.assertEqual(stable, alpha)

    def release(self, tag="v1.1.0-alpha.1", **changes):
        release = dict(tagName=tag, isDraft=False, publishedAt="2026-11-12T00:00:00Z",
                       id="release-1", isPrerelease="-alpha." in tag)
        release.update(changes)
        return release

    def test_supported_versions(self):
        for version in ("0.0.0", "1.0.1", "1.1.0-alpha.0", "1.1.0-alpha.12"):
            with self.subTest(version=version):
                self.assertTrue(valid_version(version))

    def test_reject_ambiguous_and_unsupported_versions(self):
        for version in ("v1.0.0", "01.0.0", "1.0.0-alpha.01", "1.0.0-alpha",
                        "1.0.0-beta.1", "1.0.0+build", "1.0.0\n", "1.0", "1.0.0;id", None):
            with self.subTest(version=version):
                self.assertFalse(valid_version(version))

    def test_matching_published_channels(self):
        for tag in ("v1.0.1", "v1.1.0-alpha.1"):
            validate_release(self.release(tag), tag, "release-1")

    def test_reject_channel_mismatch(self):
        for tag in ("v1.0.1", "v1.1.0-alpha.1"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                validate_release(self.release(tag, isPrerelease="-alpha." not in tag), tag)

    def test_reject_missing_or_nonboolean_channel(self):
        for value in (None, "false", 0, 1):
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_release(self.release(isPrerelease=value), "v1.1.0-alpha.1")

    def test_reject_draft_unpublished_tag_and_identity_changes(self):
        for changes in (dict(isDraft=True), dict(publishedAt=None), dict(tagName="v1.1.0-alpha.2"),
                        dict(id="replacement"), dict(id=None)):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validate_release(self.release(**changes), "v1.1.0-alpha.1", "release-1")

    def test_reject_invalid_requested_tags(self):
        for tag in ("1.0.1", "v1.1.0-beta.1", "v1.1.0-alpha.01"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                validate_release(self.release(tag), tag)


if __name__ == "__main__":
    unittest.main()
