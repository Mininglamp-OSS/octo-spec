#!/usr/bin/env python3
"""Validate reusable skill metadata and the pre-PR review contract."""

from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
SKILL_FILES = sorted(
    list((ROOT / ".claude/skills").glob("*/SKILL.md"))
    + list((ROOT / "templates/octospec-init/.claude/skills").glob("*/SKILL.md"))
    + list((ROOT / "integrations/octo/skills").glob("*/SKILL.md"))
)
REVIEW_SKILL = (
    ROOT
    / "templates/octospec-init/.claude/skills/octospec-pre-pr-review/SKILL.md"
)


def load_frontmatter(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        raise AssertionError(f"{path}: missing opening YAML fence")
    parts = text.split("---", 2)
    if len(parts) != 3:
        raise AssertionError(f"{path}: missing closing YAML fence")
    data = yaml.safe_load(parts[1])
    if not isinstance(data, dict):
        raise AssertionError(f"{path}: frontmatter must be a mapping")
    return data


class SkillMetadataTest(unittest.TestCase):
    def test_skills_have_valid_unique_metadata(self) -> None:
        self.assertTrue(SKILL_FILES, "no skills discovered")
        seen: dict[str, Path] = {}
        for path in SKILL_FILES:
            with self.subTest(path=path):
                data = load_frontmatter(path)
                name = data.get("name")
                description = data.get("description")
                self.assertIsInstance(name, str)
                self.assertEqual(name, path.parent.name)
                self.assertIsInstance(description, str)
                self.assertTrue(description.strip())
                if "user-invocable" in data:
                    self.assertIsInstance(data["user-invocable"], bool)
                if name in seen:
                    self.assertEqual(
                        path.read_bytes(),
                        seen[name].read_bytes(),
                        f"duplicate skill name drifts from {seen[name]}",
                    )
                else:
                    seen[name] = path

    def test_pre_pr_review_skill_keeps_required_contract(self) -> None:
        data = load_frontmatter(REVIEW_SKILL)
        description = data["description"].lower()
        body = REVIEW_SKILL.read_text(encoding="utf-8")
        for trigger in ("pre-pr review", "review-and-fix", "审查并修复"):
            self.assertIn(trigger, description)
        for requirement in (
            "global security red lines",
            "cross-tenant",
            "ambiguous commit errors",
            "git diff --cached --check",
            "Fixes #…",
            "independent reviewer",
        ):
            self.assertIn(requirement, body)


if __name__ == "__main__":
    unittest.main()
