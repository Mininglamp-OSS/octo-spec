#!/usr/bin/env bash
# Regression test for octospec-sync.sh's exit-code propagation.
# A refused (malformed-marker) agent file must make the whole sync exit non-zero,
# even though per-file isolation lets the other files sync. (PR #3 review: caller
# was swallowing the failure and exiting 0.)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
fail=0

note() { printf '%s - %s\n' "$1" "$2"; }

# Build a throwaway repo with a healthy CLAUDE.md and a corrupted AGENTS.md.
# All temp dirs register with a single cleanup trap so an early `set -e` exit (or
# a mid-test failure) never leaves throwaway repos behind.
TMP_DIRS=()
cleanup() { for d in "${TMP_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT
tmp="$(mktemp -d)"; TMP_DIRS+=("$tmp")
cd "$tmp"
git init -q
mkdir -p .octospec
printf 'inherits: octo-spec@1.1.0\n' > .octospec/manifest.yaml
printf '# CLAUDE\n\nteam rule\n' > CLAUDE.md
# orphan begin marker -> the python helper must REFUSE this file
printf '# AGENTS\n\n<!-- octospec:begin -->\nrule beta KEEP ME\n' > AGENTS.md

set +e
GLOBAL_SRC="$REPO" bash "$REPO/scripts/octospec-sync.sh" > out.log 2>&1
code=$?
set -e

if [ "$code" -ne 0 ]; then
  note ok "sync exits non-zero when an agent file is refused (code=$code)"
else
  note FAIL "sync exited 0 despite a refused file"; fail=1
fi

if grep -q "rule beta KEEP ME" AGENTS.md; then
  note ok "refused AGENTS.md left untouched (content preserved)"
else
  note FAIL "refused AGENTS.md lost content"; fail=1
fi

if grep -q "octospec:begin" CLAUDE.md && grep -q "team rule" CLAUDE.md; then
  note ok "healthy CLAUDE.md still synced (per-file isolation kept)"
else
  note FAIL "healthy CLAUDE.md not synced"; fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "shell-wrapper exit-code test: PASS"
else
  echo "shell-wrapper exit-code test: FAIL"
fi

# ---------------------------------------------------------------------------
# Bootstrap regression: a repo that starts with ONLY CLAUDE.md (the common
# initial state of an existing Claude Code repo) must still get AGENTS.md
# created, so Codex — which reads AGENTS.md — receives the octospec block.
# (PR #3 review: the old any_present bootstrap skipped AGENTS.md whenever any
# candidate already existed, so a CLAUDE.md-only repo silently never got it.)
tmp2="$(mktemp -d)"; TMP_DIRS+=("$tmp2")
cd "$tmp2"
git init -q
mkdir -p .octospec
printf 'inherits: octo-spec@1.1.0\n' > .octospec/manifest.yaml
printf '# CLAUDE\n\nteam rule keep me\n' > CLAUDE.md
# Intentionally NO AGENTS.md / GEMINI.md / QWEN.md.

set +e
GLOBAL_SRC="$REPO" bash "$REPO/scripts/octospec-sync.sh" > out.log 2>&1
code2=$?
set -e

if [ "$code2" -eq 0 ]; then
  note ok "sync of a CLAUDE.md-only repo exits 0"
else
  note FAIL "sync of a CLAUDE.md-only repo exited $code2"; fail=1
  cat out.log
fi

if [ -f AGENTS.md ]; then
  note ok "AGENTS.md created in a CLAUDE.md-only repo"
else
  note FAIL "AGENTS.md NOT created in a CLAUDE.md-only repo"; fail=1
fi

if grep -q "octospec:begin" AGENTS.md 2>/dev/null && grep -q "octospec:end" AGENTS.md 2>/dev/null; then
  note ok "bootstrapped AGENTS.md contains the octospec marker block"
else
  note FAIL "bootstrapped AGENTS.md missing octospec marker block"; fail=1
fi

if grep -q "octospec:begin" CLAUDE.md && grep -q "team rule keep me" CLAUDE.md; then
  note ok "existing CLAUDE.md still synced, no data loss"
else
  note FAIL "existing CLAUDE.md not synced or lost content"; fail=1
fi

# GEMINI.md / QWEN.md must NOT be force-created.
if [ ! -e GEMINI.md ] && [ ! -e QWEN.md ]; then
  note ok "GEMINI.md/QWEN.md not force-created (only-existing behavior kept)"
else
  note FAIL "GEMINI.md/QWEN.md were force-created"; fail=1
fi

rm -rf "$tmp2"

if [ "$fail" -eq 0 ]; then
  echo "shell-wrapper bootstrap test: PASS"
else
  echo "shell-wrapper bootstrap test: FAIL"
fi

# ---------------------------------------------------------------------------
# Template drift guard: the quickstart (README) tells users to copy
# templates/octospec-init -> .octospec and then run
# ./.octospec/scripts/octospec-sync.sh. That only works if the template ships a
# scripts/ dir, and those copies MUST stay byte-identical to the canonical
# scripts/ originals — otherwise the vendored copy silently drifts from the
# tested source. (PR #3 收口: template had no scripts/ at all, so the documented
# init failed with "no such file or directory".)
TPL="$REPO/templates/octospec-init/scripts"
for f in octospec-sync.sh octospec_sync_block.py; do
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
# script by its documented relative path. Must succeed and produce a synced
# CLAUDE.md, with no "no such file" failure.
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

if grep -q "octospec:begin" CLAUDE.md 2>/dev/null && grep -q "octospec:end" CLAUDE.md 2>/dev/null; then
  note ok "quickstart synced the octospec block into CLAUDE.md"
else
  note FAIL "quickstart did not sync CLAUDE.md"; fail=1
fi

cd "$REPO"
rm -rf "$tmp3"

if [ "$fail" -eq 0 ]; then
  echo "quickstart end-to-end test: PASS"
else
  echo "quickstart end-to-end test: FAIL"
fi
exit "$fail"
