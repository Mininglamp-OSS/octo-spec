# octo-code shared logic

Procedures shared by `octo-code` and (future) `octo-code-multica`. Both skills
reference this file so the engine call, completion check, and preflight never
drift between variants.

---

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

```bash
claude -p "<task prompt>" \
  --output-format json \
  --permission-mode acceptEdits \
  --allowedTools "Read,Edit,Write,Bash(git *),Bash(gh *),Bash(python3 *),Bash(pytest *)" \
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
  4-phase loop including the Finish-phase learning reflow.

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
   - expected branch exists and is pushed;
   - tests green (`python3 -m pytest -q` or the repo's gate);
   - for rule-producing tasks: `.octospec/rules/<id>.md` **and** its
     `rules/_index.yaml` entry exist (learning landed, not stranded in
     `learnings/pending/`);
   - journal entry written under `.octospec/journal/`;
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
