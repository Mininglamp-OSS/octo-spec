#!/usr/bin/env bash
# octospec-lint — OKF conformance check for octo-spec knowledge files.
#
# Verifies that every knowledge .md file is a valid OKF unit: it must start with
# a *properly terminated* YAML frontmatter block and declare a non-empty `type`.
# This keeps the repository a valid OKF bundle so any OKF-aware tool or agent can
# consume it.
#
# Scope is opt-in: only directories that hold knowledge units are linted
# (global rules and any */rules/ tree). Prose, docs, templates, index/log
# structural files, and agent command/skill prose are not knowledge units and
# are never linted. This avoids surprising a future contributor who adds, say,
# CONTRIBUTING.md at the repo root.
#
# Usage:
#   scripts/octospec-lint.sh [root]
#
# Exit codes: 0 = all conformant, 1 = one or more violations.
set -euo pipefail

ROOT="${1:-.}"

# Knowledge-unit globs (opt-in). A file is linted only if it matches one of
# these AND is not a structural/index file.
is_knowledge_file() {
  case "$1" in
    */rules/*.md) return 0 ;;             # repo or template rule files
    "$ROOT"/global/*.md|*/global/*.md) return 0 ;;  # global constitution rules
  esac
  return 1
}

# Structural files that live inside a knowledge dir but are NOT knowledge units
# (OKF index/log are plain markdown with no frontmatter).
is_structural() {
  case "$1" in
    */index.md|index.md|*/log.md|log.md) return 0 ;;
    */_index.yaml) return 0 ;;  # (defensive; not .md, but be explicit)
  esac
  return 1
}

fail=0
checked=0

while IFS= read -r f; do
  is_knowledge_file "$f" || continue
  is_structural "$f" && continue
  checked=$((checked + 1))

  # 1) Must start with a frontmatter fence on line 1.
  if [ "$(head -n1 "$f")" != "---" ]; then
    echo "FAIL $f: missing YAML frontmatter (file must start with '---')"
    fail=1
    continue
  fi

  # 2) Frontmatter must be terminated by a closing '---' fence. Detect whether
  #    a closing fence was actually seen (not just EOF).
  closed="$(awk 'NR==1 && $0=="---"{infm=1; next} infm && $0=="---"{print "yes"; exit}' "$f")"
  if [ "$closed" != "yes" ]; then
    echo "FAIL $f: unterminated YAML frontmatter (missing closing '---')"
    fail=1
    continue
  fi

  # 3) Extract the frontmatter block (between the first two '---' fences).
  fm="$(awk 'NR==1 && $0=="---"{infm=1; next} infm && $0=="---"{exit} infm{print}' "$f")"
  if [ -z "$fm" ]; then
    echo "FAIL $f: empty frontmatter block"
    fail=1
    continue
  fi

  # 4) Must declare a non-empty `type` (OKF's only required field).
  type_val="$(printf '%s\n' "$fm" | sed -n 's/^type:[[:space:]]*//p' | head -n1 | tr -d '[:space:]')"
  if [ -z "$type_val" ]; then
    echo "FAIL $f: missing required OKF field 'type'"
    fail=1
    continue
  fi
done < <(find "$ROOT" -type f -name '*.md' -not -path '*/.git/*' | sort)

if [ "$fail" -eq 0 ]; then
  echo "octospec-lint: OK ($checked knowledge file(s) conform to OKF)"
else
  echo "octospec-lint: FAILED — fix the violations above"
fi
exit "$fail"
