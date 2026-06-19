# Change log

Change history for the global ("constitution") rules, following the
[OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
change-log convention (§7). Newest entries first. Each entry records
Creation / Update / Deprecation of a knowledge unit.

## 2026-06-19

- **Fix** — Corrected `scripts/octospec_sync_block.py` fence detection to follow
  CommonMark code-fence rules (record the opening fence's char AND length; a
  fence is only closed by a same-char run of length >= the opener with an empty
  info string). The previous prefix-only check let an inner ``` close a ````
  (4-backtick) fence, so markers shown inside a documentation example were
  mistaken for the real managed region and the user content between them was
  silently overwritten (CommonMark CM-119/120). Added regression coverage for
  nested 4-backtick / 4-tilde fences, info strings, and indented fences. Also
  hardened CLI arg parsing with a `--` end-of-options separator.
- **Fix** — `templates/octospec-init/` now ships `scripts/` (byte-identical
  copies of `octospec-sync.sh` + `octospec_sync_block.py`) so the README
  quickstart (`cp template -> .octospec`, then `./.octospec/scripts/octospec-sync.sh`)
  succeeds instead of failing with "no such file or directory". CI asserts the
  template copies never drift from the canonical scripts, and runs the quickstart
  end-to-end.

## 2026-06-19
  agent-instruction source) and a YAML/marker-safe sync: `scripts/octospec_sync_block.py`
  (whole-line + fence-aware marker detection, refuses malformed/duplicate markers,
  atomic writes, CRLF-preserving) driven by the rewritten `scripts/octospec-sync.sh`,
  with a regression suite `scripts/test_octospec_sync_block.py` wired into CI. Syncs the
  block idempotently into every agent-instruction file present (CLAUDE.md, AGENTS.md,
  GEMINI.md, QWEN.md); content outside the markers is preserved. This makes the
  Layer-1 auto-load behavior (the integration design tracked in PR #2) real for
  all agents,
  not just Claude Code.
- **Fix** — octospec-sync.sh now accumulates per-file failures and exits
  non-zero (a refused/malformed agent file no longer reports success);
  added `~~~` fence support and shell-wrapper + `~~~` regression tests to CI;
  removed a committed `.pyc` and added `__pycache__/`/`*.pyc` to .gitignore.

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
