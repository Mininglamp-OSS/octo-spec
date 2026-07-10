# octo-code shared logic

Procedures shared by `octo-code` and (future) `octo-code-multica`. Both skills
reference this file so the engine call, completion check, and preflight never
drift between variants.

---

## 0. Slug validation (do this before the slug touches anything)

The task slug is **untrusted, chat-derived input** that gets interpolated into
filesystem paths (`.octospec/tasks/<slug>/`, the worktree dir), a branch name,
and the shell command strings in §A/§E. An unvalidated slug containing `../` is a
path-traversal (write/worktree outside the intended tree); one containing shell
metacharacters is a command-injection surface.

**Hard requirement:** the slug MUST match `^[a-z0-9][a-z0-9-]*$` (lowercase
alphanumeric + hyphens, no leading hyphen, no `/`, no `..`, no whitespace, no
shell metacharacters) before it is used anywhere.

```bash
if ! printf '%s' "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]*$'; then
  echo "octo-code: refusing unsafe slug: $slug" >&2
  exit 1
fi
```

Derive the slug deterministically from the task (lowercase, spaces→`-`, strip
disallowed chars) and then assert the pattern; if it still fails, ask rather than
pass it through raw. Always double-quote `"<task-slug>"` in every command below as
defense in depth — but validation, not quoting, is the primary control.

## A. Preflight gate (run before any dispatch)

Refuse to start work unless all of these pass. Report the first failure; do not
push past it.

1. **Engine auth.** Claude Code must authenticate non-interactively.
   - Auth must live in `~/.claude/settings.json` `env` (so both native and any
     wrapper inherit it), **not** only in an interactive shell rc.
   - Smoke check:
     ```bash
     env -u ANTHROPIC_API_KEY -u ANTHROPIC_BASE_URL \
       claude -p "Reply with exactly: OCTO_CODE_AUTH_OK" --output-format json \
       | jq -r '.result'
     ```
     Expect `OCTO_CODE_AUTH_OK`. A `401` means the token/gateway in
     `settings.json` is missing or stale — fix that first.
2. **Repo allowlist + cwd mapping.** The requested repo must be on the configured
   allowlist, mapping to a known local checkout path. Never run against an
   arbitrary path from chat.
3. **octo-spec onboarding.** The target repo must carry `.octospec/` with a
   valid pin. If missing, run onboarding first (see section D) and surface that
   as a separate step, not silently.
4. **Concurrency isolation.** Use a per-task git worktree, not the shared
   checkout, so concurrent requests to the same repo don't collide:
   ```bash
   git -C "<repo>" worktree add "<repo>/.octo-code-wt/<task-slug>" -b "<branch>" origin/main
   ```

---

## B. Engine call — headless `claude -p`

Run Claude Code in headless mode with structured output. This is the load-bearing
choice: it gives a real completion signal and is resumable.

The `--allowedTools` list is **derived, not hardcoded**: a constant core plus the
target repo's own verify toolchain from `manifest.yaml` `verify.tools` (so a Go or
TS repo is not gated behind a Python assumption). Read `verify.tools` and expand
each into `Bash(<tool> *)`:

```bash
# ILLUSTRATIVE pseudocode (no runtime engine ships here). `read_verify_tools` is
# the verify:-scoped extractor from octo-code-doctor.sh (§F) — reuse that, don't
# re-parse ad hoc.
# constant core
TOOLS="Read,Edit,Write,Bash(git *),Bash(gh *)"
# derive from the repo's declared verify toolchain (verify.tools in manifest.yaml)
for t in $(read_verify_tools "<repo>/.octospec/manifest.yaml"); do
  # HARDEN: the manifest is repo-controlled input that widens an unattended
  # agent's command surface, so validate each token before trusting it. Accept
  # only a bare command name and REJECT grammar chars / shell wrappers:
  case "$t" in
    bash|sh|zsh|env|eval|exec) continue;;          # no shell wrappers
    *[!a-zA-Z0-9_.-]*) continue;;                  # no commas/parens/spaces/globs
  esac
  TOOLS="$TOOLS,Bash($t *)"
done   # Go → Bash(go *),Bash(gofmt *) ; TS → Bash(pnpm *),Bash(npx *) ; etc.

claude -p "<task prompt>" \
  --output-format json \
  --permission-mode acceptEdits \
  --allowedTools "$TOOLS" \
  --max-turns 40 \
  > run.json 2>run.err
```

Notes:
- **Permission mode.** Prefer `acceptEdits` + a scoped `--allowedTools` list over
  blanket `bypassPermissions`. Use `bypassPermissions` only inside a disposable
  sandbox. (Unattended runs have no human to approve a prompt; an unscoped run
  with no pre-approval just dies on the first tool gate.)
- **Do not use `--bare`.** Bare mode skips `CLAUDE.md` / skill auto-discovery,
  but octo-spec injects its rules *through* `CLAUDE.md` and `.octospec/`. Bare
  would blind the agent to the standard.
- **cwd** is the per-task worktree from preflight.
- The task prompt must tell the agent to read `CLAUDE.md` and run the full
  6-phase loop (Discover → Plan → Implement → Verify → Iterate → Finish),
  **pausing after Plan for the approval gate** (§B2) and including the
  Finish-phase learning reflow. Discover creates the task branch and commits the
  spec (discovery + spec) onto it — here the per-task **worktree branch from
  §A.4 IS that branch**, so the spec rides into the PR with no manual copy.
- **Verify must be independent.** The session that wrote the code must not
  self-certify. Run Verify as a **separate `claude -p` review** (fresh session,
  read-only tools) that checks the diff against the spec's Acceptance + injected
  rules + Out of scope, in addition to the repo `verify.gate`. See §C.
- **Implement is TDD (Red → Green → Refactor).** The task prompt must instruct the
  agent to write the approved Acceptance as failing tests and **commit them
  (`red: <slug>`) before any production code**, then write the minimal code to
  green, then refactor while staying green. Acceptance items marked `N/A(test)` in
  the spec get no test. The `red:`-before-code commit order is what the §C
  checklist verifies — an unattended run that writes tests *after* the code has
  not done TDD.

---

## B2. Approval pause (between Plan and Implement)

The spec must be **human-approved** before Implement. In an unattended run there
is no human at the keyboard, so the flow is **not** one continuous engine call —
it splits around a real pause:

1. **Plan half.** The engine runs Discover + Plan and STOPS after writing
   `.octospec/tasks/<slug>/spec.md` (revision 1). Instruct it in the task prompt
   to end the turn there without implementing. Post the spec back to the
   originating thread: *"Spec ready (r1). Reply `approve` to continue, or reply
   with changes."*
2. **Human decision.** Wait for the originator's reply. Do not auto-approve — the
   agent may not approve its own spec (comprehension gate, no self-approval).
3. **Approve + resume.** On `approve`, the orchestrator writes the approval record
   into the spec's `approvals:` frontmatter (`revision:` = current, `by:` = the
   originator's identity, `at:` = ISO8601 UTC) **and commits it**
   (`approve: <slug> r<rev>`) on the task branch — parity with local `/octospec
   approve`, so the sign-off is in git history. Then `--resume "$sid"` with a
   prompt to continue from Implement. On a change request, resume the Plan half
   instead and re-post the updated spec.
4. **Re-pause on revision bump.** If a later Iterate is *spec-changing*, the spec
   `revision` bumps and the prior approval is stale. Pause again and get the new
   revision approved before Implement resumes. Impl-only iterations do not bump
   the revision and need no re-approval.

> This means octo-code is **not** "one message → PR" — it is "one message → spec
> → human approve → PR". That pause is the point: sign-off happens at the spec
> boundary, not after the code already exists.

---

## C. Completion check + resume (do NOT trust a bare "done")

A single headless run can stop before a multi-phase task is complete. Always
verify against artifacts, then resume the same session if work remains.

1. Parse the JSON result:
   ```bash
   sid=$(jq -r '.session_id'      run.json)
   tr=$(jq  -r '.terminal_reason' run.json)
   cost=$(jq -r '.total_cost_usd' run.json)
   ```
2. **Artifact checklist** (the real definition of done — verify all that the task
   required):
   - the spec's current `revision` is approved (`approvals[]` has a matching
     entry) — an unapproved spec means Implement should never have run;
   - **Verify ran as an independent pass** — a review from a fresh session
     (not the implementing session) checked the diff against the spec's
     Acceptance; a "done" from the same session that wrote the code is not
     sufficient;
   - **the TDD trail matches the slice class** (the spec's `class:`): for a
     **behavior-change**, a `red:` commit precedes the production code, its tests
     failed on the pre-implementation tree and encode the approved Acceptance, and
     the green diff did not weaken them (git log order is the check), with a test
     per non-`N/A` item; for a **pure-relocation**, the behavior diff is
     byte-equivalent and the suite stays green; for a **characterization**, the
     net's assertions are discriminating;
   - expected branch exists and is pushed;
   - the repo gate is green: run the commands in `manifest.yaml` `verify.gate`
     (fall back to the repo's documented gate if no `verify:` block);
   - for rule-producing tasks: `.octospec/rules/<id>.md` **and** its
     `rules/_index.yaml` entry exist (learning landed, not stranded in
     `learnings/pending/`);
   - a **slim** journal entry written under `.octospec/journal/` (one-line result
     + `## Learning`; no per-task log.md);
   - OKF lint passes (`<octo-spec>/scripts/octospec-lint.sh .`);
   - **PR opened** (`gh pr view` succeeds).
3. If anything is missing, **resume** with a focused continuation prompt naming
   exactly what's left:
   ```bash
   claude -p "Not done yet. Remaining: <gap list>. Complete only these." \
     --resume "$sid" --output-format json --permission-mode acceptEdits \
     --allowedTools "..." > run.cont.json
   ```
   Re-run the artifact checklist. Cap resumes (e.g. 3) before escalating to a
   human — don't whack-a-mole.
4. **PR fallback.** Opening the PR is the step most often left undone. If branch
   + commits are pushed but no PR exists, the orchestrator opens it directly with
   `gh pr create` (filling the repo PR template) rather than resuming just for
   that.

---

## D. Onboarding fallback (repo not yet on octo-spec)

If preflight step 3 fails, onboard the repo (this is the "install" half of the
flow) before coding:

```bash
cp -r "<octo-spec>/templates/octospec-init" "<repo>/.octospec"
# confirm .octospec/manifest.yaml pin matches <octo-spec>/VERSION
GLOBAL_SRC="<octo-spec>" "<repo>/.octospec/scripts/octospec-sync.sh"
"<octo-spec>/scripts/octospec-lint.sh" "<repo>"
```

Commit `.octospec/`, root `.claude/`, `.github/PULL_REQUEST_TEMPLATE.md`, and the
updated `CLAUDE.md` / `AGENTS.md` (a one-time onboarding PR), then proceed to the
coding task.

---

## E. Cleanup

Remove the per-task worktree when done (success or give-up):

```bash
git -C "<repo>" worktree remove "<repo>/.octo-code-wt/<task-slug>" --force
```

---

## F. Install & doctor (one-message setup, honestly)

Team members install octo-code by sending the bot one message
(e.g. *"install octo-code"* / *"安装 octo-code"*). What that message can and
cannot do is the whole point of this section — do not over-promise.

**What one message CAN do — install the skill files.** The skill is just files.
The bot fetches `integrations/octo/skills/octo-code/` + `shared/` from octo-spec
into its own skills directory (git fetch / clawhub / copy), and auto-discovery
picks it up. This half is genuinely one-message.

**What one message CANNOT do — provision the host engine.** octo-code runs
`claude -p`, which needs the `claude` CLI installed and **non-interactively
authenticated**, plus `git` / `gh` / `jq` on the bot host. A chat message cannot
install or log in to a CLI on someone's machine. Claiming otherwise is the exact
"paper OK" failure octo-spec exists to prevent.

So the install flow is **two steps, the second automated**:

1. **Install the skill files** (one message).
2. **Run the doctor immediately and report the gaps**:
   ```bash
   <skill-dir>/shared/octo-code-doctor.sh            # human report
   <skill-dir>/shared/octo-code-doctor.sh --json     # machine-readable
   <skill-dir>/shared/octo-code-doctor.sh --repo <path>   # + require repo onboarding
   ```
   The doctor checks each guardrail precondition (claude CLI, headless auth smoke,
   git, gh auth, jq, optional python3, and — with `--repo` — the target repo's
   declared `verify.tools`). With `--repo`, the target repo's
   `.octospec` onboarding becomes a **required** check: a repo with no `.octospec/`
   or no manifest pin fails (exit 1), so an automated install flow never treats a
   non-onboarded repo as ready. The doctor prints `✅ / ⚠️ / ❌` per item with a
   fix hint. It is **read-only** — it never installs, logs in, or mutates a repo.
   Exit `0` = ready, `1` = a required check failed.

The bot relays the doctor result back into the thread verbatim-ish, so the
operator sees exactly what host setup remains (e.g. *"❌ claude auth — set
ANTHROPIC_* in ~/.claude/settings.json env"*). When the doctor is all-green,
octo-code is ready and the user can just say *"use octo-code to add X to repo Y"*.

> **Why a doctor instead of an installer.** The guardrail checklist in
> `octo-code/SKILL.md` is a list of *environment preconditions*. The doctor is
> that checklist made executable: it turns "did the operator set this up?" from a
> guess into a checked fact, before the first real run can fail on it.
