#!/usr/bin/env python3
"""Heuristic static scan of Kotlin/Compose sources for accessibility problems. Reads code; needs no device.

Usage: scan_compose.py <dir-or-file> [--json] [--only RULE,RULE]

Rules (each names the person it hurts):
  clickable-no-role     .clickable without role/onClickLabel and no semantics nearby          blind   warning
  small-target          clickable/IconButton sized below 48.dp                                 motor   error
  null-desc-clickable   contentDescription = null on an Image/Icon inside something clickable blind   error
  null-desc             contentDescription = null elsewhere: decorative, or a missing label?   blind   info
  gesture-only          pointerInput/detectTapGestures/swipe/drag with no semantics actions    motor   warning
  fixed-text-size       text sized in dp (does not follow the user's font scale)               lowvision error
  small-text            fontSize below 12.sp                                                   lowvision warning
  literal-color         Color(0x…) in a composable file: check contrast with contrast-check    lowvision info

It is a window-based regex scan: it misses what is built elsewhere and flags what is fine. Treat each hit as
"look here", then confirm on the device (a11y-audit, talkback-speak). A clean scan is not a pass.
"""
import json, re, sys, pathlib

WINDOW_BEFORE, WINDOW_AFTER = 3, 9
CLICK = re.compile(r"\.clickable\b|\.combinedClickable\b|\.toggleable\b|IconButton\(|\.selectable\b")
SIZE = re.compile(r"\.(?:size|width|height|requiredSize|defaultMinSize\([^)]*minWidth =|minimumInteractiveComponentSize)\s*\(?\s*(\d+(?:\.\d+)?)\.dp")
SEMANTICS = re.compile(r"semantics|role\s*=|onClickLabel|contentDescription\s*=\s*[^n]|stateDescription|customActions|clearAndSetSemantics|mergeDescendants")
GESTURE = re.compile(r"detectTapGestures|detectDragGestures|detectHorizontalDragGestures|detectVerticalDragGestures|SwipeToDismiss|swipeable|anchoredDraggable|\.draggable\(")
FIXED_TEXT = re.compile(r"fontSize\s*=\s*(\d+(?:\.\d+)?)\.dp")
SMALL_TEXT = re.compile(r"fontSize\s*=\s*(\d+(?:\.\d+)?)\.sp")
NULL_DESC = re.compile(r"contentDescription\s*=\s*null")
LITERAL = re.compile(r"Color\(\s*0x[0-9A-Fa-f]{6,8}\s*\)")


def scan_file(path):
    out = []
    lines = path.read_text(errors="ignore").splitlines()
    is_theme = bool(re.search(r"(Color|Theme)\.kt$|/theme/", str(path)))

    def add(rule, person, sev, i, msg):
        out.append({"rule": rule, "person": person, "severity": sev, "file": str(path), "line": i + 1, "code": lines[i].strip()[:110], "why": msg})

    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith(("//", "*", "/*")):
            continue
        near = "\n".join(lines[max(0, i - WINDOW_BEFORE): i + WINDOW_AFTER])
        before = "\n".join(lines[max(0, i - 6): i + 1])
        if CLICK.search(line):
            if not SEMANTICS.search(near):
                add("clickable-no-role", "blind", "warning", i, "clickable without role, onClickLabel or semantics: TalkBack says only 'double tap to activate'")
            # the size must sit on this call or its own modifier chain (next two lines), and not belong to a nested Icon/Image
            chain = "\n".join(lines[i: i + 3])
            m = SIZE.search(chain)
            if m and not re.search(r"\b(Icon|Image|AsyncImage)\(", chain.split(m.group(0))[0].splitlines()[-1] if m.group(0) in chain else "") and float(m.group(1)) < 48:
                add("small-target", "motor", "error", i, f"{m.group(1)}.dp is below the 48.dp minimum touch target")
        if NULL_DESC.search(line):
            if CLICK.search(before):
                add("null-desc-clickable", "blind", "error", i, "no label on an element the user can activate")
            else:
                add("null-desc", "blind", "info", i, "fine if decorative; a missing label if the image carries information")
        if GESTURE.search(line) and not re.search(r"customActions|semantics|onClick", near):
            add("gesture-only", "motor", "warning", i, "gesture with no accessible alternative (button, custom action)")
        m = FIXED_TEXT.search(line)
        if m:
            add("fixed-text-size", "lowvision", "error", i, "text size in dp ignores the user's font scale: use sp")
        m = SMALL_TEXT.search(line)
        if m and float(m.group(1)) < 12:
            add("small-text", "lowvision", "warning", i, f"{m.group(1)}.sp is below 12.sp")
        if not is_theme and LITERAL.search(line):
            add("literal-color", "lowvision", "info", i, "hard-coded colour: check contrast in light, dark and on images")
    return out


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__); return 2
    root = pathlib.Path(argv[0])
    files = [root] if root.is_file() else sorted(p for p in root.rglob("*.kt") if "/build/" not in str(p) and "Test" not in p.name and "/test" not in str(p).lower())
    only = set(argv[argv.index("--only") + 1].split(",")) if "--only" in argv else None
    findings = [f for p in files for f in scan_file(p) if not only or f["rule"] in only]
    if "--json" in argv:
        print(json.dumps(findings, indent=2, ensure_ascii=False)); return 0
    order = {"error": 0, "warning": 1, "info": 2}
    for f in sorted(findings, key=lambda f: (order[f["severity"]], f["rule"], f["file"], f["line"])):
        print(f'{f["severity"]:7} {f["rule"]:19} {f["person"]:9} {f["file"]}:{f["line"]}  {f["code"]}')
    counts = {s: sum(f["severity"] == s for f in findings) for s in order}
    print(f"\n{len(files)} file(s): {counts['error']} error, {counts['warning']} warning, {counts['info']} info. A clean scan is not a pass.")
    return 1 if counts["error"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
