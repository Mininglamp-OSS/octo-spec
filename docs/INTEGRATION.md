# Integration architecture — how code written here picks up octospec

octo-spec is **Claude-Code-first**. This document explains how the standard
reaches the code that gets written, and where it is actually enforced.

> **Scope (phase 1): Claude Code.** octospec is discovered through Claude Code's
> skill + command under `.claude/`. Distributing the workflow into other agents'
> native skill directories (Codex `.codex/skills`, Gemini `.gemini/skills`, …) is
> a planned future addition — see "Adding other agents later". There is **no
> injected instruction block** in `CLAUDE.md`/`AGENTS.md`; that machinery was
> removed in favor of the skill.

## The two-layer model

Two layers together cover the paths that matter:

### Layer 1 — Active layer (skill discovery, best-effort)

A developer working in **Claude Code inside the repo checkout** gets octospec
automatically:

- The **`octospec-workflow` skill** (committed under `.claude/skills/`) is
  auto-discovered — its name+description are always in context, and Claude loads
  the full 6-phase flow when a non-trivial coding task matches. This is the single
  source of truth for the workflow.
- The **`/octospec <phase> <slug>` command** (under `.claude/commands/`) is a
  manual entry into the same skill, for driving one phase on demand.
- The repo's `.octospec/` (rules, specs, journals) is read by both.

This layer makes Claude Code **do the right thing by default**. It is guidance,
not a hard gate — the model could fail to trigger the skill, or a different tool
could be used. That's fine, because of Layer 2.

### Layer 2 — Enforcement layer (at the PR, entry-point-independent)

Every path eventually converges on **one pull request**. That is the chokepoint
where the standard is actually enforced, regardless of who or what wrote the code:

- **PR template** — Linked Spec + the COMPREHENSION three questions
- **Comprehension gate** — load-bearing / architectural / P0 changes require
  demonstrated understanding before merge *(today: template + review convention;
  not yet hard-enforced in CI — see `docs/GETTING-STARTED.md`)*
- **Review** — human or AI reviewer applies the rules
- **CI** — repo tests + `octospec-lint` (OKF conformance for the spec repo).
  *Today CI enforces lint/tests; the comprehension gate is a review-time
  convention, planned to be CI-enforced.*

Because enforcement lives at the PR, **Layer 1 doesn't have to be perfect**.
Even if the skill never triggers, or code is written by a tool that doesn't know
octospec, load-bearing changes still can't merge without passing Layer 2.

## Entry points → how each connects

| Scenario | Who writes the code | Picks up octospec via | Auto? | Notes |
|---|---|---|---|---|
| **1. Local Claude Code** | Claude Code in the checkout | `octospec-workflow` skill + `/octospec` command + `.octospec/` | ✅ auto | The primary, fully-supported path |
| **2. Orchestrator → local Claude Code** | Claude Code spawned in the checkout | same skill/command | ✅ auto | As long as the spawn cwd is the repo root |
| **3. Orchestrator → dispatch system** | A dispatched Claude Code in a checkout | skill/command + dispatch brief | ✅ auto | The dispatch brief adds a "read `.octospec/`" pointer |
| **4. Orchestrator writes code directly** | The orchestrator itself (not checkout-anchored) | — | ⚠️ **not auto** | See decision below |
| **5. A non-Claude agent (Codex/Gemini/…)** | That agent in the checkout | — | ⚠️ **not yet** | Skill distribution to other agents is future work; today Layer 2 (the PR) still governs it |

### Decision: scenario 4 is closed, not patched

An orchestrator-style gateway agent is **not anchored to any checkout**; its
system prompt is global, not per-repo, so it cannot reliably auto-load a specific
repo's `.octospec/`. Rather than bolt on a fragile rule ("remember to read the
repo's spec before writing"), which will eventually drift and be forgotten:

> **Governed-repo code is always written by a checkout-anchored Claude Code**
> (local, or dispatched). The orchestrator does what it is best at — gathering
> requirements, decomposing work, and dispatching — and spawns an anchored agent
> to write the code instead of writing it itself.

This keeps **exactly one enforced path**: the orchestrator never edits a governed
repo directly, so octospec is always in effect. If a change ever did slip through
directly, Layer 2 (the PR gate) still catches load-bearing work.

## Adding other agents later

Every mainstream coding agent has a **native skills mechanism** with its own
directory (Codex `.codex/skills` / `.agents/skills`, Gemini CLI `.gemini/skills`,
Cursor `.cursor/rules`, …), all progressive-disclosure like Claude's. So the
future multi-agent path is to **distribute the same `octospec-workflow` skill
into each agent's native dir** (via `octospec-sync`), NOT to inject a duplicated
instruction block into `AGENTS.md`/`GEMINI.md`. That keeps one source of truth
(the skill) with per-agent delivery. Until then, non-Claude agents are governed
by Layer 2 (the PR) like any other path. You never need to weaken Layer 2 — it's
the safety net for every path.

## Host adapters (`integrations/`)

Beyond a developer running Claude Code in-repo, octo-spec ships optional **host
adapters** under `integrations/` that let a bot drive the whole flow for an end
user (message → onboarding → coding → PR), without the user opening a coding
agent.

This does **not** change the spec-only contract. Adapters are thin glue: they
route intent, launch an external coding engine, and check completion. The engine
(Claude Code headless `claude -p`) is still external; octo-spec itself ships
no runtime engine. See `integrations/README.md` for the layering and
`integrations/octo/skills/octo-code/` for the first adapter (ACP-free, headless
engine, no multica dependency).
