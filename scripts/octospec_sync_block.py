#!/usr/bin/env python3
"""octospec_sync_block.py — sync the shared agent-instruction block into one
agent-instruction file, between

    <!-- octospec:begin -->
    ... managed content ...
    <!-- octospec:end -->

markers, preserving everything outside the markers.

Safety contract (the whole point of this tool):
  * Marker detection is WHOLE-LINE and FENCE-AWARE: a line is only a marker if,
    after stripping whitespace, it equals the marker string AND it is not inside
    a ``` fenced code block. This prevents prose/examples that merely mention the
    marker string from being mistaken for the managed region.
  * Exactly-one-marker or out-of-order markers are a hard ERROR (we refuse and
    leave the file untouched) rather than appending a second block — appending
    would compound into content loss on the next run.
  * Writes are ATOMIC (temp file + os.replace), so an interruption never leaves
    a truncated file.
  * Line endings are preserved (LF vs CRLF) so we don't splice mixed endings.

Usage:
    octospec_sync_block.py <target-file> <block-source> [--create]

Exit codes: 0 ok (with one of created/updated/unchanged printed),
            2 = refused (malformed markers) or usage error.
"""
import io
import os
import sys

BEGIN = "<!-- octospec:begin -->"
END = "<!-- octospec:end -->"
FENCE_PREFIXES = ("```", "~~~")


def find_marker_lines(lines):
    """Return (begin_idx, end_idx) of whole-line, non-fenced markers.

    Each is the line index or None. Raises ValueError on malformed marker state
    (a marker appearing more than once, or only one of the pair present, or end
    before begin)."""
    in_fence = False
    fence_marker = None
    begins = []
    ends = []
    for i, raw in enumerate(lines):
        stripped = raw.strip()
        matched_fence = next((p for p in FENCE_PREFIXES if stripped.startswith(p)), None)
        if matched_fence is not None:
            # Only the same fence char closes the fence (``` not closed by ~~~).
            if not in_fence:
                in_fence = True
                fence_marker = matched_fence
            elif matched_fence == fence_marker:
                in_fence = False
                fence_marker = None
            continue
        if in_fence:
            continue
        if stripped == BEGIN:
            begins.append(i)
        elif stripped == END:
            ends.append(i)

    if not begins and not ends:
        return (None, None)
    if len(begins) > 1 or len(ends) > 1:
        raise ValueError(
            "multiple octospec markers found (%d begin, %d end); refusing to "
            "edit to avoid content loss" % (len(begins), len(ends))
        )
    if len(begins) != 1 or len(ends) != 1:
        raise ValueError(
            "unbalanced octospec markers (%d begin, %d end); refusing to edit "
            "to avoid content loss" % (len(begins), len(ends))
        )
    if ends[0] < begins[0]:
        raise ValueError(
            "octospec end marker precedes begin marker; refusing to edit"
        )
    return (begins[0], ends[0])


def detect_newline(text):
    """Return the dominant line ending of text ('\\r\\n' or '\\n')."""
    if "\r\n" in text:
        return "\r\n"
    return "\n"


def sync(target_path, block_src_path, create=False):
    """Sync block into target. Returns one of created/updated/unchanged.
    Raises ValueError on malformed markers."""
    with io.open(block_src_path, encoding="utf-8") as f:
        block = f.read().replace("\r\n", "\n").replace("\r", "\n").strip("\n")

    try:
        with io.open(target_path, encoding="utf-8", newline="") as f:
            cur = f.read()
        existed = True
    except FileNotFoundError:
        if not create:
            return "skipped"
        cur = ""
        existed = False

    nl = detect_newline(cur) if existed and cur else "\n"
    # Work in LF internally; re-apply nl on write.
    cur_lf = cur.replace("\r\n", "\n").replace("\r", "\n")
    lines = cur_lf.split("\n")

    begin_idx, end_idx = find_marker_lines(lines)
    block_lines = block.split("\n")

    if begin_idx is not None and end_idx is not None:
        new_lines = lines[:begin_idx] + block_lines + lines[end_idx + 1:]
    else:
        # No markers: append the block (with a blank-line separator if needed).
        if cur_lf == "":
            new_lines = block_lines
        else:
            trimmed = cur_lf.rstrip("\n")
            new_lines = trimmed.split("\n") + [""] + block_lines

    new_lf = "\n".join(new_lines)
    # Preserve a trailing newline for non-empty files.
    if not new_lf.endswith("\n"):
        new_lf += "\n"

    new_out = new_lf.replace("\n", nl) if nl != "\n" else new_lf

    if existed and new_out == cur:
        return "unchanged"

    # Atomic write: temp file in the same dir + os.replace.
    target_dir = os.path.dirname(os.path.abspath(target_path)) or "."
    tmp = os.path.join(target_dir, ".%s.octospec.tmp" % os.path.basename(target_path))
    with io.open(tmp, "w", encoding="utf-8", newline="") as f:
        f.write(new_out)
    os.replace(tmp, target_path)
    return "created" if not existed else "updated"


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    create = "--create" in argv[1:]
    if len(args) != 2:
        sys.stderr.write(
            "usage: octospec_sync_block.py <target-file> <block-source> [--create]\n"
        )
        return 2
    target, block_src = args
    try:
        result = sync(target, block_src, create=create)
    except ValueError as e:
        sys.stderr.write("octospec: REFUSED %s: %s\n" % (target, e))
        return 2
    print(result)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
