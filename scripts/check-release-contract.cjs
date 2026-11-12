// Run against the dependency version locked by the pinned Release Please action.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const moduleRoot = path.resolve(process.argv[2]);
const { Manifest } = require(moduleRoot);
const { Version } = require(path.join(moduleRoot, "build/src/version.js"));
const { buildVersioningStrategy } = require(path.join(moduleRoot, "build/src/factories/versioning-strategy-factory.js"));
const root = path.resolve(__dirname, "..");
const github = {
    repository: { owner: "calmcacil", repo: "CalmEUITweaks" },
    getFileJson: async (file) => JSON.parse(fs.readFileSync(path.join(root, file), "utf8")),
};

async function main() {
    const dependency = require(path.join(moduleRoot, "package.json"));
    console.log(`Release Please ${dependency.version} parser/versioning contract`);
    assert.equal(dependency.version, "17.6.0");
    const cases = [
        ["stable", "1.0.1", "feat", false, "1.1.0"],
        ["stable", "1.0.1", "fix", false, "1.0.2"],
        ["stable", "1.0.1", "feat", true, "2.0.0"],
        ["alpha", "1.0.1", "feat", false, "1.1.0-alpha.1"],
        ["alpha", "1.1.0-alpha.1", "feat", false, "1.1.0-alpha.2"],
        ["alpha", "1.1.0-alpha.1", "fix", false, "1.1.0-alpha.2"],
        ["stable", "1.1.0-alpha.1", "feat", false, "1.1.0"],
        ["stable", "1.1.0-alpha.1", "fix", false, "1.1.0"],
    ];
    const strategies = {};
    for (const channel of ["stable", "alpha"]) {
        const configFile = channel === "alpha" ? ".github/release-please-alpha-config.json" : "release-please-config.json";
        const manifest = await Manifest.fromManifest(github, "main", configFile);
        const config = manifest.repositoryConfig["."];
        assert.equal(config.prerelease, channel === "alpha");
        assert.equal(config.draft === true, channel === "alpha");
        assert.equal(config.forceTag === true, channel === "alpha");
        assert.equal(config.versioning, "prerelease");
        strategies[channel] = buildVersioningStrategy({ github, ...config, type: config.versioning });
    }
    for (const [channel, current, type, breaking, expected] of cases) {
        const actual = strategies[channel].bump(Version.parse(current), [{ type, breaking, notes: [] }]).toString();
        assert.equal(actual, expected);
        console.log(`${channel}: ${current} + ${breaking ? "breaking " : ""}${type} -> ${actual}`);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
