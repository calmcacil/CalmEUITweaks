# CI and releases

## Development

Use Conventional Commit PR titles and squash merges: `fix(chat): preserve routing`,
`feat(spacers): add an option`, or `ci: update workflows`.

CI runs Lua 5.1 syntax checks and the regression suites, validates
versions and workflows, and builds a BigWigs package snapshot. The aggregate
checks are named `Required` and `PR title`. The title check also reruns when a
PR title is edited. In-game verification in SPEC.md remains necessary.

The active main ruleset requires a pull request, an up-to-date branch, both
checks from GitHub Actions, and resolved review threads. It also blocks force
pushes and deletion. No bypass actors are configured. Approval count is zero;
a second reviewer is not required. Only squash merges are enabled, using the
PR title and body for the commit. Merged branches
are deleted automatically, and auto-merge is available after checks pass.

The active release-tag ruleset prevents tags matching v* from being moved or
deleted, while allowing new release tags to be created. Actions require full
commit SHA pins and allow GitHub-owned actions plus googleapis/release-please-action and
BigWigsMods/packager. Default workflow permissions remain read-only, and Actions
cannot approve pull requests. CodeQL does not support Lua; Go and container
scanners are not applicable to this addon.

On Linux, install Lua 5.1, Python 3, ShellCheck, and actionlint, then run
`bash scripts/check.sh`. The test runner creates a temporary parent directory
so existing test fixtures work regardless of the checkout folder name.

CI runs validation and package creation in one Required job to avoid extra runner
startup and aggregation overhead. Actionlint uses the pinned upstream 1.7.12
Linux x64 binary, verified against a committed SHA-256 digest; no Go toolchain or
source compilation is needed. ShellCheck and Python come from the hosted runner.
Lua is installed from binary packages only when missing, with apt metadata
refreshed only if the initial installation fails. Package snapshots are rebuilt
for every change to verify the actual installable ZIP. Already compressed ZIP
artifacts are uploaded without another compression pass. Pandoc is disabled
because GitHub-only publication does not need markup conversion for WoWInterface.

## Version policy

The consolidated testing release is 0.2.0. While testing, fixes increment the
patch number and features or breaking changes increment the minor number. Release Please is
configured to keep breaking changes below 1.0 until stability is explicitly
declared. When ready, put `Release-As: 1.0.0` in the commit body of a reviewed
change and inspect the resulting release PR before merging it.

VERSION, the release manifest, and the TOC version must agree. Release Please
maintains them and CHANGELOG.md. Addon settings schema versions are independent.

## GitHub App setup

Give the shared release App access to calmcacil/CalmEUITweaks, with Contents and
Pull requests read/write permissions. Add repository Actions secrets named
RELEASE_APP_ID and RELEASE_APP_PRIVATE_KEY. Existing secrets on CalmChat do not
automatically carry over. The coordinator reports missing configuration in its
run summary and skips release PR creation until both secrets are available.

Keep default workflow permissions read-only. Only the publisher receives
contents: write. The App token lets its release event trigger the publisher.

## Publishing

1. Merge ordinary Conventional Commit changes to main.
2. Review and merge the Release Please PR.
3. Release Please creates the version tag and GitHub Release.
4. Publish release verifies the published release before checking out its exact
   tag, verifies it belongs to main, and runs tests and packaging with read-only
   permissions. A separate job validates the candidate against the original
   source and uploads assets using contents: write. Publishing tools come from
   the workflow's trusted commit, independently of the release source.
5. Assets are CalmEUITweaks-vX.Y.Z.zip, release.json, and checksums.txt.

The ZIP installs as CalmEUITweaks/, matching the GitHub repository and TOC name.
The package targets Forever interface 16001, requires EllesmereUI, and excludes
tests and development helpers. Metadata uses flavor forever. No external addon
hosting credentials are needed for GitHub publication.

When no release exists, publish the prepared 0.2.0 baseline after verification.
The release coordinator waits for that baseline before creating version bumps.
Changes limited to CI, tests, or
documentation do not open a release PR; the coordinator looks for addon changes
since the latest release. Those supporting changes ship with the next addon release.

## Recovery

If assets are missing, manually run Publish release with the existing tag.
Reruns reuse and verify existing assets and upload only missing ones. Never move
or recreate a published tag. Fix incorrect published source in a new release.
Run recovery from main. Trusted publishing helper changes on main apply to old
release tags without moving those tags or changing their source.

Download all three assets and run `sha256sum --check checksums.txt`. Roll back
by installing an earlier verified ZIP. Font assets and registration belong in
a separate personal SharedMedia addon and are excluded from this plugin.
