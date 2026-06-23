---
description: octospec Finish — final check, record journal + learnings, open a PR
argument-hint: <slug>
---

You are running the octospec **Finish** phase for task `$ARGUMENTS`.

1. Run the final verification gate one more time (lint / type-check / tests).
2. Write `.octospec/journal/shared/$ARGUMENTS.md` — a short, team-visible record:
   what was done, any structural learning, any gotcha worth remembering. Start
   the file with OKF frontmatter (`type: Journal`, plus `title`/`description`/
   `tags`/`timestamp`) so it stays a valid OKF unit and passes `octospec-lint`.
   Also add a dated entry to `.octospec/log.md` (create it if missing).
3. **Learning promotion (in-place write-back).** If this task produced a reusable
   learning, promote it **in the same PR** — do NOT stage it in
   `learnings/pending/` to wait for a separate PR (that PR never happens, so the
   learning stays stranded on the feature branch). Two cases:
   - **Existing rule applies** → edit the relevant `.octospec/rules/<rule>.md`
     in place (add/refine a bullet), bump its `timestamp`, and note the change in
     the journal. The PR review IS the gate for the rule edit.
   - **No rule fits yet** → create a new `.octospec/rules/<slug>.md` with full
     OKF frontmatter (`type: Rule`, `title`, `description`, `inject_when`,
     `priority`, `load_bearing`, `tier`, `source`, `timestamp`) and add it to
     `rules/_index.yaml`.
   The helper `scripts/octospec-update-spec.sh` drafts these artifacts (rule
   draft + promotion-issue body for rule-level, per-actor journal for
   task-level) without ever writing `rules/` on main directly.
   Only drop into `learnings/pending/` when the learning is genuinely
   *unresolved* (needs human design before it can become a rule) — pending is for
   open questions, not for finished learnings awaiting a phantom review PR.
4. Open a PR. Pre-fill the body using `.github/PULL_REQUEST_TEMPLATE.md`:
   - **Linked Spec** → `.octospec/tasks/$ARGUMENTS/brief.md`
   - **COMPREHENSION** three questions answered to substance (for load-bearing /
     architectural / P0 changes; omit for trivial ones).
5. Commit with a Conventional Commit message referencing the issue.
