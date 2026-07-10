# octo-spec

[English](README.md) | [简体中文](README.zh-CN.md)

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![OKF conformance](https://github.com/Mininglamp-OSS/octo-spec/actions/workflows/octospec-lint.yml/badge.svg)](https://github.com/Mininglamp-OSS/octo-spec/actions/workflows/octospec-lint.yml)
[![Version](https://img.shields.io/github/v/tag/Mininglamp-OSS/octo-spec?label=version&sort=semver)](https://github.com/Mininglamp-OSS/octo-spec/tags)

**An out-of-the-box engineering standard for AI-assisted coding** — **git-native, zero-service**, stored in an **open format (OKF)**, with a **two-layer constitution** (org-wide `_global` rules + repo-local rules).

**Without octo-spec:** every new AI session you re-explain your conventions —
commit style, error handling, which rules this change touches — and the agent
still drifts.

**With octo-spec:** the standards live in the repo. `git pull` brings them, and
any coding agent reads and follows them automatically — no re-explaining.

```mermaid
flowchart TD
    subgraph SOT["Source of truth (in the repo)"]
        R[".octospec/rules/<br/>team conventions"]
        G[".octospec/_global/<br/>org-wide rules (synced, git-ignored)"]
        SK[".claude/skills/octospec-workflow<br/>the 6-phase flow (source of truth)"]
    end

    subgraph Entry["Claude Code entry points"]
        SKILL["skill (auto-discovered)"]
        CMD["/octospec command (manual)"]
    end

    CC["Claude Code"]

    R --> SK
    G --> R
    SK --> SKILL
    SK --> CMD
    SKILL --> CC
    CMD --> CC
    R --> CC

    CC --> OUT["Code that follows<br/>the same rules"]
```

**One source of truth (`.octospec/` + the workflow skill), Claude-Code-first.**

AI writes code fast, but every session it starts from scratch — no memory of your
project, your conventions, or your team's requirements. octo-spec persists specs,
tasks, and project memory **into your repository**, so Claude Code works to your
team's engineering standards.

octo-spec is **git-native** and **Claude Code first**: there is no central server
to run and no extra service to install. Clone the repo, and the shared standards
come with it — reviewable, versioned, and improvable like any other code artifact.
(Governance for non-Claude agents happens at the PR gate today; distributing the
workflow skill into other agents' native skill dirs is planned — see
[Integration architecture](docs/INTEGRATION.md).)

## Prerequisites

- **git** — octo-spec is git-native; the standards travel with the repo.
- **bash** — to run `octospec-sync.sh` (onboarding) and the helper scripts.
- **PyYAML** — needed to run the OKF lint (`octospec-lint.sh`).
  Install with `pip install pyyaml`.
- **Claude Code** to execute the workflow (the skill + `/octospec` command).
  octo-spec ships the rules and scripts; the agent does the coding.

## Quick start

**Fastest path (zero shell): paste this one line to Claude Code:**

> Read https://raw.githubusercontent.com/Mininglamp-OSS/octo-spec/v2.1.0/BOOTSTRAP.md and follow it to onboard octo-spec into this repo.

It clones the pinned octo-spec, then runs the standard `octospec-init` onboarding for you. The manual steps below remain the source of truth.

> Using Claude Code? The **`octospec-init`** skill walks an agent through this
> exact onboarding for you (copy → confirm pin → sync → verify). The manual steps
> below are the same thing by hand, and remain the source of truth.

```bash
# 1. Initialize the .octospec/ skeleton (the template ships its own sync scripts).
cp -r <path-to>/octo-spec/templates/octospec-init .octospec

# 2. Confirm the version pin in .octospec/manifest.yaml. The template ships
#    pinned to the current release, so onboarding at the same version needs no
#    edit. Then point GLOBAL_SRC at an octo-spec checkout of that SAME version —
#    the pin must match the checkout's VERSION file, or sync fails fast.
export GLOBAL_SRC=/path/to/octo-spec

# 3. Sync. This vendors the global rules into .octospec/_global/ AND materializes
#    the repo-root scaffolding Claude Code expects: the /octospec command + the
#    workflow skill to .claude/, and the PR template to .github/. It does NOT
#    touch CLAUDE.md/AGENTS.md. Works out of the box, idempotent.
./.octospec/scripts/octospec-sync.sh

# 4. Self-check: run the OKF lint (not vendored — run it from the checkout).
"$GLOBAL_SRC/scripts/octospec-lint.sh" .
```

That's it — **onboarding is complete**. The repo now carries the rules, the
`/octospec` command + workflow skill (under the repo-root `.claude/`, so Claude
Code discovers them), and the PR template (under `.github/`). Commit the new files
(`.octospec/`, root `.claude/`, `.github/`); from here every teammate just
`git pull`s.

**How the loop runs from here:** ask Claude Code to "add a feature" / "fix
this bug" (the workflow skill triggers), or drive a single phase explicitly with
one command (`/octospec discover|plan|implement|verify|iterate|finish`, plus
`approve`, `autopilot`, `next`, `status`). The 6-phase loop is executed **by the agent** — there is no loop CLI
to paste (see
[The 6-phase loop](#the-6-phase-loop) below).

See [`docs/CLAUDE-WORKFLOW.md`](docs/CLAUDE-WORKFLOW.md) for the Claude Code
command workflow.

## Core ideas

| Capability | What it changes |
|---|---|
| **Auto-injected rules** | Write conventions once in `.octospec/rules/`, then let the relevant context be injected into each AI session instead of repeating yourself. |
| **Task-centered workflow** | Keep discovery notes, specs, and status in `.octospec/tasks/` so AI work stays structured. |
| **Project memory** | Journals in `.octospec/journal/` preserve what happened last time, so each new session starts with real context. |
| **Team-shared standards** | Specs live in the repo, so one person's hard-won rule benefits the whole team. |

## The 6-phase loop

```mermaid
flowchart LR
    D["Discover"] --> P["Plan"] --> A{"approved?"}
    A -->|yes| I["Implement"] --> V["Verify"]
    A -->|no| P
    V -->|pass| F["Finish"]
    V -->|fail| IT["Iterate"]
    IT -->|impl/test-only| V
    IT -->|spec-changing| P
    F -.promote learnings.-> D
```

```
Discover  → read-only: understand the code the task touches (writes discovery.md)
Plan      → derive a spec from discovery; a human APPROVES its revision
Implement → gate-checks approval, then TDD (Red→Green→Refactor) with rules injected
Verify    → an INDEPENDENT reviewer checks the diff vs the spec + the repo's verify.gate
Iterate   → (optional) rework; spec-changing rework re-triggers approval
Finish    → a final check runs, then new learnings are promoted back into rules/
            in the same PR (no dead-letter queue; rule-ready → rules/, else journal)
```

> **The loop is executed by your coding agent — it is not a set of pasteable CLI
> commands.** The `/octospec` command or the `octospec-workflow` skill drives
> the agent through these phases. **octo-spec itself ships no runtime engine**: its
> scripts only do **sync** (onboard / vendor global rules + materialize root
> scaffolding), **lint** (OKF conformance), and **learning-reflow** at Finish
> (`octospec-update-spec.sh`). The reasoning each phase needs is the agent's job.

## Two layers

octo-spec is split into two layers so shared standards and per-repo specifics
never fight each other:

- **Global ("constitution")** — this repository. Cross-repo conventions every
  project should follow: commit style, PR rules, review standards, security
  red lines, comprehension gate.
- **Per-repo ("local law")** — a `.octospec/` directory inside each business repo.
  Repo-specific rules that inherit from the global layer via a pinned version.

## Built on an open format (OKF)

octo-spec stores its rules, tasks, and journals as plain Markdown with YAML
frontmatter, compatible with the [Open Knowledge Format (OKF)](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
v0.1 — an open, Apache-2.0 knowledge format from Google Cloud's Knowledge Catalog.

This is a deliberate choice: knowledge is best represented in commonly accessible,
established formats that are readable by humans without tooling, parseable by
agents without bespoke SDKs, diffable in version control, and portable across
tools and organizations. By aligning with OKF, an `.octospec/` directory is a
valid OKF knowledge bundle — any OKF-aware tool or agent can read it — while
octospec adds its own workflow layer (on-demand rule injection, the 6-phase loop,
and review gates) on top as permitted OKF extension fields.

## Directory layout (per-repo `.octospec/`)

```
.octospec/
  manifest.yaml          # inherited global version (pinned), repo tier, owner
  rules/                 # the rule source of truth (injected on demand)
    <domain>.md
    _index.yaml          # rule list + inject triggers + priority
  tasks/<slug>/
    discovery.md           # Discover-phase notes: what the task touches
    spec.md               # goal / load-bearing list / acceptance / revision + approvals
    <slug>-rule-draft.md  # (transient) rule draft the helper writes, deleted once landed
  journal/<slug>.md        # per-task record + structural learnings
  scripts/
    octospec-update-spec.sh     # Finish-phase helper: drafts a rule + promotion
                                # material for landing it in the same PR
```

> Reusable learnings are promoted **in the same PR** at Finish (edit the relevant
> `rules/<rule>.md` in place, or add a new rule + `_index.yaml` entry) — the PR
> review is the gate. The helper drafts the rule at
> `tasks/<slug>/<slug>-rule-draft.md` (scratch, deleted once the rule lands); a
> learning that isn't rule-ready stays in the task journal's `## Learning`, never
> a separate dead-letter queue. The
> `.octospec/scripts/octospec-update-spec.sh` helper drafts these artifacts
> without ever writing `rules/` on main directly.

## OKF conformance

The knowledge files (the global rule files, any repo `rules/*.md`, and per-task
`tasks/**` specs / `journal/**` entries) are valid OKF units: each starts with a
properly terminated YAML frontmatter block that parses as valid YAML and declares
a non-empty `type`. The structural files `index.md` and `log.md` are intentionally
exempt (OKF index/log are plain markdown with no frontmatter), as are fill-in
`*.template.md` scaffolds. CI enforces this with `scripts/octospec-lint.sh` (a
YAML-aware linter; needs `python3` + PyYAML), so the format never drifts. Run it
locally with:

```bash
./scripts/octospec-lint.sh .
```

> In an onboarded repo the lint covers your own `rules/` and `tasks/**`. The
> vendored `.octospec/_global/` is a read-only cache of rules already linted in
> this repo's CI, so it is out of the onboarded repo's lint scope by design.

A human-readable rule catalog lives in [`global/index.md`](global/index.md), and
the change history in [`global/log.md`](global/log.md).

## Resources

| Doc | What's inside |
|---|---|
| [Quick start](#quick-start) | Onboard a repo in four commands (copy → pin → sync → lint). |
| [Getting started](docs/GETTING-STARTED.md) | 5-minute guide + usage examples + diagrams. |
| [Integration architecture](docs/INTEGRATION.md) | How every entry point (Claude Code, Codex, Octo bots, dispatch) picks up the standard. |
| [Claude Code workflow](docs/CLAUDE-WORKFLOW.md) | Slash commands + the zero-install / materialization model. |
| [Change history](global/log.md) | Dated log of global-rule changes. |

## FAQ

<details>
<summary><strong>Do I need to install anything?</strong></summary>

No service to run. Once a maintainer has onboarded the repo and committed the
result, every teammate just `git pull`s — the rules, the agent block, the slash
commands, and the PR template all come with the repo. To run the OKF lint you
need `python3` + PyYAML (see [Prerequisites](#prerequisites)).
</details>

<details>
<summary><strong>Does octo-spec run the coding loop for me?</strong></summary>

No. octo-spec ships the rules and three scripts (sync / lint / learning-reflow).
The Discover→Plan→Implement→Verify→Iterate→Finish loop is executed by your
**coding agent** (via the `/octospec` command or the `octospec-workflow` skill).
There is no runtime engine and no loop CLI to paste.
</details>

<details>
<summary><strong>What if I don't use it?</strong></summary>

Nothing changes for you. `.octospec/` is additive — it adds files, touches no
runtime code, and blocks no merge. Delete `.octospec/` to fully roll back.
</details>

<details>
<summary><strong>Where do rules come from?</strong></summary>

This repo's existing conventions, made atomic and checkable. Propose new ones via
a normal PR to `.octospec/rules/`. Promoting a learning into a rule is a regular
reviewed PR — that's how the standard gets smarter without drifting silently.
</details>

<details>
<summary><strong>Why did sync write files outside <code>.octospec/</code>?</strong></summary>

By design. Claude Code only discovers slash commands / skills under the repo-root
`.claude/`, and GitHub only applies a PR template at the repo-root `.github/`. So
sync materializes those out of `.octospec/` to the root. **octospec-managed** files
(the `/octospec` command, the `octospec-*` skills, the PR template) are refreshed
from source on every run so upgrades actually land; a file you authored yourself
(a non-octospec command/skill under `.claude/`) is install-if-missing and left
untouched. Idempotent on re-run.
</details>

## License

octo-spec is licensed under the **Apache License 2.0**. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Notes

<details>
<summary>Sync mechanics & caveats</summary>

- The template ships its own `scripts/` (`octospec-sync.sh`), so the copied `.octospec/` carries the sync script itself — you don't need a path back into the octo-spec checkout just to locate it. The global rules are still sourced from an octo-spec checkout at sync time (see `GLOBAL_SRC`).
- Sync vendors the global rules into git-ignored `.octospec/_global/`. It does **not** write `CLAUDE.md`/`AGENTS.md`/`GEMINI.md`/`QWEN.md` — octospec is discovered through the Claude Code skill + command under `.claude/` (the agent-instruction injection block was removed).
- Sync also **materializes repo-root scaffolding** that tools only discover at the root: it copies `.octospec/.claude/` (the `/octospec` command + workflow skill) to the repo-root `.claude/`, and `.octospec/.github/PULL_REQUEST_TEMPLATE.md` to `.github/`. **octospec-managed** files (the `octospec` command, the `octospec-*` skills, the PR template) are refreshed from source every run; a file you authored yourself under `.claude/` is install-if-missing and left untouched. It also **prunes** octospec-managed root commands (`.claude/commands/octospec*.md`) that the pinned version no longer ships, so an upgrade that removes a command actually removes it (never a user's own commands).
- **Upgrade in one step.** Sync refreshes the octospec-managed surfaces — the vendored `.octospec/.claude/`, `.octospec/.github/`, the fill-in templates, AND the materialized repo-root skill / command / PR template — from `GLOBAL_SRC` on every run, the same way it refreshes `_global/`. So to upgrade you only **bump the pin in `manifest.yaml` and re-run sync**; the new command/skill/PR-template land and obsolete commands are pruned automatically. Your content — `manifest.yaml`, real `tasks/`, `journal/`, `rules/`, and any non-octospec files you added under `.claude/` — is never touched.
- Re-run any time you bump the pin; it is idempotent. A second run reports the root scaffolding as already present.
- The script vendored under `.octospec/scripts/` is a byte-for-byte copy of the canonical `scripts/octospec-sync.sh` in this repo; CI (`scripts/test_octospec_sync_sh.sh`) asserts they stay identical, so the copy can never silently drift from the tested source. To upgrade the tooling **itself** (the sync script), re-copy the template `scripts/` from a newer octo-spec checkout — this is the one managed surface sync can't refresh in place (it is the running script).

</details>
