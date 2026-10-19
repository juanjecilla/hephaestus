#!/usr/bin/env python3
"""WCAG 2.x contrast for Android colours.

  contrast.py pair <fg> <bg> [--large]      one pair, e.g. pair 0xFF777777 0xFFFFFFFF   (also #RRGGBB, #AARRGGBB)
  contrast.py theme <path-to-.kt-or-dir>    check every on<X>/<X> pair of Material colour schemes found in Kotlin
  contrast.py literals <dir>                list hard-coded Color(0x…) literals outside theme files, with file:line

Thresholds: normal text 4.5:1 (AA), large text (≥ 18 sp, or ≥ 14 sp bold) 3:1, UI components and icons 3:1.
Alpha is composited over the background. Colours that depend on what is behind them (text on a poster image)
cannot be checked statically: the 'literals' mode flags them for a human.
"""
import re, sys, pathlib

HEX = re.compile(r"0x([0-9A-Fa-f]{6,8})")


def parse(s):
    s = s.strip().lstrip("#")
    s = s[2:] if s.lower().startswith("0x") else s
    if len(s) == 6:
        s = "FF" + s
    a, r, g, b = (int(s[i:i + 2], 16) for i in (0, 2, 4, 6))
    return a / 255, r, g, b


def over(fg, bg):
    a, r, g, b = fg
    return tuple(round(c * a + d * (1 - a)) for c, d in zip((r, g, b), bg[1:]))


def lum(rgb):
    f = lambda c: (c / 255 / 12.92) if c / 255 <= 0.03928 else (((c / 255) + 0.055) / 1.055) ** 2.4
    r, g, b = map(f, rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(fg, bg):
    l1, l2 = sorted((lum(over(fg, bg)), lum(bg[1:])), reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)


def verdict(r, large=False):
    return "AA" if r >= (3 if large else 4.5) else "FAIL"


def scheme_pairs(text):
    """Resolve `val X = Color(0x…)` constants, then yield (scheme, role, fg, bg) for Material on<X>/<X> pairs."""
    consts = {m.group(1): m.group(2) for m in re.finditer(r"val\s+(\w+)\s*=\s*Color\(\s*(0x[0-9A-Fa-f]{6,8})\s*\)", text)}
    for sm in re.finditer(r"(light|dark)ColorScheme\s*\((.*?)\n\s*\)", text, re.S):
        vals = {}
        for k, v in re.findall(r"(\w+)\s*=\s*([\w.]+(?:\(\s*0x[0-9A-Fa-f]{6,8}\s*\))?)", sm.group(2)):
            hx = HEX.search(v)
            vals[k] = "0x" + hx.group(1) if hx else consts.get(v.split(".")[-1])
        for k, v in vals.items():
            if k.startswith("on") and len(k) > 2:
                base = k[2].lower() + k[3:]
                if vals.get(base) and v:
                    yield sm.group(1), f"{k} on {base}", v, vals[base]


def cmd_pair(a):
    large = "--large" in a
    pos = [x for x in a if not x.startswith("--")]
    r = ratio(parse(pos[0]), parse(pos[1]))
    print(f"{r:.2f}:1  {verdict(r, large)}{' (large text)' if large else ''}")
    return 0 if verdict(r, large) == "AA" else 1


def cmd_theme(a):
    files = [pathlib.Path(a[0])] if pathlib.Path(a[0]).is_file() else list(pathlib.Path(a[0]).rglob("*.kt"))
    bad = n = 0
    for f in files:
        for scheme, role, fg, bg in scheme_pairs(f.read_text(errors="ignore")):
            r = ratio(parse(fg), parse(bg)); n += 1
            if verdict(r) == "FAIL":
                bad += 1
                print(f"FAIL {r:5.2f}:1  {scheme}  {role}  ({fg} on {bg})  {f}")
    print(f"{n} pair(s) checked, {bad} below 4.5:1")
    return 1 if bad else 0


def cmd_literals(a):
    n = 0
    for f in pathlib.Path(a[0]).rglob("*.kt"):
        if re.search(r"(Color|Theme)\.kt$|/theme/", str(f)):
            continue
        for i, line in enumerate(f.read_text(errors="ignore").splitlines(), 1):
            if "Color(" in line and HEX.search(line) and not line.strip().startswith(("//", "*")):
                n += 1; print(f"{f}:{i}: {line.strip()}")
    print(f"{n} literal(s) outside theme files")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("pair", "theme", "literals"):
        print(__doc__); sys.exit(2)
    sys.exit({"pair": cmd_pair, "theme": cmd_theme, "literals": cmd_literals}[sys.argv[1]](sys.argv[2:]))
