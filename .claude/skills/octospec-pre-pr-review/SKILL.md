---
name: octospec-pre-pr-review
description: >-
  Use when a developer asks for a rigorous pre-PR review, merge-readiness audit,
  review-and-fix pass, or wants to reduce reviewer findings before opening a PR.
  Supports one or multiple repositories/worktrees and requests such as "review
  this branch before PR", "审查并修复后提交", "帮我做提 PR 前检查", "看下这些
  commits 有什么问题", and "pre-PR audit". Reviews the complete change set
  against its brief and repository rules, traces security/authz/data/race/error
  paths, runs risk-proportional verification, fixes confirmed defects when asked,
  and commits only when explicitly requested. This is a self-review aid, not the
  independent formal approval required for merge.
---

# octospec pre-PR review

Run a skeptical, evidence-based review before a branch is offered to other
reviewers. The objective is not merely to make tests green; it is to find the
correctness, security, contract, concurrency, and maintainability problems that
an experienced reviewer would block.

This is a **pre-PR self-audit, not a formal review verdict**. The global rule's
`approve` / `request-changes` requirement applies when acting as an independent
reviewer on someone else's PR; this skill reports readiness because its operator
may also have authored or fixed the change.

This skill complements `octospec-workflow`:

- `octospec-workflow` structures Plan → Implement → Verify → Finish.
- `octospec-pre-pr-review` performs an adversarial final audit of the actual
  branch/worktree, optionally fixes findings, and prepares clean commits.

It does **not** replace independent PR review. Per the global review rule, do not
approve your own PR. Report merge readiness, not an `approve` verdict.

## Inputs

Resolve these from the request and repository state:

- repository/worktree path(s);
- target branch or exact commit(s);
- comparison base (normally merge-base with the PR target);
- whether the user asked for read-only review, review + fix, commit, push, or PR;
- linked issue/task brief and stated intent.

Never infer a worktree path from a repository name. Confirm ambiguous targets.
Do not include unrelated dirty files merely because they are present.

## Non-negotiable operating rules

1. **Preserve user work.** Start with `git status`, identify pre-existing dirty
   files, and never reset, checkout over, stash, clean, or rewrite them without
   explicit permission.
2. **Review the complete candidate.** Inspect both committed branch changes and
   relevant uncommitted changes. A last-commit-only review misses cumulative
   regressions.
3. **Requirements are a security boundary.** Read the linked brief, issue,
   `.octospec/rules/_index.yaml`, matching rules, and repository instructions.
   If implementation and brief conflict, do not silently choose one:
   - follow an explicit current human requirement and update the brief in the
     same change; or
   - flag the mismatch and stop that behavior from merging.
4. **Evidence over speculation.** A finding must name the reachable failure,
   affected behavior, and exact code location. Do not inflate style preferences
   into blockers.
5. **Fix causes, not symptoms.** Add a regression test that would fail before the
   fix whenever practical.
6. **No false green.** Check every command's exit status. Distinguish failures
   caused by the patch from verified pre-existing/environment failures.
7. **Commit/push boundaries.** Fixing files does not imply permission to commit;
   committing does not imply permission to push or open a PR. Only do each action
   when the user requested it.

## Workflow

### Phase 1 — Establish the review baseline

For every repository independently:

1. Record `pwd`, current branch/HEAD, `git status --short --branch`, worktree
   registration, and remotes/base branch where relevant.
2. Resolve the exact review range using an explicit commit parent, user-provided
   base, or merge-base. State the range in the final report.
3. Inventory:
   - commits in range;
   - changed, renamed, deleted, generated, and untracked files;
   - pre-existing dirty files;
   - generated artifacts that must match source annotations/schemas.
4. Read repository instructions and applicable octospec rules before judging the
   code. For endpoint changes, load that repository's API/OpenAPI skill or
   standard and run its required compatibility checks.
5. Classify the change by risk: authentication/authorization, tenant isolation,
   destructive mutation, persistence/migration, artifact/file handling,
   concurrency/async UI, public API, or ordinary local behavior.

When several repositories form one feature, build a contract matrix before
reviewing details: role/value encodings, routes, request/response fields, error
semantics, defaults, events, and ownership of each decision.

### Phase 2 — Review in independent passes

Use parallel independent reviewers/subagents when available, but personally
validate every reported blocker against code and tests. At minimum perform these
passes:

#### A. Intent, spec, and scope

- Does the cumulative diff implement the current requirement and acceptance
  criteria?
- Did behavior change outside the brief's load-bearing list or declared scope?
- Are docs, comments, generated specs, fixtures, and user-facing copy consistent
  with the implementation?
- For multi-repo work, do all sides use the same wire contract and enum/role
  encoding? Confirm against the authoritative producer, not only local comments.

#### B. Correctness and state transitions

Trace the main path and negative paths end to end:

- missing, malformed, stale, duplicate, and out-of-order input;
- partial failure between multi-step writes;
- retries and idempotency;
- empty/default states;
- create/update/delete and rollback/compensation;
- cache invalidation and read-after-write behavior.

For every multi-transaction workflow ask what happens if step N succeeds and
step N+1 fails. For ambiguous commit errors, reconcile authoritative state before
attempting a destructive rollback.

#### C. Security and isolation

Verify server-side enforcement, not UI visibility alone:

- identity and tenant/Space scope come from authoritative context;
- role checks use the authoritative encoding and exact allowed roles;
- cross-tenant reads/writes fail closed and do not leak existence;
- admins cannot see owner-only controls or invoke owner-only mutations;
- request bodies, query values, archives, URLs, Markdown, and config are treated
  as untrusted;
- logs and responses do not expose secrets or raw internal errors.

Treat authority expansion, cross-tenant exposure, data loss, and fail-open paths
as blockers.

#### D. Concurrency and lifecycle

Look specifically for:

- stale async responses overwriting state after tenant/route/selection changes;
- missing generation checks, abort handling, or unmount invalidation;
- check-then-act races and stale snapshots used for destructive cleanup;
- deadlocks, ambiguous database commit outcomes, and lock ordering;
- detached work without a deadline;
- cleanup that can delete shared/content-addressed objects;
- retries blocked by partially consumed tasks or stale pending rows.

A stale-reference cleanup must re-check authoritative references at deletion time,
use ownership/reference counting, or defer to a safe GC design. A snapshot taken
before releasing a lock is not sufficient proof that an object is still unused.

#### E. API, compatibility, and errors

- Route, operation ID, auth declaration, request/response schema, envelope, and
  generated specification agree.
- Error codes/messages are stable, sanitized, and mapped intentionally.
- Existing clients remain compatible; run the repository's API diff gate for
  changed endpoints.
- Database migrations are ordered, serialized, scoped, reversible where required,
  and tested.

#### F. Tests and operability

- Tests cover authorization truth tables, negative tenant cases, state-machine
  failures, retries, and races proportional to risk.
- Mocks and E2E handlers are hermetic; new API calls cannot fall through to a
  real proxy/backend.
- Tests wait for async work and do not hide meaningful `act`, unhandled promise,
  race, or resource-leak warnings.
- Logs/metrics make compensation and background failures observable without
  leaking sensitive values.

### Phase 3 — Rank findings and decide fixes

Use the global severities:

- **P0** — every violation of the global security red lines, including missing or
  fail-open authorization, cross-tenant leakage, secret exposure, unbounded
  hostile input, plus data loss/corruption or a broad release blocker.
- **P1** — concrete correctness, non-security contract, or race defect that must
  be fixed before merge. Authorization concerns are P1 only when validation
  proves no global security rule is violated.
- **P2** — worthwhile test, maintainability, or operability improvement that does
  not make the current behavior unsafe or incorrect.

For each finding provide:

1. severity and concise title;
2. exact file and line/range;
3. reachable failure scenario and impact;
4. why existing tests/checks miss it;
5. minimal safe fix and required regression test.

Deduplicate findings that share one root cause. If no actionable findings remain,
state that explicitly; do not invent issues to appear thorough.

When fix permission exists, fix P0/P1 findings and directly related P2 issues.
Do not broaden the change into unrelated refactors. Re-review the resulting diff
from the beginning; a fix is new code and can introduce new defects.

### Phase 4 — Verification ladder

Run the narrowest relevant checks first, then broader gates. Adapt commands to
repository instructions, but cover:

1. focused unit/component/package tests for changed behavior;
2. negative authorization/tenant and concurrency/race tests where applicable;
3. formatter and diff whitespace checks;
4. type-check, vet, lint, or static analysis;
5. complete affected-package tests;
6. repository-wide test/build gates when feasible;
7. API generation/check/diff for endpoint changes;
8. production build and i18n checks for user-facing web changes;
9. final `git diff --check` and status inspection.

Never report a timed-out or truncated command as passed. If a broad command is
noisy or times out, run exact focused commands and report both facts honestly.
Warnings should be classified as introduced, pre-existing, or unresolved.

### Phase 5 — Commit readiness

If the user requested commits:

1. review `git diff` and `git diff --cached` one last time;
2. stage only files belonging to the reviewed change;
3. run `git diff --cached --check`;
4. use an English Conventional Commit without `Co-Authored-By`; obey the global
   commit rule, including an issue footer (`Fixes #…` or `Refs #…`) when an issue
   exists, and explicitly report when no issue reference was provided;
5. keep repositories in separate commits and report each resulting SHA;
6. verify every worktree is clean (or list intentionally remaining files).

Do not push or create a PR unless requested.

### Phase 6 — Optional PR preparation

Only when the user explicitly requests a PR:

1. push without force to the intended remote branch;
2. populate the repository PR template with Summary, Linked Spec/issue, exact
   verification evidence, and the COMPREHENSION answers required for
   load-bearing, architectural, or P0 changes;
3. disclose residual risks and known pre-existing warnings;
4. return the PR URL and do not self-approve it.

## Final report

Report in this order:

1. **Outcome** — ready, not ready, or ready with stated residual risks.
2. **Findings fixed** — grouped P0/P1/P2 with short impact descriptions.
3. **Residual findings/risks** — including pre-existing warnings or design debt;
   never hide known unresolved races behind green tests.
4. **Verification evidence** — exact commands/categories and pass/fail status.
5. **Commits** — repository, branch, SHA, message; state whether pushed.
6. **Primary changed files** — clickable paths where the interface supports it.

Remember: this is a pre-PR self-review. The final report may say the branch is
ready to submit, but the formal PR still needs an independent reviewer identity.
