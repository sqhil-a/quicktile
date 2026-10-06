#!/usr/bin/env python3
"""Export validated static pages into standalone support/privacy folders.

Never initializes Git, pushes, publishes, enables Pages, or changes unknown files.
Repeated exports update only unmodified files previously owned by this exporter.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import runpy
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VERIFY = runpy.run_path(str(ROOT / "Scripts/verify-website.py"))
BUILD = runpy.run_path(str(ROOT / "Scripts/build-website.py"))
MANIFEST = ".quicktile-site-export.json"
PUBLIC_FILES = ("index.html", "support.html", "privacy.html", ".nojekyll", "robots.txt", "sitemap.xml")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_path(root: Path, relative: str) -> Path:
    parts = Path(relative).parts
    if not parts or any(part in ("..", ".") for part in parts) or Path(relative).is_absolute():
        raise ValueError(f"Unsafe export path: {relative}")
    target = root / relative
    for ancestor in (target, *target.parents):
        if ancestor == root.parent:
            break
        if ancestor.is_symlink():
            raise ValueError(f"Refusing a symlink in the destination: {ancestor}")
    return target


def standalone_readme(site: str, config: dict[str, str]) -> bytes:
    repository = config["supportRepositoryURL" if site == "support" else "privacyRepositoryURL"].rstrip("/")
    root_url = config["siteURL" if site == "support" else "privacySiteURL"].rstrip("/") + "/"
    page_url = config["supportURL" if site == "support" else "privacyURL"]
    description = "Setup, troubleshooting, and privacy links" if site == "support" else "QuickTile privacy policy"
    text = f"""# QuickTile {site}

{description} for the QuickTile iPhone app and Mac companion.

- Repository: {repository}
- Pages root: {root_url}
- Official {'support' if site == 'support' else 'privacy'} page: {page_url}
- Contact: {config['supportEmail'] or config['supportRepositoryURL'].rstrip('/') + '/issues'}

This is a static documentation site, not the QuickTile app source repository.
It uses system fonts, local original vector assets, and no tracking or scripts.

## Publish when ready

These files are exported locally; no publication is implied.
Choose **Settings → Pages → Build and deployment → Source: GitHub Actions**.
The included workflow can deploy after a push to `main` or a manual run on `main`.
It uploads only public HTML, CSS/SVG assets, `.nojekyll`, `robots.txt`, and the sitemap.
README, workflow files, build metadata, and the export manifest are excluded.

The authored templates and exporter live in the QuickTile workspace under
`website/` and `Scripts/`. Re-export from there after changes. The exporter refuses
to overwrite files changed here; reconcile edits in the source workspace first.

Workflow reference: https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages
"""
    return text.encode("utf-8")


def files_for(site: str, build_root: Path, config_path: Path, config: dict[str, str]) -> dict[str, bytes]:
    source = build_root / site
    errors = VERIFY["verify"](source, config_path, True)
    if errors:
        raise ValueError(f"{site} output is not publication-ready:\n" + "\n".join(errors))
    info = json.loads((source / "build-info.json").read_text(encoding="utf-8"))
    if info.get("site") != site:
        raise ValueError(f"The {site} folder contains the wrong site build.")
    result = {name: (source / name).read_bytes() for name in PUBLIC_FILES}
    assets = source / "assets"
    if assets.is_symlink():
        raise ValueError("The build assets directory cannot be a symlink.")
    for path in sorted(assets.iterdir()):
        if not path.is_file() or path.is_symlink() or path.suffix not in (".css", ".svg"):
            raise ValueError(f"Unexpected build asset: {path}")
        result["assets/" + path.name] = path.read_bytes()
    result["README.md"] = standalone_readme(site, config)
    result[".github/workflows/pages.yml"] = (ROOT / "Configuration/StandalonePages.yml").read_bytes()
    result[".gitignore"] = (MANIFEST + "\n.DS_Store\n_site/\n").encode("utf-8")
    return result


def preflight(destination: Path, desired: dict[str, bytes]) -> dict[str, str]:
    if destination.is_symlink() or (destination.exists() and not destination.is_dir()):
        raise ValueError(f"Destination is not a regular directory: {destination}")
    manifest = destination / MANIFEST
    previous: dict[str, str] = {}
    if manifest.exists():
        if manifest.is_symlink():
            raise ValueError(f"Unsafe manifest: {manifest}")
        value = json.loads(manifest.read_text(encoding="utf-8"))
        if value.get("version") != 1 or not isinstance(value.get("files"), dict):
            raise ValueError(f"Unrecognized export manifest: {manifest}")
        previous = value["files"]
    elif destination.exists():
        unknown = [path.name for path in destination.iterdir() if path.name not in (".git", ".DS_Store")]
        if unknown:
            raise ValueError(f"Destination has unknown files; nothing was overwritten: {destination} ({', '.join(unknown)})")
    for relative in set(previous) | set(desired):
        target = safe_path(destination, relative)
        if not target.exists():
            continue
        if not target.is_file():
            raise ValueError(f"Destination file is not regular: {target}")
        current = digest(target.read_bytes())
        wanted = digest(desired[relative]) if relative in desired else None
        if current != previous.get(relative) and current != wanted:
            raise ValueError(f"File has local or unknown changes; nothing was overwritten: {target}")
    return previous


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=".quicktile-export-", dir=path.parent, delete=False) as temporary:
        temporary.write(data)
        temporary_path = Path(temporary.name)
    try:
        temporary_path.replace(path)
    finally:
        temporary_path.unlink(missing_ok=True)


def export(destination: Path, desired: dict[str, bytes], previous: dict[str, str], site: str) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for relative, content in desired.items():
        target = safe_path(destination, relative)
        if not target.exists() or target.read_bytes() != content:
            atomic_write(target, content)
    # Only unchanged files proven to belong to an earlier export may be removed.
    for relative in set(previous) - set(desired):
        target = safe_path(destination, relative)
        if target.exists():
            target.unlink()
    metadata = {"version": 1, "site": site, "files": {name: digest(data) for name, data in desired.items()}}
    atomic_write(destination / MANIFEST, (json.dumps(metadata, indent=2, sort_keys=True) + "\n").encode("utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-root", type=Path, default=ROOT / ".build/website")
    parser.add_argument("--destination-root", type=Path, default=ROOT.parent)
    parser.add_argument("--config", type=Path, default=ROOT / "website/config.json")
    parser.add_argument("--dry-run", action="store_true", help="Validate both outputs and destinations without writing")
    args = parser.parse_args()
    try:
        config = BUILD["read_config"](args.config)
        planned = []
        for site in ("support", "privacy"):
            destination = args.destination_root / ("quicktile-" + site)
            desired = files_for(site, args.build_root, args.config, config)
            previous = preflight(destination, desired)
            planned.append((site, destination, desired, previous))
        for site, destination, desired, previous in planned:
            if not args.dry_run:
                export(destination, desired, previous, site)
            print(f"{'Would export' if args.dry_run else 'Exported'} {site} static pages to {destination}")
        print("No Git repository was initialized, and nothing was pushed or published.")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Website export failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
