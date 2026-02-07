#!/usr/bin/env python3
import re
import sys
from pathlib import Path


RAYCAST_SRC = Path("RaycastExtension/momentum/src")
STRING_LITERAL_RE = re.compile(r'"((?:\\.|[^"\\])*)"')

# Simple guardrails to keep runtime/user-facing copy in English.
BANNED_CHARS_RE = re.compile(r"[áéíóúñÁÉÍÓÚ¿¡]")
BANNED_WORDS = [
    "emparej",
    "proyecto",
    "proyectos",
    "conflicto",
    "conflictos",
    "ajustes",
    "pudimos",
    "invalido",
    "inválido",
]

# Keep acceptable tokens that may appear in tests or identifiers.
ALLOW_SUBSTRINGS = [
    "list-projects",
    "project-id",
]


def main() -> int:
    if not RAYCAST_SRC.exists():
        print(f"ERROR: missing Raycast source at {RAYCAST_SRC}")
        return 1

    violations: list[str] = []
    for path in RAYCAST_SRC.rglob("*"):
        if path.suffix not in {".ts", ".tsx"}:
            continue
        content = path.read_text()
        for raw in STRING_LITERAL_RE.findall(content):
            text = raw.replace('\\"', '"').replace("\\n", "\n")
            if any(token in text for token in ALLOW_SUBSTRINGS):
                continue
            if BANNED_CHARS_RE.search(text):
                violations.append(f"{path}: contains Spanish accented chars -> {text}")
                continue
            lower = text.lower()
            if any(word in lower for word in BANNED_WORDS):
                violations.append(f"{path}: contains Spanish marker -> {text}")

    if violations:
        print("Raycast English-copy check failed:")
        for item in violations[:120]:
            print(f"- {item}")
        return 1

    print("Raycast English-copy check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
