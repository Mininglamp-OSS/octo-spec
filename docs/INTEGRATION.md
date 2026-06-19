# Integration architecture — how every entry point picks up octospec

octo-spec is designed so that **the engineering standard applies no matter how
code gets written** — a developer in Claude Code, a bot in Octo, a CLI agent
like Codex, or an orchestrator dispatching work. This document explains the
model and how each real-world entry point connects.

## The two-layer model

Don't try to teach every entry point perfectly. Instead, rely on two layers that
together cover all paths:

### Layer 1 — Active layer (auto-loaded, best-effort)

Any agent that runs **inside a repo checkout** automatically reads that repo's
agent-instruction file and the `.octospec/` directory:

- Claude Code reads `CLAUDE.md`
- Codex and most other agents read `AGENTS.md`
- (future: Gemini reads `GEMINI.md`, Cursor reads `.cursor/rules`, etc.)

octo-spec keeps **one source of truth** for the instruction block and syncs it
into every agent-instruction file that exists in the repo (via `octospec-sync`),
using `<!-- octospec:begin -->` / `<!-- octospec:end -->` markers. The wording is
tool-neutral, so whichever file an agent reads, it gets the same guidance:
read the matching `.octospec/rules/`, capture a task brief, fill the PR's
comprehension questions.

This layer makes agents **do the right thing by default**. It is guidance, not a
hard gate — an agent could ignore it.

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
Even if an entry point fails to auto-load the rules, load-bearing changes still
can't merge without passing Layer 2.

## Entry points → how each connects

| Scenario | Who writes the code | Reads instructions from | Auto? | Notes |
|---|---|---|---|---|
| **1. Local Claude Code** | Claude Code in the checkout | `CLAUDE.md` + `.octospec/` | ✅ auto | Plus `/octospec-*` slash commands |
| **2b. Orchestrator → local Claude Code / Codex** | CC / Codex spawned in the checkout | `CLAUDE.md` / `AGENTS.md` | ✅ auto | As long as the spawn cwd is the repo root |
| **2c. Orchestrator → dispatch system** | Agent runs CC/Codex in a checkout | `CLAUDE.md` / `AGENTS.md` + brief | ✅ auto | Dispatch brief adds a "read `.octospec`" pointer; dogfooded on #344 → PR #420 |
| **2a. Orchestrator writes code directly** | The orchestrator itself (not checkout-anchored) | — | ⚠️ **not auto** | See decision below |

### Decision: scenario 2a is closed, not patched

An orchestrator-style gateway agent is **not anchored to any checkout**; its
system prompt is global, not per-repo, so it cannot reliably auto-load a specific
repo's `.octospec/`. Rather than bolt on a fragile rule ("remember to read the
repo's spec before writing"), which will eventually drift and be forgotten:

> **Governed-repo code is always written by a checkout-anchored executor**
> (local Claude Code, an ACP agent like Codex, or a dispatched agent). The
> orchestrator does what it is best at — gathering requirements, decomposing
> work, and dispatching — and spawns an anchored agent to write the code instead
> of writing it itself.

This keeps **exactly one enforced path**: the orchestrator never edits a governed
repo directly, so octospec is always in effect. If a change ever did slip through
directly, Layer 2 (the PR gate) still catches load-bearing work.

## Adding a new entry point later

1. If it's a new agent tool with its own instruction file (e.g. `GEMINI.md`),
   add that filename to `octospec-sync` so the shared block is synced there too.
2. If it's a new way to dispatch work, make sure its task brief includes the
   "read `.octospec/`" pointer.
3. You never need to weaken Layer 2 — it's the safety net for every path.
