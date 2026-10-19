#!/usr/bin/env python3
"""Audit one UiAutomator dump of an Android screen for accessibility problems.

Usage: tree_audit.py <screen.xml> [--density 420] [--json]

Checks (each finding names the person it hurts: blind, lowvision, cognitive, motor):
  unlabeled        clickable node with no text, no content-desc and no labelled child        blind     error
  small-target     clickable node under 48x48 dp                                             motor     error
  generic-label    label is a placeholder ("button", "image", "icon"...)                      blind     warning
  duplicate-label  several clickable nodes share one label with no way to tell them apart     blind     warning
  image-no-desc    non-clickable image in the tree without a description (decorative or not?) blind     info
  tiny-text        text node shorter than 12 dp tall (≈ text under 12 sp)                      lowvision warning
  clipped          clickable node cut by the screen edge (lazy list item): skipped as a target, reported as info

Limits, on purpose: UiAutomator does not expose headings, roles, state descriptions, custom actions, colours or
traversal order. Those need the source (scan_compose.py) or TalkBack itself. A clean report is not a pass.
"""
import json, re, sys
import xml.etree.ElementTree as ET

GENERIC = {"button", "image", "icon", "img", "imageview", "view", "logo", "click", "tap", "untitled"}
MIN_DP = 48


def bounds(n):
    m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds", ""))
    return tuple(int(x) for x in m.groups()) if m else None


def label(n):
    return (n.get("content-desc") or n.get("text") or "").strip()


def has_labelled_child(n):
    return any(label(c) or has_labelled_child(c) for c in n)


def walk(n, path="", scroll=()):
    """Yield (path, node, bounds of the scrollable ancestors that may clip it)."""
    for i, c in enumerate(n):
        p = f"{path}/{i}"
        yield p, c, scroll
        inner = scroll + ((bounds(c),) if c.get("scrollable") == "true" and bounds(c) else ())
        yield from walk(c, p, inner)


def audit(xml_path, density=420):
    scale = density / 160.0
    root = ET.parse(xml_path).getroot()
    screen = max((bounds(n) for _, n, _ in walk(root) if bounds(n)), key=lambda b: (b[2] - b[0]) * (b[3] - b[1]))
    out, labels = [], {}
    for path, n, scrollers in walk(root):
        b = bounds(n)
        if not b:
            continue
        w, h = (b[2] - b[0]) / scale, (b[3] - b[1]) / scale
        tol = 1.5 / scale  # px rounding: 48 dp at 2.625 px/dp is 126 px, a 125 px node is not a bug
        cls, lab = n.get("class", "").split(".")[-1], label(n)
        clickable = n.get("clickable") == "true"
        where = {"path": path, "class": cls, "bounds": n.get("bounds"), "label": lab, "size_dp": [round(w), round(h)]}
        edges = [screen] + list(scrollers)
        clipped = any(b[0] <= e[0] or b[1] <= e[1] or b[2] >= e[2] or b[3] >= e[3] for e in edges)
        if clickable and clipped and (w < MIN_DP - tol or h < MIN_DP - tol):
            # lazy lists compose only what is on screen: a sliver at the edge has no label yet, and is not a real target
            out.append({"rule": "clipped", "person": "motor", "severity": "info", **where})
        elif clickable:
            if not lab and not has_labelled_child(n):
                out.append({"rule": "unlabeled", "person": "blind", "severity": "error", **where})
            if w < MIN_DP - tol or h < MIN_DP - tol:
                out.append({"rule": "small-target", "person": "motor", "severity": "error", **where})
            if lab.lower() in GENERIC:
                out.append({"rule": "generic-label", "person": "blind", "severity": "warning", **where})
            if lab:
                labels.setdefault(lab, []).append(where)
        elif cls in ("ImageView", "Image") and not lab:
            out.append({"rule": "image-no-desc", "person": "blind", "severity": "info", **where})
        if n.get("text") and h < 12 and not clickable:
            out.append({"rule": "tiny-text", "person": "lowvision", "severity": "warning", **where})
    for lab, nodes in labels.items():
        if len(nodes) > 1:
            out.append({"rule": "duplicate-label", "person": "blind", "severity": "warning", "label": lab, "count": len(nodes),
                        "paths": [x["path"] for x in nodes]})
    return out


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__); return 2
    density = int(argv[argv.index("--density") + 1]) if "--density" in argv else 420
    findings = audit(argv[0], density)
    if "--json" in argv:
        print(json.dumps(findings, indent=2, ensure_ascii=False)); return 1 if any(f["severity"] == "error" for f in findings) else 0
    order = {"error": 0, "warning": 1, "info": 2}
    for f in sorted(findings, key=lambda f: (order[f["severity"]], f["rule"])):
        size = f" {f['size_dp'][0]}x{f['size_dp'][1]}dp" if "size_dp" in f else ""
        lab = f' "{f["label"]}"' if f.get("label") else ""
        print(f'{f["severity"]:7} {f["rule"]:15} {f["person"]:9}{size}{lab}  {f.get("class", "")} {f.get("bounds", "")}'.rstrip())
    errs = sum(f["severity"] == "error" for f in findings)
    print(f"\n{len(findings)} finding(s), {errs} error(s). A clean report is not a pass: see 'Limits' in --help.")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
