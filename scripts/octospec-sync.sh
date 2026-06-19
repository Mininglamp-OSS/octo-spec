#!/usr/bin/env bash
# octospec-sync — vendor the pinned global ("constitution") rules into a
# git-ignored local cache, then sync the shared agent-instruction block into
# every agent-instruction file present in the repo.
#
# Inheritance model: vendor snapshot + version pin (NOT git submodule).
#   - manifest.yaml declares `inherits: octo-spec@<semver>`
#   - this script fetches that version's global/ into .octospec/_global/
#   - _global/ is git-ignored; upgrading = bump the pin + re-run this script.
#
# Agent-instruction sync: one source of truth (the octo-spec checkout's
# templates/octospec-init/AGENT-BLOCK.md) is written, idempotently, between
#   <!-- octospec:begin --> ... <!-- octospec:end -->
# markers into each agent-instruction file that exists in the repo
# (CLAUDE.md, AGENTS.md, GEMINI.md, ...). Content outside the markers is left
# untouched. If a file has no markers yet, the block is appended.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
OCTOSPEC_DIR="$REPO_ROOT/.octospec"
MANIFEST="$OCTOSPEC_DIR/manifest.yaml"
GLOBAL_CACHE="$OCTOSPEC_DIR/_global"

[ -f "$MANIFEST" ] || { echo "no $MANIFEST"; exit 1; }

PIN="$(grep -E '^inherits:' "$MANIFEST" | sed -E 's/^inherits:[[:space:]]*//')"
echo "octospec: inherits = $PIN"

# GLOBAL_SRC: path to a checkout of octo-spec at the pinned version.
# Override via env: GLOBAL_SRC=/path/to/octo-spec ./octospec-sync.sh
GLOBAL_SRC="${GLOBAL_SRC:-}"
if [ -z "$GLOBAL_SRC" ]; then
  echo "set GLOBAL_SRC to a checkout of octo-spec (at version: $PIN)" >&2
  exit 1
fi

# 1) Vendor the global rules.
rm -rf "$GLOBAL_CACHE"
mkdir -p "$GLOBAL_CACHE"
cp -r "$GLOBAL_SRC/global/." "$GLOBAL_CACHE/"
echo "octospec: synced global rules -> $GLOBAL_CACHE"

# Ensure _global/ is git-ignored.
GITIGNORE="$OCTOSPEC_DIR/.gitignore"
grep -qxF "_global/" "$GITIGNORE" 2>/dev/null || echo "_global/" >> "$GITIGNORE"

# 2) Sync the shared agent-instruction block into every instruction file present.
BLOCK_SRC="$GLOBAL_SRC/templates/octospec-init/AGENT-BLOCK.md"
if [ ! -f "$BLOCK_SRC" ]; then
  echo "octospec: WARNING no AGENT-BLOCK.md at $BLOCK_SRC; skipping instruction sync" >&2
else
  # Agent-instruction files we know about. We only touch files that already
  # exist, except CLAUDE.md/AGENTS.md which we create if missing (the two
  # broadly-supported defaults).
  ALWAYS="CLAUDE.md AGENTS.md"
  OPTIONAL="GEMINI.md QWEN.md"

  sync_block() {
    local target="$1"
    local path="$REPO_ROOT/$target"
    python3 - "$path" "$BLOCK_SRC" <<'PY'
import sys, io
path, block_src = sys.argv[1], sys.argv[2]
BEGIN = "<!-- octospec:begin -->"
END = "<!-- octospec:end -->"
with io.open(block_src, encoding="utf-8") as f:
    block = f.read().strip("\n") + "\n"
try:
    with io.open(path, encoding="utf-8") as f:
        cur = f.read()
except FileNotFoundError:
    cur = ""
b, e = cur.find(BEGIN), cur.find(END)
if b != -1 and e != -1 and e > b:
    e_end = e + len(END)
    new = cur[:b] + block.rstrip("\n") + cur[e_end:]
else:
    sep = "" if cur == "" or cur.endswith("\n\n") else ("\n" if cur.endswith("\n") else "\n\n")
    new = cur + sep + block
if new != cur:
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(new)
    print("updated" if cur else "created")
else:
    print("unchanged")
PY
  }

  for t in $ALWAYS; do
    res="$(sync_block "$t")"
    echo "octospec: $t -> $res"
  done
  for t in $OPTIONAL; do
    [ -f "$REPO_ROOT/$t" ] || continue
    res="$(sync_block "$t")"
    echo "octospec: $t -> $res"
  done
fi

echo "octospec: done."
