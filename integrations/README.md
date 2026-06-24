# integrations/

Optional **host adapters** that let an agent runtime drive the octo-spec
engineering flow for end users. These are not part of the octo-spec core.

## Layering (read this first)

octo-spec core stays **spec-only** — its scripts do exactly three things
(`sync`, `lint`, `learning-reflow`) and it ships **no runtime engine**. Nothing
under `integrations/` changes that contract:

- Adapters here only **orchestrate and route**. They detect intent, locate the
  repo, launch a coding agent, and check completion.
- The actual engine is still an external coding agent (e.g. Claude Code), not
  octo-spec. The 4-phase reasoning is the agent's job, exactly as in the manual
  flow.

So "no runtime engine" remains true: integrations are thin glue, the engine is
elsewhere.

## Layout

```
integrations/
└── octo/                       # the octo coding flow (currently OpenClaw-backed)
    ├── README.md
    └── skills/
        ├── octo-code/          # ACP-free: one message → headless claude → PR
        ├── octo-code-multica/  # (future) multica-dispatched variant
        └── shared/             # logic shared across the variants (no drift)
```

The second layer is the **host/product surface** (`octo`); the third layer is the
**dispatch backend** (direct headless vs. multica). New hosts get a sibling of
`octo/`; new backends get a sibling skill under `octo/skills/`.

## Status

| Adapter | State | Backend |
|---|---|---|
| `octo/skills/octo-code` | usable (validated end-to-end) | direct headless `claude -p` |
| `octo/skills/octo-code-multica` | planned | multica issue dispatch |
