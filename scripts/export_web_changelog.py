#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_REPOSITORY = "miguelgarglez/momentum"
DEFAULT_DOWNLOAD_BASE_URL = f"https://github.com/{DEFAULT_REPOSITORY}/releases/tag/v"
DEFAULT_COMPARE_BASE_URL = f"https://github.com/{DEFAULT_REPOSITORY}/compare/"
ALLOWED_SECTIONS = {"features", "bug fixes", "performance"}
INTERNAL_SECTION_NAMES = {
    "ci",
    "documentation",
    "tests",
    "build",
    "style",
    "chores",
    "refactors",
    "reverts",
}
MARKDOWN_LINK_RE = re.compile(r"\[([^\]]+)\]\([^)]+\)")
RELEASE_HEADING_RE = re.compile(
    r"^## \[(?P<version>[^\]]+)\]\((?P<compare_url>[^)]+)\) \((?P<published_at>\d{4}-\d{2}-\d{2})\)\s*$"
)
SECTION_RE = re.compile(r"^### (?P<section>.+?)\s*$")
SCOPE_RE = re.compile(r"^\*\*(?P<scope>[^*:]+):?\*\*\s*")
COMMIT_SUFFIX_RE = re.compile(r"\s*\(\[[0-9a-f]{7,}\][^)]+\)\s*$", re.IGNORECASE)
PAREN_HASH_SUFFIX_RE = re.compile(r"\s*\((?:closes\s+)?#?\d+[^\)]*\)\s*$", re.IGNORECASE)
PAREN_COMMIT_HASH_RE = re.compile(r"\s*\([0-9a-f]{7,}\)\s*$", re.IGNORECASE)
INTERNAL_KEYWORDS = (
    "ci",
    "workflow",
    "release",
    "agents",
    "concurrency",
    "documentation",
    "docs",
    "tests",
    "test suite",
    "xcode project file",
    "swiftformat",
    "swiftlint",
    "formatting",
    "main actor isolation",
    "mainactor",
    "actor isolation",
    "diagnostic",
    "diag ",
    "kill switch",
    "signpost",
    "build ",
    "packaging",
)


@dataclass
class Section:
    name: str
    bullets: list[str] = field(default_factory=list)


@dataclass
class Release:
    version: str
    compare_url: str
    published_at: str
    sections: dict[str, Section] = field(default_factory=dict)

    def add_bullet(self, section_name: str, bullet: str) -> None:
        section_key = section_name.lower()
        section = self.sections.setdefault(section_key, Section(name=section_name))
        section.bullets.append(bullet)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a product-facing changelog JSON for Momentum landing."
    )
    parser.add_argument(
        "--input",
        default="CHANGELOG.md",
        help="Path to the source CHANGELOG.md file.",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Where to write the generated JSON payload.",
    )
    parser.add_argument(
        "--overrides",
        default="scripts/release/web_changelog_overrides.json",
        help="Path to JSON overrides for specific releases.",
    )
    parser.add_argument(
        "--repository",
        default=DEFAULT_REPOSITORY,
        help="GitHub repository slug used to build fallback compare/download URLs.",
    )
    return parser.parse_args()


def load_overrides(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def parse_changelog(markdown: str) -> list[Release]:
    releases: list[Release] = []
    current_release: Release | None = None
    current_section: str | None = None
    active_bullet_index: int | None = None

    for raw_line in markdown.splitlines():
        line = raw_line.rstrip()
        heading_match = RELEASE_HEADING_RE.match(line)
        if heading_match:
            current_release = Release(
                version=heading_match.group("version"),
                compare_url=heading_match.group("compare_url"),
                published_at=heading_match.group("published_at"),
            )
            releases.append(current_release)
            current_section = None
            active_bullet_index = None
            continue

        section_match = SECTION_RE.match(line)
        if section_match and current_release is not None:
            section_name = section_match.group("section")
            current_section = section_name
            current_release.sections.setdefault(
                section_name.lower(), Section(name=section_name)
            )
            active_bullet_index = None
            continue

        if current_release is None or current_section is None:
            continue

        stripped = line.strip()
        if stripped.startswith("* "):
            current_release.add_bullet(current_section, stripped[2:].strip())
            active_bullet_index = len(
                current_release.sections[current_section.lower()].bullets
            ) - 1
            continue

        if (
            active_bullet_index is not None
            and stripped
            and not stripped.startswith("## ")
            and not stripped.startswith("### ")
        ):
            current_release.sections[current_section.lower()].bullets[
                active_bullet_index
            ] += f" {stripped}"

    return releases


def strip_markdown(value: str) -> str:
    cleaned = MARKDOWN_LINK_RE.sub(r"\1", value)
    cleaned = COMMIT_SUFFIX_RE.sub("", cleaned)
    cleaned = PAREN_HASH_SUFFIX_RE.sub("", cleaned)
    cleaned = PAREN_COMMIT_HASH_RE.sub("", cleaned)
    cleaned = cleaned.replace("`", "")
    cleaned = cleaned.replace('"', "")
    cleaned = re.sub(r"\s+", " ", cleaned)
    return cleaned.strip(" .")


def extract_scope(value: str) -> tuple[str | None, str]:
    scope_match = SCOPE_RE.match(value)
    if not scope_match:
        return None, value
    return scope_match.group("scope").strip().lower(), value[scope_match.end() :].strip()


def looks_internal(text: str, scope: str | None, section_name: str) -> bool:
    lower = text.lower()
    if section_name.lower() in INTERNAL_SECTION_NAMES:
        return True
    if scope in INTERNAL_SECTION_NAMES:
        return True
    return any(keyword in lower for keyword in INTERNAL_KEYWORDS)


def generic_sentence(text: str, is_fix: bool) -> str:
    normalized = text.rstrip(".")
    replacements = (
        (r"^add\s+", "Added "),
        (r"^allow\s+", "Added support for "),
        (r"^improve\s+", "Improved "),
        (r"^refine\s+", "Refined "),
        (r"^update\s+", "Updated "),
        (r"^support\s+", "Added support for "),
        (r"^keep\s+", "Kept "),
        (r"^show\s+", "Now shows "),
        (r"^fix\s+", "Fixed "),
        (r"^stabilize\s+", "Improved "),
        (r"^restore\s+", "Restored "),
        (r"^reduce\s+", "Reduced "),
    )
    for pattern, replacement in replacements:
        if re.search(pattern, normalized, flags=re.IGNORECASE):
            normalized = re.sub(
                pattern,
                replacement,
                normalized,
                flags=re.IGNORECASE,
            )
            break

    if normalized and normalized[0].islower():
        normalized = normalized[0].upper() + normalized[1:]

    if not normalized.endswith("."):
        normalized += "."

    if is_fix and not normalized.lower().startswith(
        ("fixed ", "improved ", "restored ", "reduced ", "now ")
    ):
        normalized = f"Fixed {normalized[0].lower() + normalized[1:]}"

    return normalized


def theme_summary(text: str, section_name: str, scope: str | None) -> tuple[str | None, str | None]:
    lower = text.lower()
    category = "fixes" if section_name.lower() == "bug fixes" else "highlights"

    if scope in {"raycast", "raycast-ext"}:
        return (
            "raycast",
            "Use Momentum from Raycast with faster project actions and more reliable manual tracking controls.",
        )

    matchers: list[tuple[str, str, str]] = [
        (
            "raycast",
            r"\braycast\b|\blocal api\b",
            "Use Momentum from Raycast with faster project actions and more reliable manual tracking controls.",
        ),
        (
            "localization",
            r"\bbilingual\b|\blocali[sz]ation\b|\bi18n\b",
            "Momentum is now available in English and Spanish across the app.",
        ),
        (
            "project-identity",
            r"project icon|emoji",
            "Customize projects with icons and emoji for faster visual scanning.",
        ),
        (
            "manual-tracking",
            r"manual time|manual tracking|manual session",
            "Manual tracking flows are easier to start, stop, and manage from Momentum.",
        ),
        (
            "feedback",
            r"\bfeedback\b|\bemail-only\b",
            "Sending product feedback is simpler with a direct email flow inside Momentum.",
        ),
        (
            "rules",
            r"expiration preset|assignment rule|rules?",
            "Assignment rules are quicker to create with more practical expiration presets.",
        ),
        (
            "project-domains",
            r"domain entry|domains?",
            "Project domain management is more flexible and easier to maintain.",
        ),
        (
            "file-tracking",
            r"file tracking",
            "Momentum can now track supported files alongside app and browser activity.",
        ),
        (
            "streaks",
            r"longest streak|streak",
            "Momentum now surfaces streak progress more clearly inside project summaries.",
        ),
        (
            "context-usage",
            r"context usage tracking|session management",
            "Momentum now captures richer context usage data across tracked sessions.",
        ),
        (
            "settings",
            r"\bsettings\b",
            "Settings are easier to navigate with a clearer split-view layout and improved section flows.",
        ),
        (
            "project-details",
            r"usage summary|project details?|navigation to project details|monthly",
            "Project detail screens now surface clearer summaries and easier navigation through tracked work.",
        ),
        (
            "project-color",
            r"project color|color picker",
            "Projects can now use custom colors for quicker recognition across the app.",
        ),
        (
            "status-item",
            r"status-item|menu bar|pulse|conflicts|symbol ring",
            "Menu bar controls are more reliable and do a better job surfacing active tracking state.",
        ),
        (
            "action-panel",
            r"action panel|overlay",
            "Project action panels and overlays behave more consistently throughout the app.",
        ),
        (
            "tracking-conflicts",
            r"tracking|conflict|picker icon",
            "Tracking and conflict resolution flows feel more consistent during everyday use.",
        ),
        (
            "onboarding",
            r"welcome|onboarding",
            "The first-launch experience is smoother with a more polished welcome flow.",
        ),
        (
            "performance",
            r"performance|cpu|cache|tolerance",
            "Momentum feels lighter during long sessions thanks to performance and responsiveness improvements.",
        ),
    ]

    for theme, pattern, summary in matchers:
        if re.search(pattern, lower):
            if category == "fixes" and theme in {"raycast", "status-item", "action-panel", "tracking-conflicts"}:
                return theme, summary
            if category == "highlights" and theme not in {"action-panel", "tracking-conflicts"}:
                return theme, summary
            if category == "fixes" and theme == "performance":
                return theme, summary
            if category == "highlights" and theme == "performance":
                return theme, summary

    if scope in {
        "models",
        "onboarding",
        "projects",
        "raycast",
        "raycast-ext",
        "status-item",
        "tracking",
        "ui",
    }:
        return f"{category}:{scope}", generic_sentence(text, category == "fixes")

    return None, None


def dedupe_preserve_order(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        normalized = item.strip()
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        result.append(normalized)
    return result


def curate_release(release: Release, repository: str) -> dict[str, Any]:
    highlights: list[str] = []
    fixes: list[str] = []
    theme_cache: set[str] = set()

    for section_name, section in release.sections.items():
        if section_name not in ALLOWED_SECTIONS:
            continue

        for bullet in section.bullets:
            scope, without_scope = extract_scope(bullet)
            cleaned = strip_markdown(without_scope)
            if not cleaned or looks_internal(cleaned, scope, section.name):
                continue

            theme, summary = theme_summary(cleaned, section.name, scope)
            is_fix = section.name.lower() == "bug fixes"

            if theme and summary:
                if theme in theme_cache:
                    continue
                theme_cache.add(theme)
                if is_fix:
                    fixes.append(summary)
                else:
                    highlights.append(summary)
                continue

            sentence = generic_sentence(cleaned, is_fix=is_fix)
            if is_fix:
                fixes.append(sentence)
            else:
                highlights.append(sentence)

    compare_url = (
        release.compare_url
        if release.compare_url
        else f"https://github.com/{repository}/compare/v{release.version}"
    )
    download_url = f"https://github.com/{repository}/releases/tag/v{release.version}"

    return {
        "version": release.version,
        "publishedAt": release.published_at,
        "compareUrl": compare_url,
        "downloadUrl": download_url,
        "highlights": dedupe_preserve_order(highlights)[:4],
        "fixes": dedupe_preserve_order(fixes)[:3],
        "hidden": False,
    }


def apply_override(payload: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged = dict(payload)
    for key in ("version", "publishedAt", "compareUrl", "downloadUrl", "hidden"):
        if key in override:
            merged[key] = override[key]
    if "highlights" in override:
        merged["highlights"] = override["highlights"]
    if "fixes" in override:
        merged["fixes"] = override["fixes"]
    if "appendHighlights" in override:
        merged["highlights"] = dedupe_preserve_order(
            merged.get("highlights", []) + override["appendHighlights"]
        )[:4]
    if "appendFixes" in override:
        merged["fixes"] = dedupe_preserve_order(
            merged.get("fixes", []) + override["appendFixes"]
        )[:3]
    merged["highlights"] = dedupe_preserve_order(merged.get("highlights", []))[:4]
    merged["fixes"] = dedupe_preserve_order(merged.get("fixes", []))[:3]
    return merged


def generate_payload(
    changelog_path: Path, overrides_path: Path, repository: str
) -> dict[str, Any]:
    changelog_text = changelog_path.read_text()
    overrides = load_overrides(overrides_path)
    releases = parse_changelog(changelog_text)
    payload_releases: list[dict[str, Any]] = []

    for release in releases:
        curated = curate_release(release, repository=repository)
        override = overrides.get(release.version)
        if override:
            curated = apply_override(curated, override)
        if not curated["highlights"] and not curated["fixes"]:
            curated["hidden"] = True
        payload_releases.append(curated)

    return {
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "repository": repository,
        "releases": payload_releases,
    }


def main() -> None:
    args = parse_args()
    payload = generate_payload(
        changelog_path=Path(args.input),
        overrides_path=Path(args.overrides),
        repository=args.repository,
    )
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2) + "\n")


if __name__ == "__main__":
    main()
