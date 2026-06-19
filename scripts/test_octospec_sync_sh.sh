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
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
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
exit "$fail"
