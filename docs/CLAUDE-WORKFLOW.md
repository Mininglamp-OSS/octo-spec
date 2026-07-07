# Claude Code workflow

octo-spec is Claude Code first. The 6-phase loop is driven by one slash command
backed by a thin router into the workflow skill. No central server, no extra
service — everything reads and writes files in the repo.

## Zero install for team members

The `/octospec` command **and** the auto-trigger skill are **committed to the
repo** under `.claude/`. A team member does **not** install anything: `git clone`
/ `git pull` brings them with the repo.

- **Auto-trigger (skill)** — `.claude/skills/octospec-workflow/`. When a developer
  asks Claude Code to implement/fix/refactor something, the skill's description
  matches and Claude **runs the 6-phase flow automatically** — no command to
  remember. Trivial edits (typo/docs/lint/config) are skipped by design.
- **Manual control (command)** — `.claude/commands/octospec.md`. Drive a single
  phase on demand with `/octospec <phase> <slug>`:
  `discover`, `plan`, `implement`, `verify`, `iterate`, `finish` — plus `approve`
  (record human sign-off of the brief), `next` (run the inferred next phase), and
  `status` (read-only progress report).

Both version with the repo, so everyone is always on the same workflow — nothing
to install, nothing to keep in sync by hand.

### Three levels of how the flow runs

| Level | Mechanism | Trigger | Strength |
|---|---|---|---|
| Auto | skill | model decides from your request | seamless, probabilistic |
| Manual | `/octospec <phase>` command | you type it | precise, opt-in |
| Enforce | approval gate + PR template + (future) CI gate | implement / merge time | deterministic |

The skill makes the flow *easy and automatic*; the approval gate and PR/CI gate
make it *binding*.

## Setup (once per repo, by a maintainer)

1. Initialize the skeleton: copy `templates/octospec-init` to `.octospec/`
   (this carries `.claude/` and a `.github/PULL_REQUEST_TEMPLATE.md` inside
   `.octospec/`; step 3's sync materializes them to the repo root for you).
2. Pin the global version in `.octospec/manifest.yaml`, and set the `verify:`
   block to your repo's gate commands (language-agnostic — Go/TS/Python/…).
3. Run `octospec-sync` (with `GLOBAL_SRC` pointing at a checkout of octo-spec
   at the pinned version). This pulls global rules into git-ignored
   `.octospec/_global/`, writes the octospec block into your agent files
   (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / `QWEN.md`) between
   `<!-- octospec:begin -->` / `<!-- octospec:end -->` markers — the sync owns
   that region; everything outside it is yours. `CLAUDE.md` and `AGENTS.md` are
   the two default entry points — whichever is missing is created so both Claude
   Code and Codex get the block; `GEMINI.md` / `QWEN.md` are synced only when they
   already exist. Finally it **materializes the repo-root scaffolding** that
   tools only discover at the root: it copies `.octospec/.claude/` to `.claude/`
   (so Claude Code finds the `/octospec` command and skill) and
   `.octospec/.github/PULL_REQUEST_TEMPLATE.md` to `.github/` (so GitHub applies
   the PR template). This is install-if-missing — any file you have already
   customized at the root is left untouched, and re-running is idempotent.
4. Commit (including the materialized root `.claude/` and `.github/`). From here,
   every team member just pulls.

## The loop

| Command | Does | Writes |
|---|---|---|
| `/octospec discover <task>` | Read-only exploration of the code the task touches. | `tasks/<slug>/discovery.md` |
| `/octospec plan <slug>` | Derive a brief from discovery; stop for human approval. | `tasks/<slug>/brief.md` (revision 1) |
| `/octospec approve <slug>` | Record human sign-off of the brief's current revision. | approval entry in `brief.md` |
| `/octospec implement <slug>` | Gate-check approval, inject matching rules, write code (no commit). | (code) |
| `/octospec verify <slug>` | Check the diff against injected rules + Acceptance; run `verify.gate`; self-fix. | (validation only) |
| `/octospec iterate <slug>` | Disciplined rework: impl-only → re-Verify; spec-changing → bump revision + re-approve. | `brief.md` Iteration Log (spec-changing only) |
| `/octospec finish <slug>` | Final gate, journal entry, land learnings in-PR, open a PR (Linked Spec + COMPREHENSION). | `journal/<slug>.md` |

`/octospec next <slug>` runs the inferred next phase; `/octospec status <slug>`
reports progress read-only.

## Approval gate

The brief must be human-approved before Implement runs. `/octospec approve` writes
an approval bound to the brief's current `revision`. `/octospec implement` refuses
unless an approval matches that revision — and an agent may never approve its own
brief. A spec-changing iteration bumps the revision, invalidating the old approval
so the new revision must be re-approved. This makes sign-off a machine-checkable
front gate, not a post-hoc formality.

## Rule injection

A rule is injected when its `inject_when.paths` glob matches a touched file **or**
its `inject_when.touches` tag is declared in the brief's load-bearing list (which
is why the Discover phase — grounding that list in real code — matters). Read the
full text of every matching rule and follow it, load-bearing rules first.

## Promotion (learnings → rules)

`/octospec finish` lands a reusable learning **in the same PR** (edit the relevant
`rules/<rule>.md`, or add a new rule + `_index.yaml` entry) — the PR review is the
gate. `learnings/pending/` holds only *unresolved* learnings that still need human
design. This is how the standard gets smarter over time without drifting silently.
