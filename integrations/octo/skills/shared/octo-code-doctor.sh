#!/usr/bin/env bash
# octo-code-doctor — environment health check for the octo-code adapter.
#
# octo-code's engine is Claude Code headless mode (`claude -p`), which depends on
# host-environment things a single chat message CANNOT install: the `claude` CLI,
# its non-interactive auth, git, gh, and jq. This script reports exactly what is
# present and what is missing, so "install octo-code" can be honest:
#   1. the skill files install in one step (they are just files);
#   2. this doctor then tells the operator what host setup is still required.
#
# Usage:
#   octo-code-doctor.sh [--repo <path> | --repo=<path>] [--json]
#
#   --repo <path>   also require that <path> is a git repo onboarded to octo-spec
#                   (carries .octospec/ with a manifest pin). With --repo, a
#                   non-onboarded repo is a REQUIRED failure (exit 1), matching
#                   the preflight contract (core §A.3) that onboarding must hold
#                   before a coding run.
#   --json          emit a machine-readable summary instead of the human report.
#
# Exit: 0 = all required checks pass (ready to run octo-code).
#       1 = one or more required checks failed (not ready).
#       2 = usage error.
#
# This script is read-only. It never installs, logs in, or mutates any repo.

set -u

REPO=""
JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      case "${2:-}" in
        ""|-*) echo "octo-code-doctor: --repo needs a path argument" >&2; exit 2 ;;
      esac
      REPO="$2"; shift 2 ;;
    --repo=*) REPO="${1#--repo=}"; [ -n "$REPO" ] || { echo "octo-code-doctor: --repo= needs a path" >&2; exit 2; }; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "octo-code-doctor: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Collected results: each entry is "STATUS|REQUIRED|NAME|DETAIL"
# STATUS = ok | fail | warn ; REQUIRED = req | opt
RESULTS=()
FAIL=0

add() { # status required name detail
  RESULTS+=("$1|$2|$3|$4")
  if [ "$1" = "fail" ] && [ "$2" = "req" ]; then FAIL=1; fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# 1. claude CLI present
if have claude; then
  CLAUDE_VER="$(claude --version 2>/dev/null | head -1 | tr -d '\r')"
  add ok req "claude CLI" "found${CLAUDE_VER:+ ($CLAUDE_VER)}"

  # 2. non-interactive auth smoke (the load-bearing check).
  #    Unset shell-level overrides so we test settings.json env, like a real run.
  #    Capture the engine's exit status separately, and require .result to EQUAL
  #    the sentinel exactly: a failed run that merely echoes the prompt (which
  #    contains the sentinel) must NOT be accepted as authenticated.
  AUTH_RAW="$(env -u ANTHROPIC_API_KEY -u ANTHROPIC_BASE_URL \
      claude -p "Reply with exactly this token and nothing else: OCTO_CODE_AUTH_OK" \
      --output-format json 2>/dev/null)"
  AUTH_RC=$?
  if have jq; then
    AUTH_RESULT="$(printf '%s' "$AUTH_RAW" | jq -r '.result // empty' 2>/dev/null)"
  else
    AUTH_RESULT="$AUTH_RAW"
  fi
  AUTH_RESULT_TRIMMED="$(printf '%s' "$AUTH_RESULT" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [ "$AUTH_RC" -eq 0 ] && [ "$AUTH_RESULT_TRIMMED" = "OCTO_CODE_AUTH_OK" ]; then
    add ok req "claude auth (headless)" "non-interactive auth OK"
  else
    add fail req "claude auth (headless)" \
      "headless smoke failed (exit=$AUTH_RC; .result must equal OCTO_CODE_AUTH_OK) — set ANTHROPIC_* in ~/.claude/settings.json env, then re-run. (got: $(printf '%s' "$AUTH_RESULT_TRIMMED" | head -c 80))"
  fi
else
  add fail req "claude CLI" "not found — install Claude Code (this cannot be done from a chat message; install on the bot host)"
  add fail req "claude auth (headless)" "skipped (claude CLI missing)"
fi

# 3. git
if have git; then
  add ok req "git" "$(git --version 2>/dev/null | tr -d '\r')"
else
  add fail req "git" "not found — required for worktrees / commits"
fi

# 4. gh (PR open + fallback)
if have gh; then
  if gh auth status >/dev/null 2>&1; then
    add ok req "gh (GitHub CLI)" "authenticated"
  else
    add fail req "gh (GitHub CLI)" "found but NOT authenticated — run 'gh auth login' on the host (needed to open PRs)"
  fi
else
  add fail req "gh (GitHub CLI)" "not found — required to open the PR"
fi

# 5. jq (parsing the headless JSON result)
if have jq; then
  add ok req "jq" "$(jq --version 2>/dev/null | tr -d '\r')"
else
  add fail req "jq" "not found — required to parse claude --output-format json"
fi

# 6. python3 + pytest (typical repo verify gate; warn, not hard-fail)
if have python3; then
  add ok opt "python3" "$(python3 --version 2>&1 | tr -d '\r')"
  if python3 -c 'import pytest' >/dev/null 2>&1; then
    add ok opt "pytest" "importable"
  else
    add warn opt "pytest" "not importable — only needed if the target repo's gate uses pytest"
  fi
else
  add warn opt "python3" "not found — only needed for python repo gates"
fi

# 7. repo onboarding check (when --repo given, this is a REQUIRED gate)
if [ -n "$REPO" ]; then
  if [ ! -d "$REPO" ]; then
    add fail req "repo path" "$REPO does not exist"
  elif ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    add fail req "repo is git" "$REPO is not a git repository"
  else
    add ok req "repo is git" "$REPO"
    if [ -d "$REPO/.octospec" ]; then
      PIN=""
      for f in "$REPO/.octospec/manifest.yaml" "$REPO/.octospec/manifest.yml"; do
        if [ -f "$f" ]; then
          # Canonical field is `inherits: octo-spec@X.Y.Z`; older/alt manifests
          # may use `version:`/`pin:`. Extract the RHS value, not the whole line.
          PIN="$(grep -E '^[[:space:]]*(inherits|version|pin)[[:space:]]*:' "$f" 2>/dev/null \
                 | head -1 | sed -E 's/^[[:space:]]*(inherits|version|pin)[[:space:]]*:[[:space:]]*//; s/[[:space:]]*(#.*)?$//' | tr -d '\r')"
        fi
        [ -n "$PIN" ] && break
      done
      if [ -n "$PIN" ]; then
        add ok req "octo-spec onboarded" "$REPO/.octospec present (pin: $PIN)"
      else
        add fail req "octo-spec onboarded" "$REPO/.octospec present but no manifest pin (inherits/version/pin) found — invalid onboarding; fix the manifest or re-run onboarding (core §D)"
      fi
    else
      add fail req "octo-spec onboarded" "$REPO has no .octospec/ — NOT onboarded; run onboarding (core §D) before octo-code can run against it"
    fi
  fi
fi

# ---- output ----
if [ "$JSON" = "1" ]; then
  printf '{"ready":%s,"checks":[' "$([ "$FAIL" = "0" ] && echo true || echo false)"
  first=1
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r st rq nm dt <<EOF
$r
EOF
    [ $first = 1 ] || printf ','
    first=0
    if have jq; then
      jq -cn --arg status "$st" --arg required "$rq" --arg name "$nm" --arg detail "$dt" \
        '{status:$status, required:$required, name:$name, detail:$detail}'
    else
      esc_nm=$(printf '%s' "$nm" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r//g')
      esc_dt=$(printf '%s' "$dt" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r//g')
      printf '{"status":"%s","required":"%s","name":"%s","detail":"%s"}' "$st" "$rq" "$esc_nm" "$esc_dt"
    fi
  done
  printf ']}\n'
else
  echo "octo-code doctor"
  echo "================"
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r st rq nm dt <<EOF
$r
EOF
    case "$st" in
      ok)   icon="✅" ;;
      warn) icon="⚠️ " ;;
      fail) icon="❌" ;;
      *)    icon="? " ;;
    esac
    tag=""; [ "$rq" = "opt" ] && tag=" (optional)"
    printf '%s %s%s — %s\n' "$icon" "$nm" "$tag" "$dt"
  done
  echo "----------------"
  if [ "$FAIL" = "0" ]; then
    echo "READY ✅  All required checks pass — octo-code can run."
  else
    echo "NOT READY ❌  Fix the ❌ items above (they are host setup, not chat-installable), then re-run the doctor."
  fi
fi

exit "$FAIL"
