#!/usr/bin/env bash
# octospec-sync — pull the pinned global ("constitution") rules into a
# git-ignored local cache, then (re)generate the octospec block in CLAUDE.md.
#
# Inheritance model: vendor snapshot + version pin (NOT git submodule).
#   - manifest.yaml declares `inherits: octo-spec@<semver>`
#   - this script fetches that version's global/ into .octospec/_global/
#   - _global/ is git-ignored; upgrading = bump the pin + re-run this script.
#
# This is a thin reference implementation. Adjust GLOBAL_SRC for how your team
# distributes the global layer (a checked-out octo-spec, a release tarball, etc.).
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
OCTOSPEC_DIR="$REPO_ROOT/.octospec"
MANIFEST="$OCTOSPEC_DIR/manifest.yaml"
GLOBAL_CACHE="$OCTOSPEC_DIR/_global"

[ -f "$MANIFEST" ] || { echo "no $MANIFEST"; exit 1; }

PIN="$(grep -E '^inherits:' "$MANIFEST" | sed -E 's/^inherits:[[:space:]]*//')"
echo "octospec: inherits = $PIN"

# GLOBAL_SRC: path or URL to a checkout of octo-spec at the pinned version.
# Override via env: GLOBAL_SRC=/path/to/octo-spec ./octospec-sync.sh
GLOBAL_SRC="${GLOBAL_SRC:-}"
if [ -z "$GLOBAL_SRC" ]; then
  echo "set GLOBAL_SRC to a checkout of octo-spec (at version: $PIN)" >&2
  exit 1
fi

rm -rf "$GLOBAL_CACHE"
mkdir -p "$GLOBAL_CACHE"
cp -r "$GLOBAL_SRC/global/." "$GLOBAL_CACHE/"
echo "octospec: synced global rules -> $GLOBAL_CACHE"

# Ensure _global/ is git-ignored.
GITIGNORE="$OCTOSPEC_DIR/.gitignore"
grep -qxF "_global/" "$GITIGNORE" 2>/dev/null || echo "_global/" >> "$GITIGNORE"

echo "octospec: done. (regenerate CLAUDE.md octospec block as a follow-up step)"
