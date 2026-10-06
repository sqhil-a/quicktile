#!/usr/bin/env python3
"""Build a dependency-free, project-path-safe QuickTile website.

Drafts permit intentionally empty release URLs. Publish mode validates them first.
No requests are made and no content is published by this script.
"""
from __future__ import annotations

import argparse
import html
import json
from pathlib import Path
import shutil
import sys
from urllib.parse import quote, urlparse

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "website"
KEYS = ("repositoryURL", "supportRepositoryURL", "privacyRepositoryURL", "supportEmail", "macDownloadURL", "appStoreURL", "siteURL", "privacySiteURL", "supportURL", "privacyURL")


def read_config(path: Path) -> dict[str, str]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError("Website configuration must be a JSON object.")
    unknown = set(raw) - set(KEYS)
    if unknown:
        raise ValueError(f"Unknown website configuration fields: {', '.join(sorted(unknown))}")
    result = {key: raw.get(key, "") for key in KEYS}
    for key, value in result.items():
        if not isinstance(value, str) or value != value.strip() or any(ord(c) < 32 for c in value):
            raise ValueError(f"{key} must be a trimmed, single-line string.")
        if value and key.endswith("URL"):
            parts = urlparse(value)
            if parts.scheme != "https" or not parts.hostname or parts.username or parts.password or any(c.isspace() for c in value):
                raise ValueError(f"{key} must be an HTTPS URL without credentials.")
            if key not in ("macDownloadURL", "appStoreURL") and (parts.query or parts.fragment):
                raise ValueError(f"{key} cannot contain a query or fragment.")
    email = result["supportEmail"]
    if email and (email.count("@") != 1 or any(c.isspace() for c in email) or "." not in email.rsplit("@", 1)[1]):
        raise ValueError("supportEmail must be an email address.")
    return result


def publication_errors(config: dict[str, str]) -> list[str]:
    errors = []
    for field in ("siteURL", "privacySiteURL", "supportURL", "privacyURL", "supportRepositoryURL", "privacyRepositoryURL"):
        if not config[field]:
            errors.append(f"{field} is required for publication.")
    if not config["supportEmail"] and not config["supportRepositoryURL"]:
        errors.append("A support contact is required: supportEmail or a support issue tracker.")
    for field in ("siteURL", "privacySiteURL", "supportURL", "privacyURL", "supportRepositoryURL", "privacyRepositoryURL", "repositoryURL"):
        host = urlparse(config[field]).hostname or ""
        if host in ("example.com", "example.org", "localhost") or host.endswith(".invalid"):
            errors.append(f"{field} must use a real project-owned destination.")
    return errors


def link(url: str, label: str, css: str = "") -> str:
    cls = f' class="{html.escape(css, quote=True)}"' if css else ""
    return f'<a{cls} href="{html.escape(url, quote=True)}">{html.escape(label)}</a>'


def header(filename: str, config: dict[str, str], site: str) -> str:
    mark = (SOURCE / "assets/mark.svg").read_text(encoding="utf-8")
    mark = mark.replace('<svg ', '<svg aria-hidden="true" focusable="false" ')
    navigation = []
    for name, label, destination in (("support.html", "Support", config["supportURL"] or "./support.html"), ("privacy.html", "Privacy", config["privacyURL"] or "./privacy.html")):
        current = ' aria-current="page"' if filename == name or (site == "privacy" and filename == "index.html" and name == "privacy.html") else ""
        navigation.append(f'<a href="{html.escape(destination, quote=True)}"{current}>{label}</a>')
    home = config["siteURL"] or "./index.html"
    return f'<header class="header"><a class="brand" href="{html.escape(home, quote=True)}" aria-label="QuickTile home">{mark}<span>QuickTile</span></a><nav aria-label="Main navigation">{"".join(navigation)}</nav></header>'


def build(config: dict[str, str], destination: Path, mode: str, site: str) -> None:
    if destination.resolve() == SOURCE.resolve() or SOURCE.resolve() in destination.resolve().parents:
        raise ValueError("Build output cannot be the website source directory.")
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copytree(SOURCE / "assets", destination / "assets", dirs_exist_ok=True)
    repository = config["repositoryURL"].rstrip("/")
    support_repository = config["supportRepositoryURL"].rstrip("/")
    contact = ""
    if config["supportEmail"]:
        email = config["supportEmail"]
        contact = '<p class="contact">' + link("mailto:" + quote(email, safe="@.+-"), email) + '</p>'
    elif support_repository:
        contact = '<p class="contact">' + link(support_repository + "/issues", "Report an issue") + '</p>'
    else:
        contact = '<p class="note">A public support contact will be added before release. This is a local draft.</p>'
    source_link = '<p>' + link(repository, "View the source code") + '</p>' if repository else ""
    if support_repository:
        contact += '<p class="contact">' + link(support_repository + "/issues", "Report a reproducible issue") + '</p>'
    downloads = []
    if config["appStoreURL"]:
        downloads.append(link(config["appStoreURL"], "Get the iPhone app", "button"))
    if config["macDownloadURL"]:
        downloads.append(link(config["macDownloadURL"], "Download Mac companion", "button" if not downloads else "button secondary"))
    footer_links = [link(config["supportURL"] or "./support.html", "Support"), link(config["privacyURL"] or "./privacy.html", "Privacy")]
    if repository:
        footer_links.append(link(repository, "Source"))
    footer = '<footer class="footer"><span>QuickTile · Support and privacy</span><div class="footer-links">' + "".join(footer_links) + '</div></footer>'
    for filename in ("index.html", "support.html", "privacy.html"):
        if filename == "privacy.html" or (site == "privacy" and filename == "index.html"):
            canonical = config["privacyURL"]
        elif filename == "support.html":
            canonical = config["supportURL"]
        else:
            canonical = config["siteURL"]
        replacements = {
            "HEADER": header(filename, config, site), "FOOTER": footer,
            "CONTACT": contact, "SOURCE_LINK": source_link,
            "DOWNLOAD_ACTIONS": "".join(downloads),
            "CANONICAL": f'<link rel="canonical" href="{html.escape(canonical, quote=True)}">' if canonical else "",
            "DRAFT_NOTICE": '<p class="draft-note" role="note">Local preview · Release and support links are not configured.</p>' if mode == "draft" and (not config["siteURL"] or not config["supportURL"]) else "",
        }
        source_name = "privacy.html" if site == "privacy" and filename == "index.html" else filename
        content = (SOURCE / source_name).read_text(encoding="utf-8")
        for name, value in replacements.items():
            content = content.replace("{{" + name + "}}", value)
        if config["supportURL"]:
            content = content.replace('href="./support.html', 'href="' + html.escape(config["supportURL"], quote=True))
        if config["privacyURL"]:
            content = content.replace('href="./privacy.html', 'href="' + html.escape(config["privacyURL"], quote=True))
        content = content.replace('<div class="actions"></div>', "")
        if "{{" in content or "}}" in content:
            raise ValueError(f"Unresolved template token in {filename}.")
        (destination / filename).write_text(content, encoding="utf-8")
    (destination / ".nojekyll").write_text("", encoding="utf-8")
    metadata = {"mode": mode, "site": site, "configuredLinks": {key: bool(config[key]) for key in KEYS}}
    (destination / "build-info.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    sitemap = destination / "sitemap.xml"
    robots = destination / "robots.txt"
    if mode == "publish" and config["siteURL"]:
        base = config["privacySiteURL" if site == "privacy" else "siteURL"].rstrip("/")
        urls = [config["privacyURL"]] if site == "privacy" else [base + "/", config["supportURL"]]
        sitemap.write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' + ''.join('<url><loc>' + html.escape(url) + '</loc></url>' for url in urls) + '</urlset>\n', encoding="utf-8")
        robots.write_text("User-agent: *\nAllow: /\nSitemap: " + base + "/sitemap.xml\n", encoding="utf-8")
    else:
        sitemap.unlink(missing_ok=True)
        robots.write_text("User-agent: *\nDisallow: /\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=SOURCE / "config.json")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--site", choices=("support", "privacy"), default="support")
    parser.add_argument("--mode", choices=("draft", "publish"), default="draft")
    parser.add_argument("--publish", action="store_true", help="Alias for --mode publish; never uploads content")
    args = parser.parse_args()
    mode = "publish" if args.publish else args.mode
    try:
        config = read_config(args.config)
        errors = publication_errors(config) if mode == "publish" else []
        if errors:
            raise ValueError("\n".join(errors))
        output = args.output or ROOT / ".build/website" / args.site
        build(config, output, mode, args.site)
        print(f"Built {mode} {args.site} website at {output}")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Website build failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
