# octo-spec

**An out-of-the-box engineering standard for AI-assisted coding.**

AI writes code fast, but every session it starts from scratch — no memory of your
project, your conventions, or your team's requirements. octo-spec persists specs,
tasks, and project memory **into your repository**, so any coding agent works to
your team's engineering standards.

octo-spec is **git-native** and **Claude Code first**: there is no central server
to run and no extra service to install. Clone the repo, and the shared standards
come with it — reviewable, versioned, and improvable like any other code artifact.

## Two layers

octo-spec is split into two layers so shared standards and per-repo specifics
never fight each other:

- **Global ("constitution")** — this repository. Cross-repo conventions every
  project should follow: commit style, PR rules, review standards, security
  red lines, comprehension gate.
- **Per-repo ("local law")** — a `.octospec/` directory inside each business repo.
  Repo-specific rules that inherit from the global layer via a pinned version.

## Core ideas

| Capability | What it changes |
|---|---|
| **Auto-injected rules** | Write conventions once in `.octospec/rules/`, then let the relevant context be injected into each AI session instead of repeating yourself. |
| **Task-centered workflow** | Keep briefs, implementation context, and status in `.octospec/tasks/` so AI work stays structured. |
| **Project memory** | Shared journals in `.octospec/journal/` preserve what happened last time, so each new session starts with real context. |
| **Team-shared standards** | Specs live in the repo, so one person's hard-won rule benefits the whole team. |

## The 4-phase loop

```
Plan      → write a brief; AI may draft it from existing code, you confirm
Implement → AI writes code with the relevant rules auto-injected (no commit)
Verify    → diff is checked against rules + lint/type-check/tests, self-fixing
Finish    → a final check runs, then new learnings are promoted back into rules/
```

## Directory layout (per-repo `.octospec/`)

```
.octospec/
  manifest.yaml          # inherited global version (pinned), repo tier, owner
  rules/                 # the rule source of truth (injected on demand)
    <domain>.md
    _index.yaml          # rule list + inject triggers + priority
  tasks/<slug>/
    brief.md             # goal / background / load-bearing list / acceptance
    context.yaml         # injected rule ids + injection fingerprint
  journal/shared/<slug>.md   # team-visible structural learnings
  learnings/pending/<slug>.md # finish-stage candidates awaiting promotion to rules/
```

> Personal scratch journals are **not** stored in the repo tree. They live in
> `~/.octospec/journal/<repo>/<user>/` (machine-local) to avoid leaking private
> notes into the repository or pull requests.

## Quick start

```bash
# 1. In a business repo, initialize the .octospec/ skeleton
cp -r <path-to>/octo-spec/templates/octospec-init .octospec

# 2. Pin the global version in .octospec/manifest.yaml, then sync the global rules
./.octospec/scripts/octospec-sync.sh    # pulls global rules into git-ignored _global/

# 3. Point Claude Code at it: add the octospec block to your repo's CLAUDE.md
```

See [`docs/CLAUDE-WORKFLOW.md`](docs/CLAUDE-WORKFLOW.md) for the Claude Code slash
command workflow.

## License

See [LICENSE](LICENSE).
