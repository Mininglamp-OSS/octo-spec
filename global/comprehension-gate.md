---
id: comprehension-gate
tier: global
priority: 90
load_bearing: true
inject_when:
  paths: ["**"]
  touches: ["comprehension", "load-bearing", "architecture"]
source: self
supersedes: []
---

# Comprehension gate

For **load-bearing, architectural, or P0** changes, code that no human
understands must not merge. The gate adds two lightweight checkpoints around
high-risk work: a **spec-first** front and a **comprehension** back.

> Narrow trigger by design. The gate applies only to changes that are P0,
> architectural, or touch load-bearing behavior (behavior the production system
> depends on). Trivial changes (typo, docs, lint, pure config) are exempt.

## Spec-first (front)

Before implementation, the task brief must state:

- **Goal** — what behavior changes and why.
- **Load-bearing list** — which existing behaviors/contracts this touches.
- **Out of scope** — what this change deliberately does *not* touch.

## Comprehension (back)

The PR body must answer three questions — to load-bearing substance, not
boilerplate:

1. **What does this change actually do** to the load-bearing path? Describe the
   before/after behavior, not the file list.
2. **What could break** because of it? Name the dependents and the failure mode.
3. **How do you know it works** — what specific evidence (test, repro, trace)
   confirms the load-bearing behavior is correct?

## Gate

- **L1 (mechanical)**: PR has a Linked Spec + the three answers present.
  Missing → request changes.
- **L2 (semantic)**: a reviewer checks that the brief's load-bearing list covers
  what the diff actually touches and that the three answers address real
  substance. A spec↔diff gap → request changes, tagged `spec-miss`.
