---
type: Task
title: "Task: octospec-pre-pr-review"
description: Add a reusable, upgradeable pre-PR deep review skill.
tags: ["review", "code-review", "pull-request", "architecture"]
timestamp: 2026-09-04T00:00:00Z
slug: octospec-pre-pr-review
upstream: Mininglamp-OSS/octo-spec#24
source: self
---

# Task: octospec-pre-pr-review

## Goal

Ship a repository-discoverable `octospec-pre-pr-review` skill that audits the
complete PR candidate against requirements and rules, optionally fixes confirmed
blocking defects, runs risk-proportional verification, and prepares compliant
commits and pull requests only when explicitly requested.

## Background

Issue: https://github.com/Mininglamp-OSS/octo-spec/issues/24

The procedure captures lessons from a multi-repository Marketplace/Web review:
requirements and role contracts can drift, partial failures need compensation,
stale asynchronous responses can cross Space boundaries, and green narrow tests
are not sufficient evidence of merge readiness.

## Load-bearing list

- `review`: severity, evidence, re-review, and self-approval boundaries.
- `security`: authorization, tenant isolation, hostile input, and secret red lines.
- `pull-request`: linked spec, verification evidence, and comprehension output.
- `commit`: opt-in commit boundary and issue-linked Conventional Commits.
- `architecture`: filesystem discovery and pinned sync upgrade behavior.

## Out of scope

- Replacing independent formal PR review or allowing self-approval.
- Executing a coding engine or adding a hosted runtime service.
- Overwriting repository-owned custom skills or unrelated `.claude` files.
- Automatically committing, pushing, or opening PRs without explicit permission.

## Acceptance

- The skill is discoverable in the octo-spec repository and in newly onboarded
  repositories.
- After its vendored sync script is updated to the pinned release, an older
  installation receives missing canonical skills while preserving user-owned
  skills and files.
- The skill distinguishes review-only, review-and-fix, commit, push, and PR
  permissions and reviews the cumulative branch plus relevant uncommitted diff.
- Security red-line violations are P0; findings include reachable impact and exact
  references; fixes are re-reviewed and regression-tested where practical.
- Skill metadata/contract validation, OKF lint, sync-block tests, shell sync tests,
  copy-parity checks, and `git diff --check` pass.
- English and Chinese documentation explains direct invocation and independent
  reviewer requirements.
