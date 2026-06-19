#!/usr/bin/env python3
"""Regression tests for octospec_sync_block.sync().

Covers the failure modes flagged in review of PR #3 (whole-line/fence-aware
marker detection, orphan/duplicate markers, atomic write, CRLF preservation,
content preservation outside markers).

Run:  python3 scripts/test_octospec_sync_block.py
"""
import io
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import octospec_sync_block as m  # noqa: E402

BEGIN = m.BEGIN
END = m.END
BLOCK_BODY = BEGIN + "\nMANAGED v2\n" + END + "\n"

passed = 0
failed = 0


def check(name, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print("ok   - " + name)
    else:
        failed += 1
        print("FAIL - " + name + ("  :: " + detail if detail else ""))


def run(target_text, create=False, block=BLOCK_BODY, exists=True):
    """Write target_text to a temp file (unless exists=False), sync, return
    (result, final_text or exception)."""
    d = tempfile.mkdtemp()
    blk = os.path.join(d, "BLOCK.md")
    with io.open(blk, "w", encoding="utf-8", newline="") as f:
        f.write(block)
    tgt = os.path.join(d, "CLAUDE.md")
    if exists:
        with io.open(tgt, "w", encoding="utf-8", newline="") as f:
            f.write(target_text)
    try:
        res = m.sync(tgt, blk, create=create)
    except ValueError as e:
        return ("REFUSED", str(e), None)
    if res == "skipped":
        return (res, None, None)
    with io.open(tgt, encoding="utf-8", newline="") as f:
        final = f.read()
    return (res, final, None)


# 1. P1: prose mention of marker above real block must NOT be matched.
prose = (
    "# CLAUDE\n\n"
    "This repo manages the region between " + BEGIN + " and the end marker.\n\n"
    "TEAM RULE KEEP ME\n\n"
    + BEGIN + "\nOLD MANAGED\n" + END + "\n\ntrailing\n"
)
res, final, _ = run(prose)
check("prose mention not mistaken for marker (TEAM RULE preserved)",
      "TEAM RULE KEEP ME" in final and "MANAGED v2" in final and "OLD MANAGED" not in final,
      repr(final))

# 2. P1: marker inside a fenced code block must be ignored.
fenced = (
    "# CLAUDE\n\n```\n" + BEGIN + "\nexample in docs\n" + END + "\n```\n\n"
    "TEAM RULE KEEP ME\n\n" + BEGIN + "\nOLD\n" + END + "\n"
)
res, final, _ = run(fenced)
check("fenced example markers ignored (real block updated, example kept)",
      "example in docs" in final and "MANAGED v2" in final and "TEAM RULE KEEP ME" in final,
      repr(final))

# 2b. P1: marker inside a ~~~ fenced block must also be ignored.
fenced2 = (
    "# CLAUDE\n\n~~~\n" + BEGIN + "\nexample\n" + END + "\n~~~\n\n"
    "TEAM RULE KEEP ME\n\n" + BEGIN + "\nOLD\n" + END + "\n"
)
res, final, _ = run(fenced2)
check("~~~ fenced example markers ignored",
      "example" in final and "MANAGED v2" in final and "TEAM RULE KEEP ME" in final,
      repr(final))

# 3. P1: orphan begin (no end) must REFUSE, not append.
orphan = "# CLAUDE\n\n" + BEGIN + "\nrule beta KEEP ME\n"
res, final, _ = run(orphan)
check("orphan begin marker refused (no second block appended)", res == "REFUSED", repr(res))

# 4. duplicate begin markers must REFUSE.
dup = BEGIN + "\nA\n" + END + "\n" + BEGIN + "\nB\n" + END + "\n"
res, final, _ = run(dup)
check("duplicate markers refused", res == "REFUSED", repr(res))

# 5. end-before-begin must REFUSE.
oo = END + "\nx\n" + BEGIN + "\n"
res, final, _ = run(oo)
check("out-of-order markers refused", res == "REFUSED", repr(res))

# 6. clean replace preserves surrounding content.
clean = "# CLAUDE\n\npre\n\n" + BEGIN + "\nOLD\n" + END + "\n\npost\n"
res, final, _ = run(clean)
check("clean replace keeps pre/post", res == "updated" and "pre" in final and "post" in final and "MANAGED v2" in final, repr(final))

# 7. idempotent: syncing an already-synced file => unchanged.
res2, final2, _ = run(final)
check("idempotent re-sync is unchanged", res2 == "unchanged", repr(res2))

# 8. no markers => append, existing content kept.
nomark = "# GEMINI\n\nexisting gemini content\n"
res, final, _ = run(nomark)
check("no-marker file appends, keeps content",
      res == "updated" and "existing gemini content" in final and "MANAGED v2" in final, repr(final))

# 9. missing file + create => created.
res, final, _ = run("", create=True, exists=False)
check("missing file with --create is created", res == "created" and "MANAGED v2" in final, repr(res))

# 10. missing file without create => skipped.
res, final, _ = run("", create=False, exists=False)
check("missing file without create is skipped", res == "skipped", repr(res))

# 11. CRLF file preserved as CRLF.
crlf = ("# CLAUDE\r\n\r\npre\r\n\r\n" + BEGIN + "\r\nOLD\r\n" + END + "\r\n\r\npost\r\n")
res, final, _ = run(crlf)
check("CRLF preserved (no LF splice)",
      res == "updated" and "\r\n" in final and "\n\n" not in final.replace("\r\n", "") and "pre" in final and "post" in final,
      repr(final))

print("\n%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
