---
type: Rule
title: Comprehension gate
description: Load-bearing or architectural changes require demonstrated understanding before merge.
tags: ["comprehension", "load-bearing", "architecture"]
timestamp: 2026-07-08T00:00:00Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
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

Before implementation, the task spec must state:

- **Goal** — what behavior changes and why.
- **Load-bearing list** — which existing behaviors/contracts this touches.
- **Out of scope** — what this change deliberately does *not* touch.

## Approval gate (spec sign-off before Implement)

The spec must be **approved by a human before Implement may start** — sign-off
happens at the spec boundary, not after the code exists. Approval binds to the
spec's exact `revision`:

- Each approval records the `revision` it approved, `by` whom, and `at` when
  (in the spec's `approvals:` frontmatter).
- Implement refuses to run unless an approval exists for the spec's **current**
  `revision`. An agent must never approve its own spec (no self-approval).
- A *spec-changing* iteration bumps `revision`, which invalidates the prior
  approval — the new revision must be re-approved before Implement resumes. An
  impl-only fix does not touch the spec and needs no re-approval.

Because approval is revision-bound, it is a **machine-checkable** front gate: a
diff whose spec has no approval matching its current revision has not been
signed off, regardless of what the PR body claims.

## Independent verify (no self-review)

Verify is a **separate, fresh-context pass** — the same context that wrote the
code must not certify its own work (the same "no self-approval" principle that
guards the front gate also guards the back). An independent reviewer (a
fresh-context subagent such as `code-reviewer`/`verifier`, or a separate review
invocation) checks the diff against the spec's **Acceptance**, the injected
rules, and the **Out of scope** list — in addition to the repo's automated gate.
A bare "done" from the implementing context is not verification.

### Red-first: the Acceptance is a pre-registered failing test

For a behavior change, the approved Acceptance is not verified after the fact — it
is **committed as a failing test before the production code** (TDD Red). This
turns the front gate's promise into a git-provable anchor: the reviewer confirms a
`red:` commit precedes the code, its tests actually failed on the
pre-implementation tree and **encode the approved Acceptance**, and the passing
diff did not quietly weaken them. A change that genuinely cannot carry a failing
test (pure refactor, UI/visual, config/dependency bump) is exempt only via an
explicit `N/A(test): <reason>` in the spec — a silent skip is a gate failure.
This is what makes the independent Verify objective rather than a matter of the
reviewer's taste.

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
- **L2 (semantic)**: a reviewer checks that the spec's load-bearing list covers
  what the diff actually touches and that the three answers address real
  substance. A spec↔diff gap → request changes, tagged `spec-miss`.
