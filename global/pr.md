---
type: Rule
title: Pull request conventions
description: How pull requests must be structured, described, and linked.
tags: ["pull-request", "review"]
timestamp: 2026-06-19T00:00:00Z
# --- octospec extension fields (OKF-permitted; consumers must preserve) ---
id: pr
tier: global
priority: 75
load_bearing: false
inject_when:
  paths: ["**"]
  touches: ["pull-request", "review"]
source: self
supersedes: []
---

# Pull request conventions

Every PR must be reviewable on its own. A reviewer should understand **what
changed, why, and how it was verified** without reading external context.

## Required PR body fields

The PR template enforces these. A PR missing them should be blocked.

- **Summary** — what this PR does, in plain language.
- **Linked Spec** — link to the task brief (`.octospec/tasks/<slug>/brief.md`)
  or the issue this implements, when the change touches load-bearing behavior.
- **How verified** — tests run, manual steps, or evidence.
- **COMPREHENSION** (load-bearing / architectural / P0 changes only) — answer the
  three questions in [`comprehension-gate.md`](comprehension-gate.md).

## Rules

- Keep PRs small and single-purpose. Split unrelated changes.
- A PR that touches load-bearing behavior without a linked spec/brief should be
  sent back for changes.
- Do not force-push or rebase another author's PR branch; ownership stays with
  the original author.
- Trivial changes (typo, pure docs, lint-only, pure config, pure dependency bump)
  are exempt from the spec/COMPREHENSION requirement.

## Review verdicts

- Use **approve** or **request-changes** for a verdict. Do not deliver a verdict
  as a plain comment.
- A reviewer may not approve their own pull request.
