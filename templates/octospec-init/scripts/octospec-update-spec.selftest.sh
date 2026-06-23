#!/usr/bin/env bash
# Self-test for octospec-update-spec.sh — exercises all three reflow calls and
# asserts the products. Runs against a throwaway slug namespace (selftest-*) and
# cleans up the drafts it creates, so it never leaves the repo dirty.
# Exit 0 = all pass.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/octospec-update-spec.sh"
# Run against an isolated throwaway .octospec/ fixture so the test never depends
# on (or pollutes) the directory the script ships in. The script honors the
# exported OCTOSPEC_DIR; the fixture's parent acts as the repo root.
FIXTURE_ROOT="$(mktemp -d)"
export OCTOSPEC_DIR="$FIXTURE_ROOT/.octospec"
mkdir -p "$OCTOSPEC_DIR/learnings/pending" "$OCTOSPEC_DIR/journal/by-actor" "$OCTOSPEC_DIR/rules"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT
PENDING="$OCTOSPEC_DIR/learnings/pending"
BY_ACTOR="$OCTOSPEC_DIR/journal/by-actor"
TEST_ACTOR="selftest-bot"

pass=0
fail=0

# check <description> -- runs the rest of the args as a command; pass iff it
# exits 0. Keeps assertions free of `A && B || C` foot-guns (no SC2015).
check() {
  local desc="$1"; shift
  if "$@"; then
    echo "  ok: $desc"
    pass=$((pass + 1))
  else
    echo "  FAIL: $desc" >&2
    fail=$((fail + 1))
  fi
}
contains() { printf '%s' "$2" | grep -qF -- "$1"; }
# refuses: succeeds iff the script exits non-zero for the given args.
refuses()  { ! "$SCRIPT" "$@" >/dev/null 2>&1; }
# refuses_stdin: like refuses but feeds empty stdin (for the no-learning case).
refuses_stdin() { ! "$SCRIPT" "$@" </dev/null >/dev/null 2>&1; }

cleanup() {
  rm -f "$PENDING"/selftest-*-rule-draft.md
  rm -rf "${BY_ACTOR:?}/$TEST_ACTOR"
  # default-actor test writes selftest-defactor.md under the git user's lane.
  find "$BY_ACTOR" -name 'selftest-defactor.md' -delete 2>/dev/null || true
}
trap cleanup EXIT
cleanup

echo "== 1. --kind=rule (draft + promotion issue body) =="
BODY="$("$SCRIPT" --slug selftest-rule --kind rule --load-bearing \
  --inject-touches "space,audit" --priority 88 \
  --learning $'Cross-Space writes must record an audit entry.\nUse audit.Record before returning.')"
DRAFT="$PENDING/selftest-rule-rule-draft.md"
check "draft file created" test -f "$DRAFT"
check "OKF type: Rule" grep -qx 'type: Rule' "$DRAFT"
for f in title description tags timestamp id tier priority load_bearing inject_when source; do
  check "frontmatter has $f" grep -qE "^(  )?${f}:" "$DRAFT"
done
check "--load-bearing -> true" grep -q 'load_bearing: true' "$DRAFT"
check "--priority honored" grep -q 'priority: 88' "$DRAFT"
check "inject touches present" grep -q '"audit"' "$DRAFT"
check "marked draft" grep -q 'status: draft' "$DRAFT"
check "issue body has COMPREHENSION" contains 'COMPREHENSION' "$BODY"
nq="$(printf '%s\n' "$BODY" | grep -cE '^[0-9]+\. \*\*')"
check "issue body has >=3 questions ($nq)" test "$nq" -ge 3
check "issue body Linked task" contains 'Linked task' "$BODY"
check "issue body links draft" contains 'selftest-rule-rule-draft.md' "$BODY"

echo "== 2. idempotency (rerun must not duplicate) =="
"$SCRIPT" --slug selftest-rule --kind rule --learning 'second run overwrites' --no-promote >/dev/null
n_after="$(find "$PENDING" -maxdepth 1 -name 'selftest-rule-rule-draft.md' | wc -l | tr -d ' ')"
check "still exactly one draft after rerun" test "$n_after" -eq 1
check "default overwrites content" grep -q 'second run overwrites' "$DRAFT"
"$SCRIPT" --slug selftest-rule --kind rule --learning 'THIRD run skipped' --skip-existing --no-promote >/dev/null
check "--skip-existing preserves prior draft" grep -q 'second run overwrites' "$DRAFT"

echo "== 3. --kind=task (per-actor journal entry, committed in-repo) =="
OUT="$("$SCRIPT" --slug selftest-task --kind task --actor "$TEST_ACTOR" \
  --learning $'Reviewers should grep for raw c.JSON in error paths.\nIt is a recurring i18n bypass.' \
  --tags "review-pattern,i18n")"
JOURNAL="$BY_ACTOR/$TEST_ACTOR/selftest-task.md"
check "journal entry created" test -f "$JOURNAL"
check "task kind wrote NOTHING to learnings/pending" test ! -e "$PENDING/selftest-task-rule-draft.md"
check "stdout echoes repo-relative path" contains "journal/by-actor/$TEST_ACTOR/selftest-task.md" "$OUT"
check "OKF type: Journal" grep -qx 'type: Journal' "$JOURNAL"
for f in title description tags timestamp slug actor source; do
  check "frontmatter has $f" grep -qE "^${f}:" "$JOURNAL"
done
check "slug recorded" grep -q '^slug: selftest-task$' "$JOURNAL"
check "actor recorded" grep -q "^actor: $TEST_ACTOR\$" "$JOURNAL"
check "learning body present" grep -q 'recurring i18n bypass' "$JOURNAL"
check "tags carried (review-pattern)" grep -q '"review-pattern"' "$JOURNAL"
check "no external/memory leakage in output" sh -c "! printf '%s' \"\$1\" | grep -qiE 'nowledge|nmem|payload|space:'" _ "$OUT"

echo "== 4. --kind=task default actor + idempotency =="
"$SCRIPT" --slug selftest-task --kind task --actor "$TEST_ACTOR" \
  --learning 'second run overwrites journal' >/dev/null
n_journals="$(find "$BY_ACTOR/$TEST_ACTOR" -maxdepth 1 -name 'selftest-task.md' | wc -l | tr -d ' ')"
check "still exactly one journal after rerun" test "$n_journals" -eq 1
check "default overwrites journal content" grep -q 'second run overwrites journal' "$JOURNAL"
"$SCRIPT" --slug selftest-task --kind task --actor "$TEST_ACTOR" \
  --learning 'THIRD run skipped' --skip-existing >/dev/null 2>&1
check "--skip-existing preserves prior journal" grep -q 'second run overwrites journal' "$JOURNAL"
# default actor derives from git user.name and is normalized to [a-z0-9-]
DEF2="$("$SCRIPT" --slug selftest-defactor --kind task --learning 'x')"
check "default actor path is normalized + emitted" contains 'journal/by-actor/' "$DEF2"
REPO_ROOT="$(cd "$OCTOSPEC_DIR/.." && pwd)"
DEF_PATH="$REPO_ROOT/$(printf '%s' "$DEF2" | sed -n '1p')"
check "default actor file actually written" test -f "$DEF_PATH"
check "default actor handle is [a-z0-9-]" sh -c "printf '%s' \"\$1\" | grep -qE '^\\.octospec/journal/by-actor/[a-z][a-z0-9-]*/selftest-defactor\\.md$'" _ "$DEF2"
rm -f "$DEF_PATH"; rmdir "$(dirname "$DEF_PATH")" 2>/dev/null || true

echo "== 5. input validation / refusals =="
check "missing --kind refused" refuses --slug ok-slug --learning x
check "bad --kind refused" refuses --slug ok-slug --kind bogus --learning x
check "bad slug refused" refuses --slug Bad_Slug --kind task --learning x
check "empty learning refused" refuses_stdin --slug ok-slug --kind task

echo
echo "RESULT: $pass passed, $fail failed"
test "$fail" -eq 0
