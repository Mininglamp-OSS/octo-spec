#!/usr/bin/env bash
# octospec-lint — OKF conformance check for octo-spec knowledge files.
#
# Verifies that every knowledge .md file (rules, global constitution, example
# templates) is a valid OKF unit: it must start with a YAML frontmatter block
# and declare a non-empty `type`. This keeps the repository a valid OKF bundle
# so any OKF-aware tool or agent can consume it.
#
# Usage:
#   scripts/octospec-lint.sh [root]
#
# Exit codes: 0 = all conformant, 1 = one or more violations.
set -euo pipefail

ROOT="${1:-.}"

# Files/dirs that are prose or indexes, NOT OKF knowledge units, and are
# therefore exempt from the frontmatter+type requirement.
#   - index.md / log.md     : OKF structural files (human-readable, no frontmatter)
#   - README / docs / *.template.md : prose and templates
#   - .claude/**            : agent slash-command + skill prose
is_exempt() {
  case "$1" in
    */index.md|*/log.md|index.md|log.md) return 0 ;;
    */README.md|README.md) return 0 ;;
    */PULL_REQUEST_TEMPLATE.md|PULL_REQUEST_TEMPLATE.md) return 0 ;;
    */docs/*) return 0 ;;
    */.claude/*) return 0 ;;
    *_brief.template.md|*.template.md) return 0 ;;
  esac
  return 1
}

fail=0
checked=0

while IFS= read -r f; do
  if is_exempt "$f"; then
    continue
  fi
  checked=$((checked + 1))

  # 1) Must start with a frontmatter fence on line 1.
  first_line="$(head -n1 "$f")"
  if [ "$first_line" != "---" ]; then
    echo "FAIL $f: missing YAML frontmatter (file must start with '---')"
    fail=1
    continue
  fi

  # 2) Extract the frontmatter block (between the first two '---' fences).
  fm="$(awk 'NR==1 && $0=="---"{infm=1; next} infm && $0=="---"{exit} infm{print}' "$f")"
  if [ -z "$fm" ]; then
    echo "FAIL $f: empty or unterminated frontmatter block"
    fail=1
    continue
  fi

  # 3) Must declare a non-empty `type` (OKF's only required field).
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
