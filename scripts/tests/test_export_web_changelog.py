from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from scripts.export_web_changelog import generate_payload


FIXTURES_DIR = Path(__file__).parent / "fixtures"


class ExportWebChangelogTests(unittest.TestCase):
    def test_visible_release_keeps_product_facing_content(self) -> None:
        payload = self._generate_payload()
        release = self._find_release(payload, "1.0.2")

        self.assertFalse(release["hidden"])
        self.assertIn(
            "Customize projects with icons and emoji for faster visual scanning.",
            release["highlights"],
        )
        self.assertIn(
            "Use Momentum from Raycast with faster project actions and more reliable manual tracking controls.",
            release["highlights"],
        )
        self.assertIn(
            "Menu bar controls are more reliable and do a better job surfacing active tracking state.",
            release["fixes"],
        )

    def test_internal_only_release_is_hidden(self) -> None:
        payload = self._generate_payload()
        release = self._find_release(payload, "1.0.1")

        self.assertTrue(release["hidden"])
        self.assertEqual(release["highlights"], [])
        self.assertEqual(release["fixes"], [])

    def test_override_replaces_generated_copy(self) -> None:
        payload = self._generate_payload()
        release = self._find_release(payload, "1.0.0")

        self.assertEqual(
            release["highlights"],
            ["A curated override replaced the automatic highlights."],
        )
        self.assertEqual(
            release["fixes"],
            ["A curated override replaced the automatic fixes."],
        )

    def _generate_payload(self) -> dict:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output_path = Path(temporary_directory) / "changelog.generated.json"
            payload = generate_payload(
                changelog_path=FIXTURES_DIR / "web_changelog_fixture.md",
                overrides_path=FIXTURES_DIR / "web_changelog_overrides_fixture.json",
                repository="miguelgarglez/momentum",
            )
            output_path.write_text(json.dumps(payload))
            return json.loads(output_path.read_text())

    @staticmethod
    def _find_release(payload: dict, version: str) -> dict:
        for release in payload["releases"]:
            if release["version"] == version:
                return release
        raise AssertionError(f"Release {version} not found in payload.")


if __name__ == "__main__":
    unittest.main()
