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
Lua is built only when missing, using a checksum-verified, commit-pinned
MIT-licensed Lua 5.1.5 archive from GitHub, without Ubuntu mirror dependencies. Package snapshots are rebuilt
for every change to verify the actual installable ZIP. Already compressed ZIP
artifacts are uploaded without another compression pass. Pandoc is disabled
because GitHub-only publication does not need markup conversion for WoWInterface.

## Version policy

Dependabot checks GitHub Actions weekly on Monday at 05:30 Europe/Oslo and groups
action updates into one PR. Actions retain full SHA pins. Ubuntu runner upgrades
are manual: workflows stay on 24.04 until a newer image and the pinned actionlint
support are verified together. Ubuntu 26.04 jobs currently run, but actionlint 1.7.12 rejects their
runner label. Do not suppress workflow lint to accept an automatic OS upgrade.

The version in VERSION, the Release Please manifest and the TOC must agree.
Release Please maintains those files and CHANGELOG.md together; do not hand-bump
individual version files. Saved-data lineage/schema metadata is independent of
release versions. Review the generated version and release channel before
merging a release PR: merging starts stable publication or creates an alpha draft.

Stable publication requires the [in-game checklist](../SPEC.md#in-game-candidate-checklist)
and explicit publication approval. An explicitly authorized alpha can be shared
for testing with outstanding in-game verification documented in its release
notes; it must not claim stable readiness. Alpha support in the publisher does
not itself authorize creating a tag, release or upload.

## GitHub App setup

Give the shared release App access to calmcacil/CalmEUITweaks, with Contents and
Pull requests read/write permissions. Add repository Actions secrets named
RELEASE_APP_ID and RELEASE_APP_PRIVATE_KEY. Existing secrets on CalmChat do not
automatically carry over. The coordinator reports missing configuration in its
run summary and skips release PR creation until both secrets are available.

Keep default workflow permissions read-only. Only the publisher receives
contents: write. The App token lets its release event trigger the publisher.

## Publishing

After user testing and explicit publication approval:

1. Merge the reviewed Conventional Commit changes to main.
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

### Alpha testing releases

The source validator and trusted publisher accept `X.Y.Z-alpha.N` versions and
`vX.Y.Z-alpha.N` tags, where N is a nonnegative integer without leading zeroes.
Stable tags must point to stable GitHub Releases; alpha tags must have GitHub's
prerelease flag enabled. Both channels require published, non-draft releases.
The publisher verifies release identity and channel before checkout and again
before uploading assets. An alpha must not be selected as the latest stable
release. The stable coordinator excludes prereleases from its change baseline.

Release creation remains managed by Release Please. Run the Release workflow
from main with channel `alpha` to create or update the release PR for alpha
testing. Inspect the generated VERSION, manifest, TOC and changelog together.
The initial suffix is `alpha.1`; subsequent alpha releases increment the suffix
through Release Please. The numeric version follows conventional commits and
the released baseline; inspect the proposed version rather than assuming a
particular next release. Do not manually stamp versions or relabel an existing
stable release. A pending stable release PR is updated for the requested channel;
do not merge it before the intended channel/version is visible and CI passes.

The workflow separates creation of releases from creation of release PRs.
Release creation always selects the channel from the merged manifest; a manual
channel request changes only the next release PR. This prevents a stable
promotion request from publishing a still-alpha version as stable. Normal push
runs and channel `automatic` preserve the current manifest's channel. There is
one serialized Release Please PR stream for main, rather than concurrent stable
and alpha version branches.

After alpha testing and explicit stable publication approval, run Release on
main with channel `stable`. Review and merge the generated promotion PR. The
configured prerelease versioning strategy removes the prerelease suffix for
promotion; both configs retain the same version-file and changelog settings.
Normal stable development keeps stable versions. Neither starting an alpha nor
promoting it uploads assets until the reviewed release PR is merged and Release
Please creates its tagged release. Alpha releases are drafts first; they do not
trigger asset publication until their testing notes are reviewed and the draft
is published as described below.

#### Review and publish the alpha draft

The alpha config sets `draft: true` and `force-tag-creation: true`. Release Please
creates an immutable tag at the reviewed release commit while leaving the GitHub
Release unpublished. The tag must remain unchanged. Before publishing the draft:

1. Read back its tag, target commit, draft status and prerelease flag. Verify the
   tag belongs to main and its version matches the release PR metadata.
2. Add concrete testing instructions and limitations to the generated notes.
   Include the tested addon/client versions, how to enable the default-off skin
   and reload, implemented coverage and exceptions, dependency/conflict behavior,
   and the exact in-game visual/interaction/combat and CPU/memory checks still
   pending. Do not describe automated mocks as in-game verification.
3. Review the complete notes from a local file, then publish with
   `gh release edit <tag> --notes-file <notes-file> --draft=false --prerelease --latest=false`.
   This is the public publication action and requires the task's publication
   authorization. The published event starts the trusted publisher.
4. Check the publisher run and download/read back all three assets, release
   notes and prerelease status. Verify checksums and package contents. The
   alpha must remain excluded from latest stable.

Configuration follows the upstream [manifest guide](https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md)
and [versioning strategies](https://github.com/googleapis/release-please/blob/main/docs/customizing.md).
The manifest key is `versioning: prerelease`, with `prerelease: true`,
`prerelease-type: alpha.1`, `draft: true` and `force-tag-creation: true` for alpha,
and `prerelease: false` with normal publication for stable.
When changing these options or the pinned Release Please action, run
`node scripts/check-release-contract.cjs <release-please-module-directory>`
against the dependency version in that action's package-lock.json. This optional
contract check uses the real manifest parser and versioning strategy to verify
stable feature/fix/breaking bumps, alpha numbering and suffix removal during
promotion. The current pinned action locks release-please 17.6.0; install it in
a temporary directory with npm lifecycle scripts disabled. It is not an addon
runtime dependency and does not need to be installed for ordinary Lua checks.

Release tooling changes must reach main before they can be used for publication.
The release source commit must also be an ancestor of main. Feature-branch tags
are not supported by the trusted publisher. Prepare and review changes through
the normal PR/check process before creating the alpha release.

Before alpha publication, run source/regression checks, build the exact package,
validate it with `bash scripts/check-package.sh <archive> <version>`, and record
the covered surfaces, known limitations and unavailable game checks. Download
the final assets and verify checksums after publication. Alpha publication is a
testing milestone; stable promotion still requires completed in-game acceptance
and explicit stable publication approval.

For testing before an alpha is published, the Required CI job
uploads an installable `calmuitweaks-package-snapshot` artifact for seven days.
This artifact is not a GitHub prerelease and has no public version-channel claim.

The historical 0.2.0 bootstrap applied only when no release existed. The current
coordinator still waits for a published baseline before creating automatic bumps;
if that gate is encountered, stop and agree an approved bootstrap plan rather
than publishing an obsolete version or bypassing testing. Changes limited to CI,
tests or documentation do not open a release PR; the coordinator looks for addon
changes since the latest release. Supporting changes ship with the next addon release.

## Recovery

If assets are missing, manually run Publish release with the existing tag.
Reruns reuse and verify existing assets and upload only missing ones. Never move
or recreate a published tag. Fix incorrect published source in a new release.
Run recovery from main. Trusted publishing helper changes on main apply to old
release tags without moving those tags or changing their source.

Download all three assets and run `sha256sum --check checksums.txt`. Before a
rollback, back up SavedVariables with the client closed; install an earlier
verified ZIP with a compatible backup. Older releases ignore `calm_forever` and
cannot enforce downgrade safety. Font assets and registration belong in a
separate personal SharedMedia addon and are excluded from this plugin.
