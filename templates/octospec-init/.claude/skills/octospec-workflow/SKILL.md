---
name: octospec-workflow
description: >-
  Use when implementing a feature, fixing a bug, or making any non-trivial code
  change in this repository. Drives the octospec 6-phase engineering flow
  (Discover, Plan, Implement, Verify, Iterate, Finish) so the change follows this
  repo's rules in .octospec/ and ships a PR with a linked, human-approved spec.
  Triggers on requests like "add ...", "implement ...", "fix ...", "refactor ...",
  "change the ... API", 写功能, 修 bug, 加接口, 改逻辑. Skip for trivial edits
  (typo, docs, lint, pure config) — those do not need the flow.
---

# octospec workflow

This repository uses the **octospec** engineering standard. When you are asked to
make a non-trivial code change here, run the 6-phase flow instead of editing code
directly. Rules live in `.octospec/` and are the source of truth for this repo's
conventions.

This skill is the **single source of truth** for what each phase does. The
`/octospec <phase> <slug>` command is a thin router into these same steps.

## When to run this

Run the flow for: a new feature, a bug fix, a refactor, an API change, or any
change that touches load-bearing behavior.

**Do NOT run the flow** for trivial changes: a typo, a docs-only edit, a
lint-only fix, a pure config or dependency bump. Just make those directly.

## The loop

```
Discover → Plan → [approval gate] → Implement → Verify ──pass──→ Finish
   │          ▲                          ▲            │
 branch       │                          │          fail
 + spec       │                          │            ▼
 commits      └───── Iterate (spec-changing) ◄── Iterate (impl-only)
```

Run the phases in order. Each maps to `/octospec <phase> <slug>`, which the user
can also invoke manually. **Two things need a human: `approve` (the scope
sign-off) and merging the PR. Everything between them can run unattended** — see
**Autopilot** below.

The task's own **git branch** is created at Discover and carries every artifact:
discovery, brief, the approval record, and the code all land as commits on it, so
the PR opened at Finish already contains the spec — nothing is copied by hand.

### 1. Discover
- Choose a short kebab-case `<slug>`.
- **Create the task branch** off the latest mainline (`git fetch origin`, then
  `git switch -c feat/<slug> origin/main`, or this repo's branch convention).
  Everything from here lands on this branch, so the PR carries the spec.
- Read `.octospec/tasks/_discovery.template.md`.
- **Read-only exploration**: inspect the code the task will touch — the
  load-bearing paths, their callers, contracts, isolation boundaries, blast
  radius. Do NOT write a brief or any code yet.
- Write `.octospec/tasks/<slug>/discovery.md`: Relevant files, Existing behavior,
  Contracts & blast radius, Risks & unknowns. **Commit it**
  (`discover: <slug>`).
- Purpose: an accurate load-bearing list in the next phase (which is what makes
  the right rules get injected in Implement).

### 2. Plan
- Read `.octospec/tasks/_brief.template.md` and the `discovery.md` you just wrote.
- Write `.octospec/tasks/<slug>/brief.md` with OKF frontmatter (`type: Task` +
  title/description/tags/timestamp, and `revision: 1`, `approvals: []`):
  - **Goal** — what behavior changes and why.
  - **Load-bearing list** — derive it from `discovery.md`. Use the same tags as
    `.octospec/rules/_index.yaml` `inject_when.touches` where they apply.
  - **Out of scope** — what this deliberately does NOT touch.
  - **Acceptance** — machine-checkable where possible.
- **Commit the brief** (`plan: <slug> r1`).
- **Show the brief and stop. It must be human-approved before Implement.**

### Approval gate (between Plan and Implement)

A brief may not proceed to Implement until a human has approved its **current**
`revision`. Approval is recorded in the brief's `approvals:` frontmatter:

```yaml
revision: 1
approvals:
  - revision: 1
    by: <git config user.name>
    at: <ISO8601 UTC>
```

- The human runs `/octospec approve <slug>`, which appends an approval entry for
  the current `revision` **and commits it** (`approve: <slug> r<rev>`) so the
  sign-off is tamper-evident in git history. **You must never write your own
  approval** — that would defeat the comprehension gate (no self-approval).
- Implement checks this gate as its first action (below).

### 3. Implement
- **Gate check first.** Read the brief's `revision` and `approvals`. Confirm an
  entry exists with `revision` == the current `revision`. If not, **refuse**:
  tell the user to review the brief and run `/octospec approve <slug>` (or
  `/octospec plan <slug>` to revise). Do not write any code until the gate passes.
- **Inject rules.** Read `.octospec/rules/_index.yaml` and `.octospec/_global/`
  (if synced). A rule applies when its `inject_when.paths` glob matches a file you
  will touch, OR its `inject_when.touches` tag is in the brief's load-bearing
  list. A repo-tier rule overrides a global one with the same id. **Read the full
  text of every matching rule and follow it; do load-bearing rules first.**
- Write the code following those rules, committing on the task branch.

### 4. Verify — an independent pass, not self-review
Verify is a **separate, fresh-context review**, not the implementing context
grading its own homework (that violates the "never self-approve in the same
active context" rule). The context that wrote the code must NOT self-certify.

- **Dispatch an independent reviewer.** Launch a fresh-context subagent
  (`code-reviewer` / `verifier`, or the `/review` skill) with only: the diff, the
  brief's **Acceptance**, the injected rules, and the **Out of scope** list. It
  checks the diff against each — tracing load-bearing paths, not just the happy
  path — and confirms nothing in Out of scope was touched.
- **Run the gate.** Run this repo's gate: the commands in `manifest.yaml`
  `verify.gate`. If no `verify:` block is present, fall back to the gates named in
  CLAUDE.md / AGENTS.md (lint / type-check / tests).
- If the independent review is clean **and** the gate passes, go to Finish.
  Otherwise go to Iterate (fixes are the implementer's job; re-review after).

### 5. Iterate (optional)
Only when Verify failed or surfaced a gap. Decide the kind of rework:
- **Impl-only** (the brief was right; the code was wrong): fix the code and go
  back to Verify. Do NOT touch the brief. Do NOT bump `revision`. Under Autopilot
  this retries at most **twice** before stopping for a human.
- **Spec-changing** (the load-bearing list, goal, scope, or acceptance was wrong
  or incomplete): update the brief, **bump `revision`**, add an **Iteration Log**
  entry stating the semantic reason (not the diff), commit it, then go back
  through the **approval gate** — the bump invalidated the prior approval, so the
  new revision must be re-approved before Implement resumes. Under Autopilot this
  **stops and returns to the human** (a new decision is required).

### 6. Finish
- Run the `verify.gate` once more.
- Write `.octospec/journal/<slug>.md` from `_journal.template.md`: a **one-line
  result** plus a `## Learning` section. Cross-reference the brief and PR rather
  than restating the Goal — the Learning is the journal's only unique value (it is
  the raw material for rules). Start it with OKF frontmatter (`type: Journal` +
  title/description/tags/timestamp). Do **not** maintain a per-task change log —
  the git history and the journal already carry the timeline and the detail.
- Promote any reusable learning **in this same PR**: edit the relevant
  `.octospec/rules/<rule>.md` in place (or add a new rule + `_index.yaml` entry) —
  the PR review is the gate. The helper `.octospec/scripts/octospec-update-spec.sh`
  gives you the raw material: `--kind=rule` → a draft in
  `learnings/pending/<slug>-rule-draft.md` + a promotion block on stdout. It never
  auto-writes `rules/`, so **you** copy the draft into `rules/<id>.md` and update
  `_index.yaml` here, in this PR, then drop the scratch draft. Only use
  `.octospec/learnings/pending/` for *unresolved* learnings that still need human
  design before becoming a rule; finished learnings must not be stranded there.
- Open a PR. Because the branch already carries discovery + brief + approval, the
  PR contains the spec automatically. Fill the PR template's **Linked Spec** (→
  the brief, noting the approved revision) and the **COMPREHENSION** three
  questions to substance, for load-bearing / architectural / P0 changes.

## Autopilot

`/octospec autopilot <slug>` runs the mechanical tail of the loop unattended:
**Implement → Verify → (impl-only Iterate, ≤2 retries) → Finish (open PR)**. It
exists because, once the brief is approved, no new *human* decision arises until
the PR itself — the middle phases are just "放行".

- **Precondition.** The brief's current `revision` must already be approved
  (autopilot never self-approves). If it is not, autopilot refuses and points the
  user at `/octospec approve <slug>`.
- **Stops and returns to the human** on: a **spec-changing** Iterate (the
  revision bumps → the new spec needs re-approval), or **impl-only retries
  exhausted** (2 failed fix→verify cycles). Report what blocked it.
- **Never auto-merges.** It stops at "PR opened". The PR review is the second
  human gate, by design.
- Verify inside autopilot is still the **independent** pass (§4) — a fresh
  reviewer, not the implementing context.

## Notes

- `/octospec autopilot <slug>` runs Implement → Verify → Finish unattended after
  approval, stopping only when a human decision is needed (see **Autopilot**).
- `/octospec next <slug>` inspects task state (branch? discovery? brief? approved?
  diff? verify result?) and runs the next phase for you.
- `/octospec status <slug>` reports the current phase and what is blocking,
  read-only.
- The flow is guidance; the repo's PR/CI checks are the enforcement layer. The
  approval gate is enforced by Implement refusing an unapproved revision.
