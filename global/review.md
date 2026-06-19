---
type: Rule
title: Code review standards
description: Standards reviewers (human or AI) must apply before approving.
tags: ["review", "code-review"]
timestamp: 2026-06-19T00:00:00Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
id: review
tier: global
priority: 78
load_bearing: false
inject_when:
  paths: ["**"]
  touches: ["review", "code-review"]
source: self
supersedes: []
---

# Code review standards

Review is a quality gate, not a formality. The goal is to catch correctness,
security, and design problems before merge — not to nitpick style a linter
already covers.

## What every review must check

1. **Correctness** — does the change do what its spec/brief claims? Trace the
   load-bearing path, not just the happy path.
2. **Spec alignment** — does the diff actually satisfy the linked brief? Flag
   changes that touch load-bearing behavior the brief did not cover.
3. **Security** — input validation, authz/ACL boundaries, no fail-open paths,
   no secrets in code or logs.
4. **Tests** — does the change carry tests proportional to its risk?
5. **Blast radius** — what else depends on this? Is the change backward
   compatible where it must be?

## Verdict discipline

- Output a verdict via **approve** or **request-changes** only.
- Severity-tag findings: **P0** (blocker / security / data loss), **P1**
  (must fix before merge), **P2** (advisory / follow-up).
- A reviewer may not approve their own PR; use an independent reviewer identity.

## Re-review

- On re-review, state the prior head and what changed.
- Do not re-litigate already-resolved findings; focus on the new diff.
