#!/usr/bin/env bash
# octospec-sync — vendor the pinned global ("constitution") rules into a
# git-ignored local cache, then sync the shared agent-instruction block into
# the agent-instruction files present in the repo.
#
# Inheritance model: vendor snapshot + version pin (NOT git submodule).
#   - manifest.yaml declares `inherits: octo-spec@<semver>`
#   - this script fetches that version's global/ into .octospec/_global/
#   - _global/ is git-ignored; upgrading = bump the pin + re-run this script.
#
# Agent-instruction sync: one source of truth (the octo-spec checkout's
# templates/octospec-init/AGENT-BLOCK.md) is written, idempotently and
# atomically, between `<!-- octospec:begin -->` / `<!-- octospec:end -->`
# markers into each agent-instruction file that exists (CLAUDE.md, AGENTS.md,
# GEMINI.md, QWEN.md). Marker detection is whole-line and fence-aware, and a
# malformed marker state makes the sync REFUSE that file rather than risk
# clobbering hand-written content (see scripts/octospec_sync_block.py).
#
# Bootstrap: CLAUDE.md and AGENTS.md are the two default entry points — whichever
# is missing is created so BOTH Claude Code (CLAUDE.md) and Codex (AGENTS.md) get
# the block, even when the repo started with only one of them (the common case for
# an existing Claude Code repo that has only CLAUDE.md). GEMINI.md / QWEN.md are
# only updated when they already exist; we never force-create those.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
OCTOSPEC_DIR="$REPO_ROOT/.octospec"
MANIFEST="$OCTOSPEC_DIR/manifest.yaml"
GLOBAL_CACHE="$OCTOSPEC_DIR/_global"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -f "$MANIFEST" ] || { echo "no $MANIFEST"; exit 1; }

PIN="$(grep -E '^inherits:' "$MANIFEST" | sed -E 's/^inherits:[[:space:]]*//')"
echo "octospec: inherits = $PIN"

# GLOBAL_SRC: path to a checkout of octo-spec at the pinned version.
# Override via env: GLOBAL_SRC=/path/to/octo-spec ./octospec-sync.sh
GLOBAL_SRC="${GLOBAL_SRC:-}"
if [ -z "$GLOBAL_SRC" ]; then
  echo "set GLOBAL_SRC to a checkout of octo-spec (at version: $PIN)" >&2
  echo "  e.g. GLOBAL_SRC=/path/to/octo-spec ./.octospec/scripts/octospec-sync.sh" >&2
  exit 1
fi

# --- Version assertion: manifest pin must match the GLOBAL_SRC checkout. (YUJ-5344)
# Re-sync drift guard: bumping the pin without checking out the matching tag would
# silently vendor the wrong version's global rules. fail-fast like the GLOBAL_SRC
# unset path above. Escape hatch for deliberate cross-version debugging only.
if [ "${OCTOSPEC_SKIP_VERSION_CHECK:-0}" != "1" ]; then
  # Version = part after '@', tolerating a trailing inline comment / whitespace.
  PIN_VER="$(printf '%s' "${PIN##*@}" | sed -E 's/[[:space:]]*#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
  SRC_VERSION_FILE="$GLOBAL_SRC/VERSION"
  if [ ! -f "$SRC_VERSION_FILE" ]; then
    echo "octospec: cannot verify version — no VERSION file at $SRC_VERSION_FILE" >&2
    echo "octospec: 无法校验版本 — $SRC_VERSION_FILE 不存在，GLOBAL_SRC 不像 octo-spec checkout，已中止。" >&2
    echo "  (set OCTOSPEC_SKIP_VERSION_CHECK=1 to bypass — debug only)" >&2
    exit 1
  fi
  SRC_VER="$(tr -d '[:space:]' < "$SRC_VERSION_FILE")"
  if [ -z "$SRC_VER" ]; then
    echo "octospec: cannot verify version — $SRC_VERSION_FILE is empty; aborting." >&2
    echo "octospec: 无法校验版本 — $SRC_VERSION_FILE 为空，已中止。" >&2
    echo "  (set OCTOSPEC_SKIP_VERSION_CHECK=1 to bypass — debug only)" >&2
    exit 1
  fi
  if [ "$PIN_VER" != "$SRC_VER" ]; then
    echo "octospec: VERSION MISMATCH — manifest pins octo-spec@$PIN_VER but GLOBAL_SRC checkout is $SRC_VER" >&2
    echo "octospec: 版本不一致 — manifest 钉 octo-spec@$PIN_VER，但 GLOBAL_SRC checkout 是 $SRC_VER" >&2
    echo "  Fix one of / 二选一修复:" >&2
    echo "    - check out octo-spec at the pinned tag:  git -C \"\$GLOBAL_SRC\" checkout v$PIN_VER" >&2
    echo "    - or change the manifest pin back to:     inherits: octo-spec@$SRC_VER" >&2
    echo "  (set OCTOSPEC_SKIP_VERSION_CHECK=1 to bypass — debug only)" >&2
    exit 1
  fi
  echo "octospec: version OK (pin $PIN_VER == checkout $SRC_VER)"
fi

# 1) Vendor the global rules.
rm -rf "$GLOBAL_CACHE"
mkdir -p "$GLOBAL_CACHE"
cp -r "$GLOBAL_SRC/global/." "$GLOBAL_CACHE/"
echo "octospec: synced global rules -> $GLOBAL_CACHE"

# Ensure _global/ is git-ignored (with a trailing-newline guard so we never glue
# onto a previous line that lacks a newline).
GITIGNORE="$OCTOSPEC_DIR/.gitignore"
if ! grep -qxF "_global/" "$GITIGNORE" 2>/dev/null; then
  if [ -s "$GITIGNORE" ] && [ -n "$(tail -c1 "$GITIGNORE")" ]; then
    printf '\n' >> "$GITIGNORE"
  fi
  printf '_global/\n' >> "$GITIGNORE"
fi

# 2) Sync the shared agent-instruction block into the instruction files present.
BLOCK_SRC="$GLOBAL_SRC/templates/octospec-init/AGENT-BLOCK.md"
SYNC_PY="$HERE/octospec_sync_block.py"
if [ ! -f "$BLOCK_SRC" ]; then
  echo "octospec: WARNING no AGENT-BLOCK.md at $BLOCK_SRC; skipping instruction sync" >&2
elif [ ! -f "$SYNC_PY" ]; then
  echo "octospec: WARNING no octospec_sync_block.py at $SYNC_PY; skipping instruction sync" >&2
else
  # Two default entry points (CLAUDE.md for Claude Code, AGENTS.md for Codex)
  # are created if missing; the rest are only synced when already present.
  DEFAULTS="CLAUDE.md AGENTS.md"
  OPTIONAL="GEMINI.md QWEN.md"
  rc=0
  # Per-file isolation: one refused/failed file must not abort the rest, but it
  # MUST be reflected in the final exit code.
  for t in $DEFAULTS; do
    if [ -f "$REPO_ROOT/$t" ]; then
      if res="$(python3 "$SYNC_PY" "$REPO_ROOT/$t" "$BLOCK_SRC" 2>&1)"; then
        echo "octospec: $t -> $res"
      else
        echo "octospec: $t -> FAILED: $res" >&2
        rc=1
      fi
    else
      echo "octospec: $t missing; bootstrapping"
      if res="$(python3 "$SYNC_PY" "$REPO_ROOT/$t" "$BLOCK_SRC" --create 2>&1)"; then
        echo "octospec: $t -> $res"
      else
        echo "octospec: $t -> FAILED: $res" >&2
        rc=1
      fi
    fi
  done
  for t in $OPTIONAL; do
    [ -f "$REPO_ROOT/$t" ] || continue
    if res="$(python3 "$SYNC_PY" "$REPO_ROOT/$t" "$BLOCK_SRC" 2>&1)"; then
      echo "octospec: $t -> $res"
    else
      echo "octospec: $t -> FAILED: $res" >&2
      rc=1
    fi
  done
  if [ "$rc" -ne 0 ]; then
    echo "octospec: one or more agent files failed to sync" >&2
    exit "$rc"
  fi
fi

# Copy one missing file without following destination symlinks. Repository
# checkouts are untrusted input: a symlinked .claude/.github component must not
# redirect sync writes outside the checkout. Exit 0 = installed, 3 = exists.
safe_copy_missing() {
  python3 - "$1" "$2" "$3" <<'PY'
import os
import secrets
import shutil
import stat
import sys

src, dest, root = map(os.path.abspath, sys.argv[1:])
parent_fd = None
tmp_name = None
try:
    if os.path.commonpath((dest, root)) != root:
        raise ValueError(f"destination escapes root: {dest}")
    components = os.path.relpath(dest, root).split(os.sep)
    if any(part in ("", ".", "..") for part in components):
        raise ValueError(f"invalid destination path: {dest}")
    flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_NOFOLLOW", 0)
    parent_fd = os.open(root, flags)
    for component in components[:-1]:
        try:
            next_fd = os.open(component, flags, dir_fd=parent_fd)
        except FileNotFoundError:
            try:
                os.mkdir(component, dir_fd=parent_fd)
            except FileExistsError:
                pass
            next_fd = os.open(component, flags, dir_fd=parent_fd)
        os.close(parent_fd)
        parent_fd = next_fd
    leaf = components[-1]
    try:
        existing = os.stat(leaf, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        existing = None
    if existing is not None:
        if stat.S_ISLNK(existing.st_mode):
            raise ValueError(f"destination is a symlink: {dest}")
        sys.exit(3)
    tmp_name = f".octospec-copy-{secrets.token_hex(8)}"
    fd = os.open(tmp_name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=parent_fd)
    with os.fdopen(fd, "wb") as out, open(src, "rb") as inp:
        shutil.copyfileobj(inp, out)
    os.chmod(tmp_name, stat.S_IMODE(os.stat(src).st_mode), dir_fd=parent_fd)
    os.link(
        tmp_name,
        leaf,
        src_dir_fd=parent_fd,
        dst_dir_fd=parent_fd,
        follow_symlinks=False,
    )  # atomic create relative to the verified parent FD
except (OSError, ValueError) as exc:
    print(f"octospec: refused unsafe copy to {dest}: {exc}", file=sys.stderr)
    sys.exit(1)
finally:
    if parent_fd is not None:
        if tmp_name is not None:
            try:
                os.unlink(tmp_name, dir_fd=parent_fd)
            except FileNotFoundError:
                pass
        os.close(parent_fd)
PY
}

# 3) Install newly shipped skills into the repo-local source tree. Older
# onboarded repositories do not contain skills added by a newer octo-spec pin;
# copying only missing files from GLOBAL_SRC closes that upgrade gap without
# overwriting any repository-owned customization.
CANONICAL_SKILLS="$GLOBAL_SRC/templates/octospec-init/.claude/skills"
LOCAL_SKILLS="$OCTOSPEC_DIR/.claude/skills"
if [ -d "$CANONICAL_SKILLS" ]; then
  installed_skills=0
  kept_skills=0
  while IFS= read -r src; do
    rel="${src#"$CANONICAL_SKILLS"/}"
    dest="$LOCAL_SKILLS/$rel"
    set +e
    safe_copy_missing "$src" "$dest" "$OCTOSPEC_DIR"
    copy_rc=$?
    set -e
    if [ "$copy_rc" -eq 0 ]; then
      installed_skills=$((installed_skills + 1))
    elif [ "$copy_rc" -eq 3 ]; then
      kept_skills=$((kept_skills + 1))
    else
      exit "$copy_rc"
    fi
  done <<EOF
$(find "$CANONICAL_SKILLS" -type f)
EOF
  echo "octospec: canonical skills -> installed $installed_skills, kept $kept_skills existing"
fi

# 4) Materialize repo-root scaffolding that tools only discover at the root.
# The template tree carries .octospec/.claude/ (slash commands + skills) and
# .octospec/.github/PULL_REQUEST_TEMPLATE.md, but Claude Code only discovers
# slash commands/skills under the REPO ROOT .claude/, and GitHub only applies a
# PR template at the REPO ROOT .github/. So copy these out of .octospec/ to the
# root — install-if-missing only: an existing destination file is left untouched
# so hand-written customizations are never clobbered. This makes the whole step
# idempotent (a second run reports everything already present).
#
# install_missing SRC_DIR DEST_DIR LABEL — copy every file under SRC_DIR into
# DEST_DIR (mirroring subpaths), skipping any destination file that exists.
install_missing() {
  src_dir="$1"; dest_dir="$2"; label="$3"
  [ -d "$src_dir" ] || return 0
  installed=0; skipped=0
  while IFS= read -r src; do
    rel="${src#"$src_dir"/}"
    dest="$dest_dir/$rel"
    set +e
    safe_copy_missing "$src" "$dest" "$REPO_ROOT"
    copy_rc=$?
    set -e
    if [ "$copy_rc" -eq 0 ]; then
      installed=$((installed + 1))
    elif [ "$copy_rc" -eq 3 ]; then
      skipped=$((skipped + 1))
    else
      return "$copy_rc"
    fi
  done <<EOF
$(find "$src_dir" -type f)
EOF
  echo "octospec: $label -> installed $installed, kept $skipped existing"
}

install_missing "$OCTOSPEC_DIR/.claude" "$REPO_ROOT/.claude" ".claude (slash commands + skills)"

PRT_SRC="$OCTOSPEC_DIR/.github/PULL_REQUEST_TEMPLATE.md"
PRT_DEST="$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md"
if [ -f "$PRT_SRC" ]; then
  set +e
  safe_copy_missing "$PRT_SRC" "$PRT_DEST" "$REPO_ROOT"
  copy_rc=$?
  set -e
  if [ "$copy_rc" -eq 0 ]; then
    echo "octospec: .github/PULL_REQUEST_TEMPLATE.md -> installed"
  elif [ "$copy_rc" -eq 3 ]; then
    echo "octospec: .github/PULL_REQUEST_TEMPLATE.md -> kept existing"
  else
    exit "$copy_rc"
  fi
fi

echo "octospec: done."
