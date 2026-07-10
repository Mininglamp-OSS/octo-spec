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
  (record human sign-off of the spec), `next` (run the inferred next phase), and
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
   `.octospec/_global/` and **materializes the repo-root scaffolding** that tools
   only discover at the root: it copies `.octospec/.claude/` to `.claude/` (so
   Claude Code finds the `/octospec` command and the workflow skill) and
   `.octospec/.github/PULL_REQUEST_TEMPLATE.md` to `.github/` (so GitHub applies
   the PR template). This is install-if-missing — any file you have already
   customized at the root is left untouched, and re-running is idempotent. Sync
   does **not** write `CLAUDE.md` / `AGENTS.md` — octospec is discovered through
   the Claude Code skill + command under `.claude/`.
4. Commit (including the materialized root `.claude/` and `.github/`). From here,
   every team member just pulls.

## The loop

| Command | Does | Writes |
|---|---|---|
| `/octospec discover <task>` | Create the task branch; read-only exploration of the code the task touches. | `tasks/<slug>/discovery.md` (committed) |
| `/octospec plan <slug>` | Derive a spec from discovery; commit it; stop for human approval. | `tasks/<slug>/spec.md` (revision 1) |
| `/octospec approve <slug>` | Record + commit human sign-off of the spec's current revision. | approval entry in `spec.md` |
| `/octospec implement <slug>` | Gate-check approval, inject matching rules, then **TDD**: commit failing Acceptance tests (`red:`) before code, write minimal code to green, refactor. | (red tests + code) |
| `/octospec verify <slug>` | Dispatch an **independent reviewer** (fresh context) vs injected rules + Acceptance + Out of scope; confirm the `red:` commit precedes the code and tests encode Acceptance; run `verify.gate`. No self-review. | (validation only) |
| `/octospec iterate <slug>` | Disciplined rework: impl/test-only → re-Verify (test fix is its own commit); spec-changing → bump revision + re-approve. | `spec.md` Iteration Log (spec-changing only) |
| `/octospec finish <slug>` | Final gate, slim journal (result + Learning), land learnings in-PR, open a PR (Linked Spec + COMPREHENSION). | `journal/<slug>.md` |
| `/octospec autopilot <slug>` | After approval, run Implement → Verify → (impl/test-only Iterate ≤2) → Finish unattended, stopping at "PR opened". | (as above) |

`/octospec next <slug>` runs the inferred next phase; `/octospec status <slug>`
reports progress read-only.

Because the branch is created at Discover and the spec is committed onto it, the
PR opened at Finish already contains discovery + spec + approval — no manual copy.

## TDD (Red → Green → Refactor)

Implement is test-first for behavior changes. The approved Acceptance is written
as **failing tests and committed (`red: <slug>`) before any production code**,
then the minimal code makes them green, then the code is refactored while staying
green. The `red:`-before-code commit order is a git-provable anchor: the
independent Verify confirms the tests failed pre-implementation, encode the
approved Acceptance, and were not weakened to fake a pass. A change that genuinely
can't carry a failing test (pure refactor, UI/visual, config bump) is exempt only
via an explicit `N/A(test): <reason>` in the spec — never a silent skip.

Each slice declares a **class** (in the spec) that fixes its Red obligation and
its Verify criterion:

- **behavior-change** — standard Red→Green; the Red test fails on an assertion.
- **pure-relocation** — `N/A(test)`; Verify = byte-equivalent diff + suite green.
- **characterization** — `N/A(test-first)`; Verify = discriminating assertions.

When the refactor target has no tests, use **characterization-first**: land a
characterization-net PR (pin current behavior green), then the extract PR under
that net. Verify effort is tiered by class — a full independent reviewer for
behavior-change, a lightweight byte-diff for pure-relocation.

## Autopilot

Once a spec is approved, no new *human* decision arises until the PR itself, so
`/octospec autopilot <slug>` runs the mechanical tail — Implement (Red→Green→
Refactor) → Verify → (impl/test-only Iterate, ≤2 retries) → Finish — unattended,
stopping at "PR opened". It **returns to the human** on a spec-changing failure
(revision bump → the new spec needs re-approval) or when retries are exhausted,
and it **never auto-merges** — the PR review is the second human gate.

## Approval gate

The spec must be human-approved before Implement runs. `/octospec approve` writes
an approval bound to the spec's current `revision`. `/octospec implement` refuses
unless an approval matches that revision — and an agent may never approve its own
spec. A spec-changing iteration bumps the revision, invalidating the old approval
so the new revision must be re-approved. This makes sign-off a machine-checkable
front gate, not a post-hoc formality.

## Rule injection

A rule is injected when its `inject_when.paths` glob matches a touched file **or**
its `inject_when.touches` tag is declared in the spec's load-bearing list (which
is why the Discover phase — grounding that list in real code — matters). Read the
full text of every matching rule and follow it, load-bearing rules first.

## Promotion (learnings → rules)

`/octospec finish` lands a reusable learning **in the same PR** (edit the relevant
`rules/<rule>.md`, or add a new rule + `_index.yaml` entry) — the PR review is the
gate. The helper drafts the rule at `tasks/<slug>/<slug>-rule-draft.md` (scratch,
deleted once landed); a learning that isn't rule-ready stays in the task journal's
`## Learning`. This is how the standard gets smarter over time without drifting
silently.
