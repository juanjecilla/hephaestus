#!/usr/bin/env python3
"""Approximate what TalkBack would say for a screen, from a UiAutomator dump. No device audio, no TalkBack needed.

Usage: speak.py <screen.xml> [--all]

Reading order = document order of the nodes a screen reader can focus: clickable/checkable/focusable nodes and
text nodes, merged the way TalkBack merges a clickable container ("Dune, 8.3, Movie poster, double tap to open").
Unlabeled clickable nodes print as «unlabeled» so they stand out.

This is an approximation. UiAutomator does not expose headings, roles set with Modifier.semantics, state
descriptions, custom actions or the real traversal order. Use it to hear problems early; confirm with TalkBack.
"""
import re, sys
import xml.etree.ElementTree as ET


def own_label(n):
    return (n.get("content-desc") or n.get("text") or "").strip()


def descendants_labels(n):
    out = []
    for c in n:
        l = own_label(c)
        if l:
            out.append(l)
        out += descendants_labels(c)
    return out


def role(n):
    cls = n.get("class", "")
    if n.get("checkable") == "true":
        return "switch" if "Switch" in cls or "Toggle" in cls else "checkbox"
    if "EditText" in cls:
        return "edit box"
    if "ImageView" in cls or cls.endswith(".Image"):
        return "image"
    if "Button" in cls or n.get("clickable") == "true":
        return "button"
    return ""


def speak(root, show_all=False):
    lines = []

    def visit(n, inside_clickable):
        clickable = n.get("clickable") == "true" or n.get("checkable") == "true"
        label = own_label(n)
        if clickable and not inside_clickable:
            parts = ([label] if label else []) + descendants_labels(n)
            text = ", ".join(dict.fromkeys(parts)) or "«unlabeled»"
            r = role(n) or "button"
            extra = ", selected" if n.get("selected") == "true" else ""
            extra += ", checked" if n.get("checked") == "true" else ""
            extra += ", disabled" if n.get("enabled") == "false" else ""
            lines.append(f"{text}, {r}{extra}, double tap to activate")
            return  # children are merged into this announcement
        if label and not inside_clickable and (n.get("text") or show_all):
            lines.append(label)
        elif label and not inside_clickable:
            lines.append(f"{label}, {role(n) or 'image'}")
        for c in n:
            visit(c, inside_clickable or clickable)

    visit(root, False)
    return lines


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__); return 2
    for i, line in enumerate(speak(ET.parse(argv[0]).getroot(), "--all" in argv), 1):
        print(f"{i:>3}  {line}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
