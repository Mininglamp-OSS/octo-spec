# Claude Code workflow

octo-spec is Claude Code first. The 4-phase loop maps to four slash commands
backed by thin scripts. No central server, no extra service — everything reads
and writes files in the repo.

## Zero install for team members

The slash commands are **committed to the repo** under `.claude/commands/`. A team
member does **not** install anything: `git clone` / `git pull` brings the commands
with the repo, and Claude Code picks up `/octospec-plan`, `/octospec-go`,
`/octospec-check`, `/octospec-finish` automatically. Commands version with the
repo, so everyone is always on the same workflow — nothing to install, nothing to
keep in sync by hand.

## Setup (once per repo, by a maintainer)

1. Initialize the skeleton: copy `templates/octospec-init` to `.octospec/`
   (this includes `.claude/commands/`, which moves to the repo root).
2. Pin the global version in `.octospec/manifest.yaml`.
3. Run `octospec-sync` to pull global rules into git-ignored `.octospec/_global/`.
4. Add the octospec block to your repo's `CLAUDE.md` (between
   `<!-- octospec:begin -->` / `<!-- octospec:end -->` markers — the sync owns
   that region; everything outside it is yours).
5. Commit. From here, every team member just pulls.

## The loop

| Command | Does | Writes |
|---|---|---|
| `/octospec-plan <task>` | Draft a task brief (AI may seed it from existing code; you confirm). | `tasks/<slug>/brief.md` |
| `/octospec-go <slug>` | Read the brief, inject the rules whose `inject_when` matches, write code (no commit). | `tasks/<slug>/context.yaml` + injection fingerprint |
| `/octospec-check <slug>` | Check the diff against injected rules; run lint/type-check/tests; self-fix. | (validation only) |
| `/octospec-finish <slug>` | Final check, record a shared journal entry, stage learnings, open a PR (body pre-filled with Linked Spec + COMPREHENSION). | `journal/shared/<slug>.md`, `learnings/pending/<slug>.md` |

## Rule injection

A rule is injected when its `inject_when.paths` glob matches a touched file **or**
its `inject_when.touches` tag is declared in the brief's load-bearing list. There
is an injection budget: when exceeded, load-bearing rules win, then higher
`priority`; truncated rules contribute only a summary line. The set of injected
rules is recorded in `context.yaml` with a content fingerprint for auditability.

## Promotion (learnings → rules)

`/octospec-finish` drops candidate learnings into `learnings/pending/`. Promoting
one into `rules/` is a deliberate, reviewed PR — not an automatic write. This is
how the standard gets smarter over time without drifting silently.
