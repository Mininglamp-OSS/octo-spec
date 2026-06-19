# Change log

Change history for the global ("constitution") rules, following the
[OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
change-log convention (§7). Newest entries first. Each entry records
Creation / Update / Deprecation of a knowledge unit.

## 2026-06-19

- **Update** — Adopted OKF v0.1 compatible frontmatter across all global rules.
  Added the OKF fields `type`, `title`, `description`, `tags`, `timestamp` to
  `commit`, `pr`, `review`, `security`, `comprehension-gate`. The existing
  octospec orchestration fields (`id`, `tier`, `priority`, `load_bearing`,
  `inject_when`, `source`, `supersedes`) are retained as OKF extension fields.
- **Creation** — Added `global/index.md` (human-readable rule catalog) and this
  `global/log.md` change log.
- **Creation** — Added `scripts/octospec-lint.sh` (OKF conformance check:
  every knowledge file must have frontmatter with a non-empty `type`).
- **Update** — Made the slash commands/skill/templates OKF-aware so generated
  artifacts stay conformant: `_brief.template.md` now carries `type: Task`
  frontmatter; `/octospec-plan` and `/octospec-finish` (+ the workflow skill)
  instruct writing OKF frontmatter for task briefs and journals and updating
  `log.md`.

## 2026-06-18

- **Creation** — Initial global constitution: `commit`, `pr`, `review`,
  `security`, `comprehension-gate`.
