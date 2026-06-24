# integrations/octo/

The **octo coding flow**: a team member sends a plain-language coding request in
octo (an IM surface), and a bot carries it through the full octo-spec loop —
onboarding check → Claude Code (headless) running the 4-phase loop → a PR — and
reports back in the originating thread. The user never opens Claude Code.

> **What this is, technically.** The current implementation is an OpenClaw bot
> skill (`SKILL.md` format) that the bot loads. `octo` is the product/team
> surface; OpenClaw is the runtime underneath. The flow is named after the
> surface team members actually use, consistent with the `octo-*` family
> (octo-spec / octo-server / …). If the runtime ever changes, this naming still
> holds.

## Skills

- **`skills/octo-code/`** — the ACP-free, direct path. One message → headless
  `claude -p` runs the octo-spec 4-phase loop → PR. **No multica dependency.**
  This is the recommended starting point for team rollout.
- **`skills/octo-code-multica/`** — (future) the same flow, but dispatched
  through multica issues for heavier async tracking. Not built yet.
- **`skills/shared/`** — logic both variants depend on (engine call, completion
  check, preflight), kept in one place so the two skills never drift.

## The engine: headless `claude -p`, not ACP

Validation showed the ACP runtime path is fragile for unattended multi-phase
work (it reports "done" before finishing, and one-shot sessions can't be
resumed). The engine here is therefore **Claude Code headless mode**
(`claude -p --output-format json`), the vendor-recommended way to run Claude
Code programmatically:

- structured JSON result → a real completion signal (`terminal_reason`,
  `permission_denials`) instead of guessing;
- `--resume <session_id>` → native multi-turn continuation if a run stops early;
- `total_cost_usd` per run → a cost guardrail with a real number behind it.

See `skills/octo-code/SKILL.md` for the full procedure and the team-deployment
guardrail checklist.
