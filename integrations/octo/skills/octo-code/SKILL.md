---
name: octo-code
description: Run the octo-spec engineering flow from an octo chat message. A team member sends a plain-language coding request ("add X to repo Y" / "fix bug Z"); the bot onboards the repo to octo-spec if needed, runs Claude Code in headless mode through the 4-phase loop (Plan/Implement/Verify/Finish incl. learning reflow), opens a PR, and reports back in the thread. Use for octo coding requests that should produce a real PR without the user opening Claude Code. ACP-free, no multica dependency.
user-invocable: false
---

# octo-code

Turn an octo chat coding request into a reviewed PR, end to end, without the user
opening Claude Code. The engine is **Claude Code headless mode** (`claude -p`);
the standard being followed is **octo-spec** (the repo this skill ships in).

> **Layering.** This is an *integration adapter*, not part of octo-spec core.
> octo-spec stays spec-only (sync / lint / learning-reflow, no runtime engine).
> This skill only orchestrates: it routes intent, launches the external engine,
> and checks completion. The 4-phase reasoning is the engine's job.

Shared procedures (preflight, engine call, completion check, onboarding,
cleanup) live in **`../shared/octo-code-core.md`** — read it; this file is the
entry flow that sequences those pieces.

## Install & setup (one message, then a doctor)

A team member installs octo-code by sending the bot one message
(*"install octo-code"* / *"安装 octo-code"*). Be honest about the two halves
(`shared/octo-code-core.md` §F):

1. **Skill files install in one message** — they are just files; the bot fetches
   `integrations/octo/skills/octo-code/` + `shared/` into its skills dir and
   auto-discovery picks them up.
2. **The host engine cannot be installed by a chat message.** `claude -p` needs
   the `claude` CLI installed + non-interactively authenticated, plus `git` /
   `gh` / `jq` on the bot host. So right after install, **run the doctor and
   report the gaps** instead of pretending the environment is ready:
   ```bash
   <skill-dir>/shared/octo-code-doctor.sh             # human ✅/⚠️/❌ report
   <skill-dir>/shared/octo-code-doctor.sh --json      # machine-readable
   <skill-dir>/shared/octo-code-doctor.sh --repo <p>   # + repo onboarding check
   ```
   The doctor is read-only and exits `0` only when every required precondition
   passes. Relay its output back to the thread so the operator sees exactly what
   host setup remains. When it is all-green, the user can just say *"use
   octo-code to add X to repo Y"*.

## When to use

Trigger when an octo message is a **coding request against a known repo**:
"add <feature> to <repo>", "fix <bug> in <repo>", "implement <X>". Not for
questions, discussions, or product decisions.

## Flow

1. **Parse intent.** Extract: target repo, task description, task slug. If repo
   is ambiguous or not on the allowlist, ask — do not guess a path.
   - 🔴 **The slug is untrusted chat-derived input.** It is interpolated into
     filesystem paths, a branch name, and shell command strings, so it MUST be
     validated before any such use: require it to match `^[a-z0-9][a-z0-9-]*$`
     (lowercase alphanumeric + hyphens, no leading hyphen). Reject anything with
     `/`, `..`, whitespace, or shell metacharacters — a crafted slug is a
     path-traversal and command-injection surface. If the derived slug fails the
     pattern, slugify it deterministically or ask; never pass it through raw. See
     `shared/octo-code-core.md` §0.

2. **Preflight gate** (`shared/octo-code-core.md` §A). Engine auth smoke +
   repo allowlist/cwd + octo-spec onboarded + per-task worktree. Stop on the
   first failure and report it. If not onboarded, run onboarding (§D) as an
   explicit step first.

3. **Build the task prompt.** Instruct the engine to:
   - read `CLAUDE.md` and follow the octo-spec standard;
   - run the full 4-phase loop: Plan (write `.octospec/tasks/<slug>/brief.md`)
     → Implement → Verify (`pytest`/repo gate green) → **Finish incl. learning
     reflow** (journal entry; if the task produced a reusable learning, land it
     in `.octospec/rules/<id>.md` + `rules/_index.yaml` *in this same PR*, not
     stranded in `learnings/pending/`);
   - create branch `<type>/<slug>`, conventional commit (git author = the
     configured bot identity), push, open a PR filling the PR template
     (Linked Spec + COMPREHENSION for load-bearing changes).

4. **Run the engine** (`shared/octo-code-core.md` §B): `claude -p` with
   `--output-format json`, scoped `--allowedTools`, `--permission-mode
   acceptEdits`, `--max-turns`, cwd = the worktree. Capture `run.json`.

5. **Completion check + resume** (`shared/octo-code-core.md` §C). Parse the JSON
   (`session_id`, `terminal_reason`, `total_cost_usd`), then verify the artifact
   checklist (branch pushed, tests green, rule+index landed if applicable,
   journal written, OKF lint OK, **PR opened**). If anything is missing,
   `--resume <session_id>` with a focused prompt naming the gaps. Cap resumes;
   open the PR directly as a fallback. **Never trust a bare "done."**

6. **Report back** in the originating octo thread: PR URL, test result, cost
   (`total_cost_usd`), and (if a rule was reflowed) which rule landed. Then
   clean up the worktree (`shared/octo-code-core.md` §E).

## Why headless, not ACP

`claude -p --output-format json` gives a structured completion signal
(`terminal_reason`, `permission_denials`), native resume (`--resume`), and
per-run cost — the three things unattended multi-phase work needs. The ACP
runtime path reported false "done" on multi-phase tasks and could not resume a
finished one-shot session. Headless is the vendor-recommended programmatic entry
point and is the engine of record here.

## Team-deployment guardrail checklist

Every bot host that runs octo-code must have these set **before** rollout — they
are environment preconditions, not things the skill can fix at request time:

1. **Engine auth** — `ANTHROPIC_*` in `~/.claude/settings.json` `env` (native +
   wrapper inherit it). Verify with the §A smoke (or `shared/octo-code-doctor.sh`,
   which runs it for you). Stale OAuth → 401.
2. **Permission posture** — scoped `--allowedTools` (preferred) or
   `permissions.defaultMode` in `settings.json`; unattended runs cannot answer a
   permission prompt.
3. **Completion verification** — always artifact-check; a headless run can stop
   early. (§C)
4. **Resume on gaps** — `--resume <session_id>`, capped, before escalating.
5. **PR-open fallback** — the orchestrator opens the PR if the engine left it
   undone.
6. **Repo allowlist + cwd mapping** — no arbitrary paths from chat.
7. **Per-task worktree** — concurrency isolation for same-repo parallel requests.
8. **Cost + turn caps** — `--max-turns`, and track `total_cost_usd`; set a per-
   request / per-user budget.
9. **Identity** — commit author / PR author = the configured bot identity, so
   CODEOWNERS / branch protection stay meaningful for multi-user dispatch.

Run `shared/octo-code-doctor.sh` before rollout to verify the host
prerequisites this checklist depends on: item 1 (engine auth, via the live §A
smoke), the `git` / `gh` / `jq` tools the flow shells out to, and — with
`--repo <path>` — item 6's repo onboarding (`.octospec/` pin). The runtime-only
items (2 permission posture, 3–5 completion/resume/PR-fallback, 7 worktree,
8 caps, 9 identity) are exercised during a real run, not by the doctor.

## How a team member uses it

No commands to memorize — plain language in the octo thread:

> *"use octo-code to add a rate-limit middleware to octo-server"*
> *"octo-code: fix the null-pointer in octo-web's login flow"*

The bot parses intent + repo, runs the flow above, and replies in-thread with the
PR URL, test result, and cost. The user only reviews/approves the PR.

## Validation

This flow was validated end-to-end against the sandbox repo
`yujiawei/octo-code-e2e` (kept as the regression fixture):
- onboarding (sync + OKF lint green);
- feature task → PR;
- bug-fix task → learning reflowed into a load-bearing rule (`input-validation`)
  + `_index.yaml` + journal;
- **injection closure**: a later task touching the same paths had that reflowed
  rule injected and applied (guarded an empty-input case it wasn't told about).

The guardrail checklist above is exactly the set of gaps that validation
surfaced.
