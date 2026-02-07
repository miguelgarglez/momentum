#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


CATALOG_PATH = Path("Momentum/Localizable.xcstrings")
SCAN_DIRS = [
    Path("Momentum/Views"),
]
SCAN_FILES = [
    Path("Momentum/ContentView.swift"),
    Path("Momentum/MomentumApp.swift"),
    Path("Momentum/Services/StatusItemController.swift"),
    Path("Momentum/Services/TrackerSettings.swift"),
    Path("Momentum/Utilities/SymbolCatalog.swift"),
    Path("Momentum/Models/Project.swift"),
]

# Keep this in sync with supported placeholders in codebase.
PLACEHOLDER_RE = re.compile(r"\\\([^)]*\)|%lld|%ld|%@|%d|%f|%\.\df")
STRING_LITERAL_RE = re.compile(r'"((?:\\.|[^"\\])*)"')

IGNORE_KEYS = {
    "MMM",
    "MomentumStore",
    "StatusItemOpenProject",
    "StatusItemProjectID",
    "StatusItemShowApp",
    "StatusItemShowSettings",
    "StatusItemStartManualTracking",
    "Failed to create store directory: \\(error.localizedDescription)",
    "Failed to reset store directory: \\(error.localizedDescription)",
}


def parse_placeholders(value: str) -> list[str]:
    return PLACEHOLDER_RE.findall(value)


def is_ui_candidate(text: str) -> bool:
    if not text or not any(ch.isalpha() for ch in text):
        return False
    if text in IGNORE_KEYS:
        return False
    if text.startswith(("http://", "https://", "/")):
        return False
    if text.startswith(("com.", "tracker.", "app.")) or text.endswith(".sqlite"):
        return False
    if re.fullmatch(r"#[0-9A-Fa-f]{6}", text):
        return False
    if re.fullmatch(r"[A-Z0-9_]+", text):
        return False
    if re.fullmatch(r"[a-z0-9_.\-/]+", text) and not text.isalpha():
        return False
    if text in {"GET", "POST", "PUT", "DELETE", "HEAD", "PATCH"}:
        return False
    if text.startswith("pending-conflict-"):
        return False
    if text in {"RaycastShowConflicts", "RaycastStartManualTracking", "showSettingsWindow:"}:
        return False
    # Prioritize visible/UI text patterns.
    has_space = any(ch.isspace() for ch in text)
    has_non_ascii = any(ord(ch) > 127 for ch in text)
    starts_upper = text[0].isupper()
    return has_space or has_non_ascii or starts_upper


def extract_swift_ui_strings() -> set[str]:
    strings: set[str] = set()
    source_files = []
    for directory in SCAN_DIRS:
        if directory.exists():
            source_files.extend(directory.rglob("*.swift"))
    for file_path in SCAN_FILES:
        if file_path.exists():
            source_files.append(file_path)

    for swift_path in source_files:
        content = swift_path.read_text()
        for raw in STRING_LITERAL_RE.findall(content):
            text = raw.replace('\\"', '"').replace("\\n", "\n")
            if is_ui_candidate(text):
                strings.add(text)
    return strings


def main() -> int:
    if not CATALOG_PATH.exists():
        print(f"ERROR: missing catalog at {CATALOG_PATH}")
        return 1

    catalog = json.loads(CATALOG_PATH.read_text())
    strings = catalog.get("strings", {})
    if not isinstance(strings, dict):
        print("ERROR: invalid xcstrings format: 'strings' is not an object")
        return 1

    errors: list[str] = []

    for key, payload in strings.items():
        localizations = payload.get("localizations", {})
        en = localizations.get("en", {}).get("stringUnit", {}).get("value")
        es = localizations.get("es", {}).get("stringUnit", {}).get("value")

        if not en or not isinstance(en, str):
            errors.append(f"missing EN value for key: {key}")
            continue
        if not es or not isinstance(es, str):
            errors.append(f"missing ES value for key: {key}")
            continue

        key_ph = parse_placeholders(key)
        en_ph = parse_placeholders(en)
        es_ph = parse_placeholders(es)
        if key_ph != en_ph:
            errors.append(f"EN placeholders mismatch for key: {key} | key={key_ph} en={en_ph}")
        if key_ph != es_ph:
            errors.append(f"ES placeholders mismatch for key: {key} | key={key_ph} es={es_ph}")

    source_strings = extract_swift_ui_strings()
    missing_in_catalog = sorted(s for s in source_strings if s not in strings and s not in IGNORE_KEYS)
    if missing_in_catalog:
        errors.append(f"{len(missing_in_catalog)} UI strings missing from catalog")
        for value in missing_in_catalog[:80]:
            errors.append(f"missing key: {value}")

    if errors:
        print("Localization check failed:")
        for err in errors:
            print(f"- {err}")
        return 1

    print(
        "Localization check passed:",
        f"{len(strings)} catalog keys,",
        f"{len(source_strings)} extracted UI strings",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
