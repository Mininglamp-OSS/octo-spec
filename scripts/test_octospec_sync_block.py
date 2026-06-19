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

# 2c. P1 (CommonMark CM-119/120): a 4-backtick fence is NOT closed by an inner
# 3-backtick line. A doc that wraps the markers in a ```` block (so it can SHOW
# an inner ``` example) must have all of its inner content preserved — the old
# prefix-only fence detection mistook the inner ``` for a close, exited the
# fence, and then replaced everything between the (now-"real") begin/end inside
# the example, silently eating user content.
nested_fence = (
    "# Docs\n\n"
    "## How markers look\n\n"
    "````markdown\n"               # 4-backtick fence OPEN
    "```\n"                         # inner 3-backtick — must NOT close the fence
    + BEGIN + "\n"
    "USER PRECIOUS EXAMPLE CONTENT\n"
    + END + "\n"
    "```\n"                         # inner 3-backtick
    "````\n"                        # 4-backtick fence CLOSE
    "\nAFTER TEXT\n"
)
res, final, _ = run(nested_fence)
check("4-backtick fence not closed by inner 3-backtick (no data loss)",
      "USER PRECIOUS EXAMPLE CONTENT" in final and "AFTER TEXT" in final,
      repr(final))

# 2d. Same nested-fence danger when a REAL managed block exists ABOVE the doc
# example: the real block updates to v2, the example inside the ```` fence is
# untouched, and the trailing content survives. This is the truest reproduction
# of the reported bug (md5 changes because the real block updated, but the
# fenced example + surrounding content are byte-preserved).
real_plus_example = (
    "# CLAUDE\n\npre\n\n"
    + BEGIN + "\nOLD MANAGED\n" + END + "\n\n"
    "## How markers look\n\n"
    "````markdown\n"               # 4-backtick fence OPEN
    "```\n"
    + BEGIN + "\n"
    "INNER EXAMPLE KEEP ME\n"
    + END + "\n"
    "```\n"
    "````\n"
    "\npost\n"
)
res, final, _ = run(real_plus_example)
check("real block updates while nested 4-backtick example is preserved",
      res == "updated" and "MANAGED v2" in final and "OLD MANAGED" not in final
      and "INNER EXAMPLE KEEP ME" in final and final.count(BEGIN) == 2
      and "pre" in final and "post" in final,
      repr(final))

# 2e. Tilde length asymmetry (CommonMark): a ~~~~ (4) fence is NOT closed by an
# inner ~~~ (3) line, mirroring the backtick case.
nested_tilde = (
    "# Docs\n\n"
    "~~~~\n"                        # 4-tilde fence OPEN
    "~~~\n"                         # inner 3-tilde — must NOT close it
    + BEGIN + "\n"
    "TILDE PRECIOUS CONTENT\n"
    + END + "\n"
    "~~~\n"
    "~~~~\n"                        # 4-tilde fence CLOSE
    "\nAFTER\n"
)
res, final, _ = run(nested_tilde)
check("4-tilde fence not closed by inner 3-tilde (no data loss)",
      "TILDE PRECIOUS CONTENT" in final and "AFTER" in final,
      repr(final))

# 2f. Info string on a fence opener (```` ```markdown ````) must still open a
# fence, and a backtick info string containing a backtick is NOT a fence (so a
# stray inline-code-looking line cannot accidentally open/close a fence).
info_fence = (
    "# Docs\n\n"
    "```python\n"                  # opener with info string
    + BEGIN + "\nexample with info string\n" + END + "\n"
    "```\n\n"
    "TEAM RULE KEEP ME\n\n"
    + BEGIN + "\nOLD\n" + END + "\n"
)
res, final, _ = run(info_fence)
check("fence opener with info string still hides inner markers",
      "example with info string" in final and "MANAGED v2" in final
      and "TEAM RULE KEEP ME" in final,
      repr(final))

# 2g. Indentation: a fence may be indented up to 3 spaces; 4+ spaces is an
# indented code block, not a fence. A marker that is only "hidden" behind a
# 4-space-indented pseudo-fence is therefore NOT in a fence — but it also is not
# a whole-line marker once indented? It IS (we strip), so guard the real case:
# a 3-space-indented fence still hides its markers.
indented_fence = (
    "# Docs\n\n"
    "   ```\n"                      # 3-space indent: valid fence
    + BEGIN + "\nindented example\n" + END + "\n"
    "   ```\n\n"
    "TEAM RULE KEEP ME\n\n"
    + BEGIN + "\nOLD\n" + END + "\n"
)
res, final, _ = run(indented_fence)
check("3-space-indented fence hides inner markers",
      "indented example" in final and "MANAGED v2" in final
      and "TEAM RULE KEEP ME" in final,
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

# 12. CLI `--` end-of-options: a target path that starts with '--' is accepted
# after a lone `--` separator (argv boundary handling), and `--create` before
# `--` is still honored.
d = tempfile.mkdtemp()
blk = os.path.join(d, "BLOCK.md")
with io.open(blk, "w", encoding="utf-8", newline="") as f:
    f.write(BLOCK_BODY)
weird = os.path.join(d, "--weird.md")  # basename starts with --
rc = m.main(["prog", "--create", "--", weird, blk])
with io.open(weird, encoding="utf-8", newline="") as f:
    weird_out = f.read()
check("CLI accepts -- separator + --create for a --prefixed path",
      rc == 0 and "MANAGED v2" in weird_out, "rc=%r out=%r" % (rc, weird_out))

# 13. CLI rejects an unknown --option (no silent arg drop).
rc = m.main(["prog", "--bogus", "a", "b"])
check("CLI rejects unknown option", rc == 2, "rc=%r" % rc)

print("\n%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
