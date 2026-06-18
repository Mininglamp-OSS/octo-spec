---
id: example-rule
tier: repo
priority: 50
load_bearing: false
inject_when:
  paths: ["src/example/**"]
  touches: ["example"]
source: self
supersedes: []
---

# Example rule (delete me)

This is a starter rule showing the expected shape. Replace it with a real,
atomic, checkable convention for this repo.

A good rule is:

- **Atomic** — one convention, not a chapter.
- **Checkable** — a reviewer (human or AI) can decide pass/fail.
- **Scoped** — `inject_when` targets the files/areas it actually governs, so it
  is only injected when relevant.

## Example

> All public API handlers must return errors through the shared error envelope;
> never write a raw status code from a handler.
