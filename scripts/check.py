"""Validate release versions, TOC contents, and installable archives."""

import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import zipfile

ROOT = Path(os.environ.get("CALM_RELEASE_SOURCE_ROOT", Path(__file__).resolve().parent.parent)).resolve()
ADDON = "CalmEUITweaks"
FONT_EXTENSIONS = {".ttf", ".otf", ".ttc", ".woff", ".woff2"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_toc(text, version):
    fields = dict(re.findall(r"^## ([^:]+):\s*([^\r\n]+)", text, re.M))
    require(fields.get("Interface") == "16001", "TOC interface must be 16001")
    require(fields.get("Version") == version, "TOC version does not match release version")
    require(fields.get("RequiredDeps") == "EllesmereUI", "Required EllesmereUI dependency is missing")
    require(fields.get("SavedVariables") == "CalmUITweaksDB", "Account saved variables changed")
    require(fields.get("SavedVariablesPerCharacter") == "CalmUITweaksCharDB", "Character saved variables changed")
    return [line.strip().replace("\\", "/") for line in text.splitlines()
            if line.strip() and not line.lstrip().startswith("#")]


def check_source():
    for directory in ROOT.iterdir():
        if directory.is_dir() and not directory.name.startswith("."):
            for file in directory.rglob("*"):
                require(file.suffix.lower() not in FONT_EXTENSIONS,
                        f"Font asset in source: {file.relative_to(ROOT)}")
        else:
            require(directory.suffix.lower() not in FONT_EXTENSIONS,
                    f"Font asset in source: {directory.name}")
    version = (ROOT / "VERSION").read_text().strip()
    require(re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", version), "VERSION must be X.Y.Z")
    manifest = json.loads((ROOT / ".release-please-manifest.json").read_text())
    require(manifest["."] == version, "Release manifest and VERSION differ")
    text = (ROOT / f"{ADDON}.toc").read_text()
    require("# x-release-please-start-version\n" in text and "# x-release-please-end" in text,
            "TOC release-please markers are missing")
    for file in validate_toc(text, version):
        require((ROOT / file).is_file(), f"Missing runtime file: {file}")
        if file.endswith(".lua"):
            source = (ROOT / file).read_text(encoding="utf-8-sig")
            require(not re.search(r"\bOnUpdate\b|\bNewTicker\b", source),
                    f"Continuous update callbacks are prohibited: {file}")
    print(f"Source validated for {ADDON} {version}")


def check_package(archive, version):
    with zipfile.ZipFile(archive) as package:
        names = package.namelist()
        require(names and len(names) == len(set(names)), "Archive is empty or contains duplicate paths")
        for name in names:
            parts = PurePosixPath(name).parts
            require(PurePosixPath(name).suffix.lower() not in FONT_EXTENSIONS,
                    f"Font asset in package: {name}")
            require(parts and parts[0] == ADDON and ".." not in parts and "\\" not in name,
                    f"Invalid package path: {name}")
            if len(parts) > 1:
                require(parts[1] not in {"tests", "scripts", "docs", "SPEC.md", "VERSION",
                                        "release-please-config.json"} and not parts[1].startswith("."),
                        f"Development file in package: {name}")
        text = package.read(f"{ADDON}/{ADDON}.toc").decode("utf-8-sig")
        files = validate_toc(text, version)
        source_files = validate_toc((ROOT / f"{ADDON}.toc").read_text(), version)
        require(files == source_files, "Packaged TOC load order differs from source")
        for file in files:
            content = package.read(f"{ADDON}/{file}")
            source = (ROOT / file).read_bytes()
            if file.endswith(".lua"):
                content = content.replace(b"\r\n", b"\n")
                source = source.replace(b"\r\n", b"\n")
            require(content == source, f"Packaged file differs from source: {file}")
    print(f"Package validated: {archive} ({version}, Forever 16001)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", nargs="?")
    parser.add_argument("version", nargs="?")
    args = parser.parse_args()
    try:
        if args.archive:
            check_package(args.archive, args.version or (ROOT / "VERSION").read_text().strip())
        else:
            check_source()
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as error:
        parser.exit(1, f"error: {error}\n")
