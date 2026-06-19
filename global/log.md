# Change log

Change history for the global ("constitution") rules, following the
[OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
change-log convention (§7). Newest entries first. Each entry records
Creation / Update / Deprecation of a knowledge unit.

## 2026-06-19

- **Creation** — Added `templates/octospec-init/AGENT-BLOCK.md` (one tool-neutral
  agent-instruction source) and a YAML/marker-safe sync: `scripts/octospec_sync_block.py`
  (whole-line + fence-aware marker detection, refuses malformed/duplicate markers,
  atomic writes, CRLF-preserving) driven by the rewritten `scripts/octospec-sync.sh`,
  with a regression suite `scripts/test_octospec_sync_block.py` wired into CI. Syncs the
  block idempotently into every agent-instruction file present (CLAUDE.md, AGENTS.md,
  GEMINI.md, QWEN.md); content outside the markers is preserved. This makes the
  Layer-1 auto-load behavior described in docs/INTEGRATION.md real for all agents,
  not just Claude Code.

- **Update** — Adopted OKF v0.1 compatible frontmatter across all global rules.
  Added the OKF fields `type`, `title`, `description`, `tags`, `timestamp` to
  `commit`, `pr`, `review`, `security`, `comprehension-gate`. The existing
  octospec orchestration fields (`id`, `tier`, `priority`, `load_bearing`,
  `inject_when`, `source`, `supersedes`) are retained as OKF extension fields.
- **Creation** — Added `global/index.md` (human-readable rule catalog) and this
  `global/log.md` change log.
- **Creation** — Added `scripts/octospec-lint.sh` (OKF conformance check:
  every knowledge file must have a properly terminated frontmatter block with a
  non-empty `type`; opt-in scope = global rules + `*/rules/`).
- **Update** — Rewrote the linter to be YAML-aware (`scripts/octospec-lint.py`,
  wrapped by the `.sh`): parses frontmatter as YAML, rejects malformed YAML and
  quoted-empty `type: ""`, normalizes BOM/CRLF, fails closed on a bad/empty scan
  root, and extends scope to `tasks/**` briefs and `journal/**` entries. Bumped
  the starter template's `inherits` pin to `octo-spec@1.1.0`.
- **Update** — Made the slash commands/skill/templates OKF-aware so generated
  artifacts stay conformant: `_brief.template.md` now carries `type: Task`
  frontmatter; `/octospec-plan` and `/octospec-finish` (+ the workflow skill)
  instruct writing OKF frontmatter for task briefs and journals and updating
  `log.md`.

## 2026-06-18

- **Creation** — Initial global constitution: `commit`, `pr`, `review`,
  `security`, `comprehension-gate`.
