#!/usr/bin/env bash
# Regression test for octospec-sync.sh (Claude-only, skill-first).
# sync vendors _global/, refreshes managed template surfaces, materializes the
# repo-root .claude/ + .github/ scaffolding, and prunes obsolete commands. It does
# NOT write CLAUDE.md/AGENTS.md (the agent-instruction injection machine was
# removed) — so this test covers scaffolding, drift, version assertion, upgrade
# prune, and no-clobber, not block injection.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SRC_VER="$(tr -d '[:space:]' < "$REPO/VERSION")"   # for the stale-source upgrade case
fail=0

note() { printf '%s - %s\n' "$1" "$2"; }

# All temp dirs register with a single cleanup trap so an early exit never leaves
# throwaway repos behind.
TMP_DIRS=()
cleanup() { for d in "${TMP_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Template drift guard: the quickstart (README) tells users to copy
# templates/octospec-init -> .octospec and then run
# ./.octospec/scripts/octospec-sync.sh. That only works if the template ships a
# scripts/ dir, and the sync copy MUST stay byte-identical to the canonical
# scripts/ original — otherwise the vendored copy silently drifts from the
# tested source.
TPL="$REPO/templates/octospec-init/scripts"
for f in octospec-sync.sh; do
  if [ ! -f "$TPL/$f" ]; then
    note FAIL "template missing scripts/$f (quickstart would break)"; fail=1
  elif ! cmp -s "$REPO/scripts/$f" "$TPL/$f"; then
    note FAIL "template scripts/$f drifted from canonical scripts/$f"; fail=1
  else
    note ok "template scripts/$f present and identical to canonical"
  fi
done

# ---------------------------------------------------------------------------
# Quickstart end-to-end: reproduce the documented README quickstart verbatim in
# a fresh temp repo — copy the template to .octospec, then run the vendored
# script by its documented relative path. Must succeed and materialize the
# repo-root .claude/ scaffolding, with no "no such file" failure.
tmp3="$(mktemp -d)"; TMP_DIRS+=("$tmp3")
cd "$tmp3"
git init -q
cp -r "$REPO/templates/octospec-init" .octospec

set +e
out="$(GLOBAL_SRC="$REPO" ./.octospec/scripts/octospec-sync.sh 2>&1)"
code3=$?
set -e

if [ "$code3" -eq 0 ]; then
  note ok "quickstart (cp template + run vendored script) exits 0"
else
  note FAIL "quickstart failed (code=$code3)"; fail=1
  printf '%s\n' "$out"
fi

if printf '%s' "$out" | grep -qi "no such file"; then
  note FAIL "quickstart hit a 'no such file' error"; fail=1
fi

if [ -f .claude/commands/octospec.md ] && [ -f .claude/skills/octospec-workflow/SKILL.md ]; then
  note ok "quickstart materialized the /octospec command + workflow skill to root"
else
  note FAIL "quickstart did not materialize root .claude/ scaffolding"; fail=1
fi

# sync must NOT create CLAUDE.md/AGENTS.md (injection machine removed).
if [ ! -e CLAUDE.md ] && [ ! -e AGENTS.md ]; then
  note ok "sync did not create CLAUDE.md/AGENTS.md (no injection)"
else
  note FAIL "sync created CLAUDE.md/AGENTS.md — injection machine leaked back"; fail=1
fi

cd "$REPO"
rm -rf "$tmp3"

if [ "$fail" -eq 0 ]; then
  echo "quickstart end-to-end test: PASS"
else
  echo "quickstart end-to-end test: FAIL"
fi

# ---------------------------------------------------------------------------
# Version assertion (YUJ-5344): the manifest pin (inherits: octo-spec@X) must
# match the GLOBAL_SRC checkout's VERSION, asserted BEFORE any vendoring so a
# stale pin never silently ships the wrong global rules. GLOBAL_SRC=$REPO has
# VERSION=2.1.0, so the fixtures pin 2.1.0 on the happy path.

# [api] 1) pin == VERSION -> exit 0, _global vendored, and re-running is idempotent.
tmp4="$(mktemp -d)"; TMP_DIRS+=("$tmp4")
cd "$tmp4"
git init -q
mkdir -p .octospec
printf 'inherits: octo-spec@2.1.0\n' > .octospec/manifest.yaml

set +e
GLOBAL_SRC="$REPO" bash "$REPO/scripts/octospec-sync.sh" > out.log 2>&1
code4=$?
set -e

if [ "$code4" -eq 0 ]; then
  note ok "version-match sync exits 0 (pin 2.1.0 == VERSION 2.1.0)"
else
  note FAIL "version-match sync exited $code4"; fail=1
  cat out.log
fi

if [ -d .octospec/_global ] && [ -n "$(ls -A .octospec/_global 2>/dev/null)" ]; then
  note ok "version-match sync vendored the global rules into _global/"
else
  note FAIL "version-match sync did not vendor _global/"; fail=1
fi

first="$(find .octospec/_global .claude -type f 2>/dev/null | sort | xargs cat 2>/dev/null | cksum)"
set +e
GLOBAL_SRC="$REPO" bash "$REPO/scripts/octospec-sync.sh" > out.log 2>&1
code4b=$?
set -e
if [ "$code4b" -eq 0 ] && [ "$first" = "$(find .octospec/_global .claude -type f 2>/dev/null | sort | xargs cat 2>/dev/null | cksum)" ]; then
  note ok "version-match sync is idempotent (second run unchanged)"
else
  note FAIL "version-match sync not idempotent (code=$code4b)"; fail=1
fi

cd "$REPO"

# [api] 2) pin != VERSION -> non-zero, VERSION MISMATCH, NOTHING vendored.
tmp5="$(mktemp -d)"; TMP_DIRS+=("$tmp5")
cd "$tmp5"
git init -q
mkdir -p .octospec
printf 'inherits: octo-spec@9.9.9\n' > .octospec/manifest.yaml

set +e
out5="$(GLOBAL_SRC="$REPO" bash "$REPO/scripts/octospec-sync.sh" 2>&1)"
code5=$?
set -e

if [ "$code5" -ne 0 ]; then
  note ok "version-mismatch sync exits non-zero (code=$code5)"
else
  note FAIL "version-mismatch sync exited 0"; fail=1
fi

if printf '%s' "$out5" | grep -q "VERSION MISMATCH"; then
  note ok "version-mismatch stderr contains VERSION MISMATCH"
else
  note FAIL "version-mismatch stderr missing VERSION MISMATCH"; fail=1
  printf '%s\n' "$out5"
fi

if [ ! -e .octospec/_global ]; then
  note ok "version-mismatch aborted before vendoring (_global not created)"
else
  note FAIL "version-mismatch vendored _global despite mismatch"; fail=1
fi

cd "$REPO"

# [api] 3) escape hatch: pin != VERSION + OCTOSPEC_SKIP_VERSION_CHECK=1 -> exit 0.
tmp6="$(mktemp -d)"; TMP_DIRS+=("$tmp6")
cd "$tmp6"
git init -q
mkdir -p .octospec
printf 'inherits: octo-spec@9.9.9\n' > .octospec/manifest.yaml

set +e
OCTOSPEC_SKIP_VERSION_CHECK=1 GLOBAL_SRC="$REPO" bash "$REPO/scripts/octospec-sync.sh" > out.log 2>&1
code6=$?
set -e

if [ "$code6" -eq 0 ]; then
  note ok "escape hatch (SKIP_VERSION_CHECK=1) bypasses mismatch, exits 0"
else
  note FAIL "escape hatch did not bypass mismatch (code=$code6)"; fail=1
  cat out.log
fi

if [ -d .octospec/_global ] && [ -n "$(ls -A .octospec/_global 2>/dev/null)" ]; then
  note ok "escape hatch still vendors _global/"
else
  note FAIL "escape hatch did not vendor _global/"; fail=1
fi

cd "$REPO"

# [api] 4) boundary: GLOBAL_SRC without a VERSION file -> non-zero, "no VERSION file".
tmp7="$(mktemp -d)"; TMP_DIRS+=("$tmp7")
nover="$(mktemp -d)"; TMP_DIRS+=("$nover")   # GLOBAL_SRC dir with NO VERSION file
mkdir -p "$nover/global"
cd "$tmp7"
git init -q
mkdir -p .octospec
printf 'inherits: octo-spec@2.1.0\n' > .octospec/manifest.yaml

set +e
out7="$(GLOBAL_SRC="$nover" bash "$REPO/scripts/octospec-sync.sh" 2>&1)"
code7=$?
set -e

if [ "$code7" -ne 0 ]; then
  note ok "missing-VERSION-file sync exits non-zero (code=$code7)"
else
  note FAIL "missing-VERSION-file sync exited 0"; fail=1
fi

if printf '%s' "$out7" | grep -q "no VERSION file"; then
  note ok "missing-VERSION-file stderr contains 'no VERSION file'"
else
  note FAIL "missing-VERSION-file stderr missing 'no VERSION file'"; fail=1
  printf '%s\n' "$out7"
fi

cd "$REPO"

if [ "$fail" -eq 0 ]; then
  echo "version-assertion test: PASS"
else
  echo "version-assertion test: FAIL"
fi

# ---------------------------------------------------------------------------
# Root scaffolding materialization (YUJ-5579 GAP-2/GAP-3): the template tree
# carries .octospec/.claude/ (slash commands + skills) and
# .octospec/.github/PULL_REQUEST_TEMPLATE.md, but Claude Code only discovers
# slash commands/skills under the REPO ROOT .claude/ and GitHub only applies a
# PR template at the REPO ROOT .github/. Sync must materialize those out of
# .octospec/ to the root, install-if-missing (never clobber user edits), and be
# idempotent. Reproduce the documented quickstart (cp template -> .octospec).
tmp8="$(mktemp -d)"; TMP_DIRS+=("$tmp8")
cd "$tmp8"
git init -q
cp -r "$REPO/templates/octospec-init" .octospec

set +e
GLOBAL_SRC="$REPO" ./.octospec/scripts/octospec-sync.sh > out.log 2>&1
code8=$?
set -e

if [ "$code8" -eq 0 ]; then
  note ok "root-scaffolding sync exits 0"
else
  note FAIL "root-scaffolding sync exited $code8"; fail=1
  cat out.log
fi

# GAP-2: slash command discoverable at the repo root.
if [ -f .claude/commands/octospec.md ]; then
  note ok "slash command materialized to repo-root .claude/commands/"
else
  note FAIL "repo-root .claude/commands/octospec.md missing after sync"; fail=1
fi

# GAP-2: workflow skill discoverable at the repo root too.
if [ -f .claude/skills/octospec-workflow/SKILL.md ]; then
  note ok "workflow skill materialized to repo-root .claude/skills/"
else
  note FAIL "repo-root .claude/skills/ missing after sync"; fail=1
fi

# v2.1: the router command carries the autopilot phase.
if grep -q "autopilot" .claude/commands/octospec.md; then
  note ok "router command exposes the autopilot phase"
else
  note FAIL "autopilot phase missing from materialized octospec command"; fail=1
fi

# v2.1: the slim-journal template ships in the skeleton.
if [ -f .octospec/journal/_journal.template.md ]; then
  note ok "journal template present in .octospec/journal/"
else
  note FAIL ".octospec/journal/_journal.template.md missing"; fail=1
fi

# v2.1: the per-task log.md is gone — no phase should reference writing it.
if grep -rq "\.octospec/log\.md" .octospec/.claude .octospec/scripts; then
  note FAIL "dangling per-task .octospec/log.md reference survived"; fail=1
else
  note ok "no per-task log.md reference in skill/command/scripts"
fi

# GAP-3: PR template installed at the repo root where GitHub looks for it.
if [ -f .github/PULL_REQUEST_TEMPLATE.md ]; then
  note ok "PR template materialized to repo-root .github/PULL_REQUEST_TEMPLATE.md"
else
  note FAIL "repo-root .github/PULL_REQUEST_TEMPLATE.md missing after sync"; fail=1
fi

# GAP-3: the installed PR template matches the canonical source (no drift).
if cmp -s "$REPO/templates/PULL_REQUEST_TEMPLATE.md" .github/PULL_REQUEST_TEMPLATE.md; then
  note ok "installed PR template matches canonical templates/PULL_REQUEST_TEMPLATE.md"
else
  note FAIL "installed PR template differs from canonical source"; fail=1
fi

# Idempotency: a second run installs nothing new and still exits 0.
before_claude="$(find .claude -type f | sort | xargs -I{} md5sum {} 2>/dev/null)"
before_prt="$(md5sum .github/PULL_REQUEST_TEMPLATE.md)"
set +e
GLOBAL_SRC="$REPO" ./.octospec/scripts/octospec-sync.sh > out2.log 2>&1
code8b=$?
set -e
after_claude="$(find .claude -type f | sort | xargs -I{} md5sum {} 2>/dev/null)"
after_prt="$(md5sum .github/PULL_REQUEST_TEMPLATE.md)"
if [ "$code8b" -eq 0 ] && [ "$before_claude" = "$after_claude" ] && [ "$before_prt" = "$after_prt" ]; then
  note ok "root-scaffolding sync is idempotent (second run changes nothing)"
else
  note FAIL "root-scaffolding sync not idempotent (code=$code8b)"; fail=1
fi
if grep -q "kept 3 existing" out2.log && grep -q "PULL_REQUEST_TEMPLATE.md -> kept existing" out2.log; then
  note ok "idempotent second run reports existing files kept"
else
  note FAIL "second run did not report kept-existing scaffolding"; fail=1
fi

cd "$REPO"

# No-clobber: a user's own slash command + PR template survive sync, while
# missing siblings are still installed.
tmp9="$(mktemp -d)"; TMP_DIRS+=("$tmp9")
cd "$tmp9"
git init -q
cp -r "$REPO/templates/octospec-init" .octospec
mkdir -p .claude/commands .github
printf 'MY CUSTOM COMMAND KEEP ME\n' > .claude/commands/octospec.md
printf 'MY OWN PR TEMPLATE KEEP ME\n' > .github/PULL_REQUEST_TEMPLATE.md

set +e
GLOBAL_SRC="$REPO" ./.octospec/scripts/octospec-sync.sh > out.log 2>&1
code9=$?
set -e

if [ "$code9" -eq 0 ]; then
  note ok "no-clobber sync exits 0"
else
  note FAIL "no-clobber sync exited $code9"; fail=1
  cat out.log
fi

if grep -q "MY CUSTOM COMMAND KEEP ME" .claude/commands/octospec.md; then
  note ok "user's customized slash command left untouched"
else
  note FAIL "sync clobbered a user-customized slash command"; fail=1
fi

if grep -q "MY OWN PR TEMPLATE KEEP ME" .github/PULL_REQUEST_TEMPLATE.md; then
  note ok "user's own PR template left untouched"
else
  note FAIL "sync clobbered a user-owned PR template"; fail=1
fi

if [ -f .claude/skills/octospec-workflow/SKILL.md ] && [ -f .claude/skills/octospec-init/SKILL.md ]; then
  note ok "missing scaffolding still installed alongside the user's own command"
else
  note FAIL "sync skipped installing missing scaffolding"; fail=1
fi

cd "$REPO"

# Upgrade prune (STALE-SOURCE, the real upgrade path): an already-onboarded 1.x
# repo carries the deleted v1 commands in BOTH its vendored `.octospec/.claude/`
# AND at the repo root. On the documented upgrade (bump pin + re-run sync, WITHOUT
# manually re-copying the template into .octospec), sync must refresh the vendored
# `.octospec/.claude` from GLOBAL_SRC, then install the new router and prune the v1
# commands from root — else the pre-gate octospec-go flow bypasses the approval
# gate and the new router never lands. Modeling the stale source is the point: a
# test that pre-copies the fresh template would mask exactly this bug.
tmp10="$(mktemp -d)"; TMP_DIRS+=("$tmp10")
cd "$tmp10"
git init -q
# A 1.x-style vendored tree: old commands, old skill, NO octospec.md router.
mkdir -p .octospec/.claude/commands .octospec/.claude/skills/octospec-workflow
mkdir -p .octospec/scripts .claude/commands
for c in plan go check finish; do
  printf 'v1 %s\n' "$c" > ".octospec/.claude/commands/octospec-$c.md"
  printf 'v1 %s\n' "$c" > ".claude/commands/octospec-$c.md"   # root mirror
done
printf 'v1 skill\n' > .octospec/.claude/skills/octospec-workflow/SKILL.md
# pin bumped to the current VERSION (the documented upgrade action)
printf 'inherits: octo-spec@%s\n' "$SRC_VER" > .octospec/manifest.yaml
# scripts/ re-copied on upgrade (README step); this is what runs the sync.
cp "$REPO/templates/octospec-init/scripts/"* .octospec/scripts/
# a user's own, non-octospec command must never be pruned
printf 'MY DEPLOY CMD KEEP ME\n' > .claude/commands/deploy.md

set +e
GLOBAL_SRC="$REPO" ./.octospec/scripts/octospec-sync.sh > out.log 2>&1
code10=$?
set -e

if [ "$code10" -eq 0 ]; then
  note ok "stale-source upgrade sync exits 0"
else
  note FAIL "stale-source upgrade sync exited $code10"; fail=1; cat out.log
fi

# The vendored .claude must have been refreshed from GLOBAL_SRC (else prune/install
# reconcile against the stale 1.x copy — the root-cause the reviewers found).
if [ -f .octospec/.claude/commands/octospec.md ] && \
   [ ! -e .octospec/.claude/commands/octospec-go.md ]; then
  note ok "vendored .octospec/.claude refreshed from GLOBAL_SRC (router in, v1 out)"
else
  note FAIL "vendored .octospec/.claude not refreshed → stale-source bug persists"; fail=1
fi

stale_left=0
for c in octospec-plan octospec-go octospec-check octospec-finish; do
  [ -e ".claude/commands/$c.md" ] && stale_left=$((stale_left + 1))
done
if [ "$stale_left" -eq 0 ]; then
  note ok "upgrade prunes all four obsolete v1 octospec commands from root"
else
  note FAIL "upgrade left $stale_left obsolete v1 octospec command(s) → gate bypass"; fail=1
fi

if [ -f .claude/commands/octospec.md ]; then
  note ok "current octospec.md router installed at root after upgrade"
else
  note FAIL "octospec.md router missing at root after upgrade"; fail=1
fi

if grep -q "MY DEPLOY CMD KEEP ME" .claude/commands/deploy.md 2>/dev/null; then
  note ok "user's own non-octospec command left untouched by prune"
else
  note FAIL "prune removed a user's non-octospec command"; fail=1
fi

cd "$REPO"

if [ "$fail" -eq 0 ]; then
  echo "root-scaffolding materialization test: PASS"
else
  echo "root-scaffolding materialization test: FAIL"
fi
exit "$fail"
