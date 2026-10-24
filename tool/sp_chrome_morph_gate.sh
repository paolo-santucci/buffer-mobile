#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re
import sys

def source(path):
    return "\n".join(line for line in Path(path).read_text().splitlines()
                     if not line.lstrip().startswith("//"))

chrome = source("iosApp/iosApp/Chrome/ChromeOverlay.swift")
share = source("iosApp/iosApp/Chrome/SystemSharePresenter.swift")
menu = source("iosApp/iosApp/Chrome/MenuBubble.swift")
editor = source("iosApp/iosApp/Editor/BufferEditor.swift")
toolbar = source("iosApp/iosApp/Chrome/BottomToolbar.swift")
content = source("iosApp/iosApp/ContentView.swift")

checks = {
    "bottom toolbar action order": 0 <= toolbar.find("closeKeyboardButton") < toolbar.find("copyButton"),
    "editor inset preserved": "textContainerInset" in editor and not re.search(r"textContainerInset\s*=\s*\.zero", editor),
    "editor fragment padding": "lineFragmentPadding = 0" in editor,
    "real grouped navigation items": all(token in chrome for token in (
        "UINavigationController(rootViewController: editor)", "trailingItemGroups", "[shareItem, menuItem]")),
    "menu popover anchored to menu item": all(token in chrome for token in (
        "modalPresentationStyle = .popover", "popover.sourceItem = menuItem", "popover.delegate = self")),
    "share popover anchored to bar item": all(token in share for token in (
        "from source: UIBarButtonItem", "popover.sourceItem = source", "modalPresentationStyle = .popover")),
    "system owns presentation glass": not re.search(
        r"glassEffect|GlassEffectContainer|dropCarrier|journeyTask|shareBlob|ShareSourceAnchor|Task\.sleep",
        chrome + menu + share),
    "reduce motion preserved": "UIAccessibility.isReduceMotionEnabled" in chrome
        and "UIAccessibility.isReduceMotionEnabled" in share and "accessibilityReduceMotion" in menu,
    "native compact-width presentation": "adaptivePresentationStyle" in chrome and ".none" in chrome
        and "adaptivePresentationStyle" in share and ".none" in share,
    "keyboard-safe bottom toolbar": ".safeAreaInset(edge: .bottom" in content,
    "bounded scrolling menu": "ScrollView" in menu and "maximumHeight" in menu,
}
for label, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {label}")
print(f"Native chrome gate: {sum(checks.values())}/{len(checks)} passed")
sys.exit(0 if all(checks.values()) else 1)
PY

bash tool/m4_gate.sh
