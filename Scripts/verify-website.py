#!/usr/bin/env python3
"""Validate built QuickTile pages, local assets, links, and publication metadata.

Does not contact the network. Visual and hosted-page checks remain separate.
"""
from __future__ import annotations

import argparse
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import runpy
import sys
from urllib.parse import quote, unquote, urlparse
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
BUILD = runpy.run_path(str(ROOT / "Scripts/build-website.py"))


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.ids: list[str] = []
        self.links: list[str] = []
        self.tags: list[str] = []
        self.lang: str | None = None
        self.viewport = False
        self.description = False
        self.title_text = ""
        self.in_title = False
        self.canonical: str | None = None
        self.errors: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_dict = dict(attrs)
        self.tags.append(tag)
        if "id" in attrs_dict:
            self.ids.append(attrs_dict["id"] or "")
        if tag == "html":
            self.lang = attrs_dict.get("lang")
        if tag == "meta":
            if attrs_dict.get("name") == "viewport":
                self.viewport = "width=device-width" in (attrs_dict.get("content") or "")
            if attrs_dict.get("name") == "description":
                self.description = bool(attrs_dict.get("content"))
        if tag == "title":
            self.in_title = True
        if tag == "link" and attrs_dict.get("rel") == "canonical":
            self.canonical = attrs_dict.get("href")
        for attr in ("href", "src", "action"):
            if attrs_dict.get(attr):
                self.links.append(attrs_dict[attr] or "")
        if tag == "script":
            self.errors.append("Scripts are not needed for this static site.")
        if tag in ("iframe", "form"):
            self.errors.append(f"Unexpected data-collecting or embedded element: {tag}.")
        if tag == "img" and "alt" not in attrs_dict:
            self.errors.append("An image is missing alternative text.")
        if any(name.lower().startswith("on") for name in attrs_dict):
            self.errors.append("Inline event handlers are not allowed.")

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self.in_title = False

    def handle_data(self, data: str) -> None:
        if self.in_title:
            self.title_text += data


def verify(site: Path, config_path: Path, publication: bool, standalone: bool = False) -> list[str]:
    errors: list[str] = []
    # Exported folders contain publication files, never draft metadata.
    publication = publication or standalone
    config = BUILD["read_config"](config_path)
    if publication:
        errors.extend(BUILD["publication_errors"](config))
    info_path = site / "build-info.json"
    if not info_path.exists() and not standalone:
        return errors + ["Missing build-info.json. Build the site first."]
    info = json.loads(info_path.read_text(encoding="utf-8")) if info_path.exists() else {}
    if publication and (not standalone or info) and info.get("mode") != "publish":
        errors.append("A draft build cannot be published; rebuild with --mode publish.")
    if not standalone and info.get("site") not in ("support", "privacy"):
        errors.append("Build metadata is missing a valid support/privacy site identity.")
    pages: dict[Path, PageParser] = {}
    for filename in ("index.html", "support.html", "privacy.html"):
        path = site / filename
        if not path.exists():
            errors.append(f"Missing {filename}.")
            continue
        if path.is_symlink() or not path.is_file():
            errors.append(f"{filename}: expected a regular static file, not a link or directory.")
            continue
        text = path.read_text(encoding="utf-8")
        page = PageParser()
        page.feed(text)
        pages[path.resolve()] = page
        errors.extend(f"{filename}: {error}" for error in page.errors)
        if "{{" in text or "}}" in text:
            errors.append(f"{filename}: unresolved template token.")
        if not text.lower().startswith("<!doctype html>"):
            errors.append(f"{filename}: missing HTML doctype.")
        if page.lang != "en" or not page.viewport or not page.description or not page.title_text.strip():
            errors.append(f"{filename}: missing language, responsive viewport, description, or title.")
        if page.tags.count("h1") != 1 or page.tags.count("main") != 1 or "main" not in page.ids:
            errors.append(f"{filename}: use one primary heading and one main landmark.")
        if "#main" not in page.links or "nav" not in page.tags:
            errors.append(f"{filename}: missing skip link or navigation.")
        if len(set(page.ids)) != len(page.ids):
            errors.append(f"{filename}: duplicate element identifiers.")
        if publication:
            if not page.canonical or urlparse(page.canonical).scheme != "https":
                errors.append(f"{filename}: missing production canonical URL.")
            if "Local preview" in text or "local draft" in text:
                errors.append(f"{filename}: draft copy appears in a publication build.")
            expected = {
                "support.html": {config["supportURL"]},
                "privacy.html": {config["privacyURL"]},
                "index.html": {config["siteURL"], config["privacyURL"]},
            }[filename]
            if info.get("site") in ("support", "privacy") and filename == "index.html":
                expected = {config["privacyURL"] if info["site"] == "privacy" else config["siteURL"]}
            if page.canonical not in expected:
                errors.append(f"{filename}: canonical URL does not match the configured official page.")
            support_contact = "mailto:" + quote(config["supportEmail"], safe="@.+-") if config["supportEmail"] else config["supportRepositoryURL"].rstrip("/") + "/issues"
            if support_contact not in page.links:
                errors.append(f"{filename}: configured support contact is missing.")
            for field in ("supportURL", "privacyURL"):
                if config[field] not in page.links:
                    errors.append(f"{filename}: configured {field} navigation link is missing.")
        if not config["appStoreURL"] and "Get the iPhone app</a>" in text:
            errors.append(f"{filename}: unconfigured App Store button.")
        if not config["macDownloadURL"] and "Download Mac companion</a>" in text:
            errors.append(f"{filename}: unconfigured companion download button.")
        if not config["repositoryURL"] and ("View the source code</a>" in text or ">Source</a>" in text):
            errors.append(f"{filename}: a support repository must not be labelled as app source.")
    for path, page in pages.items():
        for address in page.links:
            parsed = urlparse(address)
            if parsed.scheme:
                if parsed.scheme not in ("https", "mailto"):
                    errors.append(f"{path.name}: unsupported URL scheme in {address}.")
                continue
            if parsed.netloc or parsed.path.startswith("/"):
                errors.append(f"{path.name}: use project-path-safe relative links: {address}.")
                continue
            target = (path.parent / unquote(parsed.path)).resolve() if parsed.path else path
            if target != site.resolve() and site.resolve() not in target.parents:
                errors.append(f"{path.name}: link escapes build directory: {address}.")
                continue
            if not target.exists():
                errors.append(f"{path.name}: broken local link: {address}.")
            elif parsed.fragment and target in pages and parsed.fragment not in pages[target].ids:
                errors.append(f"{path.name}: missing anchor: {address}.")
    css = site / "assets/site.css"
    assets = site / "assets"
    if not assets.is_dir() or assets.is_symlink():
        errors.append("Expected a regular local assets directory.")
    else:
        for asset in assets.iterdir():
            if asset.is_symlink() or not asset.is_file() or asset.suffix not in (".css", ".svg"):
                errors.append(f"Unexpected or unsafe static asset: {asset.name}.")
    if not css.exists():
        errors.append("Missing stylesheet.")
    else:
        content = css.read_text(encoding="utf-8")
        for required in (":focus-visible", "prefers-reduced-motion", "prefers-color-scheme", "@media(max-width:"):
            if required not in content:
                errors.append(f"Stylesheet is missing {required} handling.")
        if "@import" in content or re.search(r"url\s*\(\s*['\"]?(?:https?:|//|data:|javascript:)", content, re.IGNORECASE):
            errors.append("Stylesheet must not load remote resources.")
    for name in ("mark.svg", "favicon.svg"):
        svg = site / "assets" / name
        if not svg.exists():
            errors.append(f"Missing {name}.")
            continue
        element = ET.fromstring(svg.read_text(encoding="utf-8"))
        for node in element.iter():
            if node.tag.rsplit("}", 1)[-1] in ("script", "foreignObject") or any(key.lower().startswith("on") for key in node.attrib):
                errors.append(f"{name}: active content is not allowed in static artwork.")
            for key, value in node.attrib.items():
                if key.rsplit("}", 1)[-1] in ("href", "src") and not value.startswith("#"):
                    errors.append(f"{name}: externally referenced artwork is not allowed.")
        rects = [node for node in element.iter() if node.tag.endswith("rect") and node.attrib.get("width") == "236"]
        coordinates = {(int(node.attrib["x"]), int(node.attrib["y"])) for node in rects}
        if coordinates != {(244, 244), (544, 244), (244, 544), (544, 544)} or any(node.attrib.get("height") != "236" or node.attrib.get("rx") != "55" for node in rects):
            errors.append(f"{name}: four-square mark does not match the aligned app geometry.")
    if not (site / ".nojekyll").exists():
        errors.append("Missing .nojekyll for GitHub Pages.")
    if publication and (not (site / "sitemap.xml").exists() or not (site / "robots.txt").exists()):
        errors.append("Publication metadata is missing.")
    elif publication:
        robots = (site / "robots.txt").read_text(encoding="utf-8")
        if "Disallow: /" in robots:
            errors.append("Draft search-indexing policy appears in publication output.")
        sitemap = ET.parse(site / "sitemap.xml")
        allowed_urls = {config["siteURL"], config["supportURL"], config["privacyURL"]}
        urls = {node.text for node in sitemap.iter() if node.tag.rsplit("}", 1)[-1] == "loc"}
        if not urls or not urls <= allowed_urls:
            errors.append("Sitemap destinations do not match the configured official pages.")
    if (site / "config.json").exists():
        errors.append("The source configuration must not be copied into the public output.")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", type=Path, default=ROOT / ".build/website/support")
    parser.add_argument("--config", type=Path, default=ROOT / "website/config.json")
    parser.add_argument("--publish", action="store_true", help="Require complete production configuration and a publication build")
    parser.add_argument("--standalone", action="store_true", help="Validate exported publication files without requiring build-info.json")
    args = parser.parse_args()
    try:
        errors = verify(args.site, args.config, args.publish, args.standalone)
    except (OSError, ValueError, json.JSONDecodeError, ET.ParseError) as error:
        errors = [str(error)]
    if errors:
        print("Website verification failed:\n" + "\n".join("- " + item for item in errors), file=sys.stderr)
        return 1
    kind = "standalone publication" if args.standalone else ("publication" if args.publish else "draft")
    print(f"Verified {kind} website at {args.site}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
