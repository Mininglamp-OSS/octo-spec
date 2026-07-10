# Change log

Change history for the global ("constitution") rules, following the
[OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
change-log convention (§7). Newest entries first. Each entry records
Creation / Update / Deprecation of a knowledge unit.

## 2026-07-10 (upgrade refresh of managed root surfaces)

- **Fix** — **Sync refreshes octospec-managed ROOT surfaces from source on
  upgrade.** Root materialization was copy-if-absent (`install_missing`), so
  stable-path files — the repo-root `octospec-workflow` skill, the `/octospec`
  command, and the PR template — were frozen at their first-installed version. On
  the documented upgrade (bump pin + re-run sync) an already-onboarded repo kept a
  v1 root skill that predates the approval gate, re-opening the same class of
  pre-gate bypass the command-prune closed (the router delegates all phase logic
  to that skill). Fixed: root materialization is now **install-or-refresh scoped
  to the octospec namespace** — octospec-owned files (`commands/octospec*.md`,
  `skills/octospec-*/**`, the PR template) are overwritten from the freshly
  re-vendored source every run; a user's own non-octospec file under `.claude/` is
  still install-if-missing. Added regression assertions that a seeded stale root
  skill / command / PR template refresh to the current source on upgrade while a
  user's `deploy.md` survives.

## 2026-07-10 (skill-first, Claude-only)

- **Deprecation (breaking onboarding change)** — **Removed the agent-instruction
  injection machine.** octospec no longer writes an
  `<!-- octospec:begin -->…<!-- octospec:end -->` block into
  `CLAUDE.md`/`AGENTS.md`/`GEMINI.md`/`QWEN.md`. The full 6-phase workflow was
  being duplicated across the `octospec-workflow` skill, the `/octospec` command,
  AND that injected block — so the "single source of truth" claim was false and
  every workflow change had to be edited in ≥2 places (reviewers repeatedly caught
  the drift). The block's only purpose was reaching non-Claude agents, but Codex /
  Gemini / Cursor / Windsurf all have their own native skills dirs and Codex has
  no documented auto-follow of a pointer inside `AGENTS.md` — so a "thick"
  injected block was the wrong shim.
  - Deleted `AGENT-BLOCK.md`, `octospec_sync_block.py` (+ its regression test),
    the CI sync-block step, and sync's step-2 injection loop + AGENTS/GEMINI/QWEN
    bootstrap. `octospec-sync.sh` now only vendors `_global/`, refreshes the
    managed template surfaces, and materializes the repo-root `.claude/`/`.github/`
    scaffolding + prunes obsolete commands. It touches no agent-instruction files.
  - The **`octospec-workflow` skill is the single workflow source of truth**;
    `/octospec` is a Claude-only thin entry into it. octospec is discovered via
    Claude Code skill progressive-disclosure — there is no always-on injected
    block.
  - **Phase 1 is Claude-only by decision.** Distributing the skill into other
    agents' native skill dirs (`.codex/skills`, `.gemini/skills`, …) is deferred
    to a future phase; until then non-Claude paths are governed by the PR gate.
  - **Migration:** already-onboarded repos keep an inert `octospec:begin/end`
    block in their `CLAUDE.md`/`AGENTS.md`. Sync no longer manages it — it's
    harmless stale content you may delete by hand. Re-run sync (bump nothing) to
    pick up the new behavior; the skill + command drive Claude Code now. Sync does
    not auto-strip the block (deleting from a user's CLAUDE.md is riskier than
    leaving it).

## 2026-07-10 (PR #21 review fixes)

- **Deprecation** — **Removed `learnings/pending/`.** It was a permanently-empty
  dead-letter: the only writer (`octospec-update-spec.sh --kind=rule`) put a rule
  *draft* there, and Finish required the draft to be promoted to `rules/` and
  deleted in the same PR — so nothing ever rested there. The rule draft now lands
  beside the task's spec at `.octospec/tasks/<slug>/<slug>-rule-draft.md` (rides
  the task branch, visible in review, deleted once the rule lands). A learning
  that isn't rule-ready stays in the task journal's `## Learning` — there is no
  separate queue. Deleted the `learnings/` template dir; updated the helper +
  selftest (drafts under `tasks/<slug>/`), the workflow skill, octo-code adapter,
  docs, and both READMEs.

- **Fix** — **Sync refreshes the managed template surfaces from `GLOBAL_SRC` (fixes
  the upgrade gate-bypass at its root).** The prune added earlier reconciled the
  repo root against the repo's *vendored* `.octospec/.claude/`, which sync never
  refreshed — so on the documented upgrade (bump pin + re-run sync) a stale 1.x
  vendored copy meant the v1 commands were never pruned and the new router was
  never installed, while sync reported success. Sync now refreshes the
  octospec-managed surfaces (`.octospec/.claude/`, `.octospec/.github/`, and the
  fill-in `_spec`/`_discovery`/`_journal` templates + `AGENT-BLOCK.md`) from the
  `GLOBAL_SRC` template on every run — the same freshness model as `_global/` —
  so install + prune operate on the pinned version, not a stale copy. User content
  (`manifest.yaml`, real `tasks/`/`journal/`/`rules/`) is untouched; `scripts/` is
  deliberately not refreshed in place (it is the running script). The upgrade-prune
  regression test was rewritten to model a genuinely **stale 1.x source** (the case
  the prior test masked by pre-copying the fresh template).
- **Fix** — **Sync prunes obsolete octospec-managed commands.**
  `octospec-sync.sh` was install-if-missing only, so an already-onboarded repo
  kept the deleted v1 `octospec-{plan,go,check,finish}.md` after re-sync — a
  fail-open bypass of the approval gate (the old `octospec-go` writes code with no
  approval check). Added a `prune_obsolete_commands` step that removes root
  `.claude/commands/octospec*.md` files absent from the template source (scoped to
  the octospec namespace so user files are never touched), plus a regression test
  that seeds a stale `octospec-go.md` and asserts it is pruned while `octospec.md`
  and a user's own command survive.
- **Fix** — **Approval no longer writes invalid YAML.** The spec template shipped
  `approvals: []` (flow empty list); appending a block-sequence approval under it
  is invalid YAML and would break OKF lint + the machine-checkable gate on first
  approval. Changed to a bare `approvals:` block key (same fix applied to
  `rules/_index.yaml`'s `rules:`).
- **Fix** — **Finish helper reconciled with the flat slim journal.** Removed the
  `--kind=task` per-actor `journal/by-actor/<actor>/<slug>.md` lane from
  `octospec-update-spec.sh` (the Finish phase writes the flat
  `journal/<slug>.md` directly); `--kind=task` now refuses with a pointer to the
  replacement. Updated the self-test accordingly.
- **Fix** (non-blocking) — Scoped the octo-code-doctor `verify.tools` awk parser
  to the `verify:` block (an unrelated earlier `tools:` key no longer misleads
  it); marked the adapter's `--allowedTools` derivation as pseudocode and added
  tool-token validation guidance (reject shell wrappers / grammar chars); dropped
  the stale "injection budget" comment; propagated `impl-only → impl/test-only`
  and `self-fixing → independent verify` in both READMEs and docs; added red-first
  TDD + independent-verify + autopilot to `AGENT-BLOCK.md`; noted autopilot's
  red-first check is conditional on ≥1 testable acceptance item.

## 2026-07-10

- **Release** — Cut **`2.1.0`**, bundling this round plus the two prior
  dogfood iterations that were staged as "unreleased 2.0.0" (autopilot,
  independent verify, spec-on-branch, log.md removal, slim journal, and TDD in
  Implement). Bumped `VERSION`, the template `manifest.yaml` pin, the sync-test
  happy-path fixtures, and the `BOOTSTRAP.md` / README `v2.1.0` tag + raw URLs.
- **Update** — Renamed the task artifact **`brief.md` → `spec.md`** (and
  `_brief.template.md` → `_spec.template.md`) — it carries goal / load-bearing /
  scope / acceptance / approvals / iteration-log, i.e. a spec, not a summary.
  Updated every reference across skill, router command, templates, octo-code
  adapter, global rules, docs, and PR templates. Backward-compat: readers fall
  back to a legacy `brief.md` for one release cycle when `spec.md` is absent;
  writes are always `spec.md`.
- **Update** — Added an explicit **slice classification** (`class:` in the spec):
  `behavior-change` (standard Red→Green), `pure-relocation` (`N/A(test)`;
  criterion = byte-equivalent diff + suite green), `characterization`
  (`N/A(test-first)`; criterion = discriminating assertions). Named the
  **characterization-first** two-stage pattern (net PR then extract PR) so it is
  not reinvented per slice.
- **Update** — Added a mandatory **Red self-check** to Implement (assertion-not-
  crash with `.first`+guard; test actually reaches the code under test;
  discriminating identity/no-op fixtures; verify real signatures before
  referencing) — moving these failure modes forward from Verify to Red.
- **Update** — **Tiered Verify by slice class** (full independent agent for
  behavior-change; lightweight byte-diff for pure-relocation; focused review for
  characterization) and split the **targeted filter** (Red→Green inner loop) from
  the **full gate** (Finish/Verify) to save a redundant full-suite run.

## 2026-07-08

- **Update** — TDD in Implement (from continued dogfood feedback), same
  unreleased `2.0.0`: Implement now follows **Red → Green → Refactor** for
  behavior changes. The approved Acceptance is written as failing tests and
  committed (`red: <slug>`) **before** production code, giving the independent
  Verify a git-provable anchor (tests failed pre-implementation, encode the
  Acceptance, weren't weakened to fake green). Refactor is folded into Implement
  (no new phase). Changes that genuinely can't carry a failing test use an
  explicit `N/A(test): <reason>` in the spec — no silent skip. Updated the
  workflow skill, router command, spec template (Acceptance = testable),
  `comprehension-gate.md` (red-first section), octo-code adapter (Red-Green
  parity + `red:`-before-code checklist item), and docs. Iterate's impl-only path
  becomes **impl/test-only** (a test fix is its own explained commit).

- **Update** — Loop v2 dogfood iteration (from 7-slice field feedback), same
  unreleased `2.0.0`:
  - **Autopilot** — added `/octospec autopilot <slug>`: after approval, runs
    Implement → Verify → (impl-only Iterate, ≤2 retries) → Finish unattended,
    stopping at "PR opened". Returns to the human on a spec-changing failure
    (revision bump → re-approval) or exhausted retries; never auto-merges.
  - **Independent verify** — Verify is now an **independent, fresh-context pass**
    (a `code-reviewer`/`verifier` subagent locally, a separate `claude -p` review
    for octo-code), not the implementing context self-certifying. Added an
    "Independent verify (no self-review)" section to `comprehension-gate.md` and
    bumped its timestamp.
  - **Spec rides the branch** — Discover now creates the task branch and commits
    discovery/spec/approval onto it, so the PR opened at Finish already contains
    the spec (eliminates the manual `cp` into the worktree PR).
  - **Removed the per-task `log.md`** — a structural rebase-conflict magnet whose
    content duplicated `git log` (timeline) and the journal (detail). Dropped its
    write from Finish and the `rules/log.md` reference from
    `octospec-update-spec.sh`.
  - **Slim journal** — journal reduced to a one-line result + `## Learning` (its
    only unique value, the raw material for rules). Added
    `journal/_journal.template.md` to bake the shape into the scaffold.

## 2026-07-07

- **Update** — Loop v2: the workflow went from a 4-phase loop
  (Plan→Implement→Verify→Finish) to a **6-phase loop**
  (Discover→Plan→Implement→Verify→Iterate→Finish) with a **spec approval gate**.
  Added an "Approval gate" section to `comprehension-gate.md`: each spec
  `revision` must carry a matching human approval before Implement runs; a
  spec-changing Iterate bumps the revision and invalidates the prior approval
  (impl-only rework does not). Bumped `comprehension-gate` timestamp.
- **Update** — Replaced the four `octospec-{plan,go,check,finish}` slash commands
  with a single router command `/octospec <phase> <slug>`
  (`discover|plan|implement|verify|iterate|finish` + `approve|next|status`); the
  `octospec-workflow` skill is now the single source of truth for phase steps.
  Rewrote the starter templates (`_spec.template.md` gains `revision`/`approvals`
  /Iteration Log; new `_discovery.template.md`) and dropped the unused injection
  budget / fingerprint / `context.yaml` machinery.
- **Update** — Made the verify step **language-agnostic**: repos declare their gate
  in `manifest.yaml` `verify.{gate,tools}` (Go/TS/Python/…); the octo-code adapter
  derives `--allowedTools` and the completion gate from it instead of hardcoding
  Python, and adds an **approval pause** between Plan and Implement. Bumped
  `VERSION`/pins to `2.0.0`.

## 2026-06-22

- **Creation** — Added `BOOTSTRAP.md` one-liner onboarding entry (remote-doc
  driven: clone the pinned octo-spec to a temp dir, then hand off to the
  `octospec-init` skill against the current repo) and surfaced it at the top of
  both `README.md` and `README.zh-CN.md` Quick start. Bumped `VERSION` to
  `1.2.0`; the bootstrap clone tag and README raw URLs are pinned to `v1.2.0`.

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
- **Creation** — Added a single canonical agent-instruction source and a
  YAML/marker-safe sync: `scripts/octospec_sync_block.py`
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
  root, and extends scope to `tasks/**` specs and `journal/**` entries. Bumped
  the starter template's `inherits` pin to `octo-spec@1.1.0`.
- **Update** — Made the slash commands/skill/templates OKF-aware so generated
  artifacts stay conformant: `_spec.template.md` now carries `type: Task`
  frontmatter; `/octospec-plan` and `/octospec-finish` (+ the workflow skill)
  instruct writing OKF frontmatter for task specs and journals and updating
  `log.md`.

## 2026-06-18

- **Creation** — Initial global constitution: `commit`, `pr`, `review`,
  `security`, `comprehension-gate`.
