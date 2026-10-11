#!/usr/bin/env python3

"""Keybinding contract checks.

Two trees are kept in sync by hand:
  - default/hypr/bindings/*.lua  (shipped with the project)
  - ~/.config/hypr/modules/binds.lua (the live personal config)

The live config never requires the default tree, so a binding changed in only
one place is silently dead. These checks fail when that drift happens. They
also flag any key that both trees bind to *different* actions, which is how
SUPER + L silently meant "lock" in one tree and "layout toggle" in the other.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BINDINGS = ROOT / "default" / "hypr" / "bindings"
LIVE = Path.home() / ".config" / "hypr" / "modules" / "binds.lua"

MOD = "SUPER"

BIND_RE = re.compile(
    r"""(?P<style>o|hl)\.bind(?:_toggle)?\(\s*
        (?: "(?P<key>[^"]*)"                     # o.bind("SUPER + X", ...)
          | (?P<var>\w+)\s*\.\.\s*"(?P<lit>[^"]*)" )  # hl.bind(mod .. " + X", ...)
        \s*,\s*(?P<args>.*)$""",
    re.VERBOSE,
)

DIRECTION_NAMES = {"l": "left", "r": "right", "u": "up", "d": "down"}

# Keys the personal config deliberately remaps away from the project default.
# Both trees are only ever loaded one at a time, so these are choices, not bugs.
# Anything NOT listed here must agree, which is what catches silent drift.
INTENTIONAL_OVERRIDES = {
    "PRINT": "personal: hyprshot region capture instead of omarchy-capture-screenshot",
    "SUPER + C": "personal: close window instead of universal copy",
    "SUPER + F": "personal: plain fullscreen",
    "SUPER + Q": "personal: kitty instead of close window",
    "SUPER + T": "personal: float toggle",
    "SUPER + V": "personal: clipboard shell toggle",
    "SUPER + SHIFT + C": "personal: color picker instead of calendar",
    "SUPER + SHIFT + E": "personal: emoji menu instead of email",
    "SUPER + SHIFT + F": "personal: theme background switcher",
    "SUPER + SHIFT + SLASH": "personal: keybindings menu instead of 1password",
    "SUPER + SHIFT + W": "personal: background switcher instead of omawrite",
    "SUPER + SPACE": "personal: shell menu toggle instead of omarchy-menu toggle",
}


class Failure(Exception):
    pass


def action_signature(style, args):
    """Comparable form of a binding's action, ignoring harmless spelling differences."""
    if style == "o":
        # o.bind("KEY", "Description", dispatcher) - the description is not the action.
        described = re.match(r'\s*"[^"]*"\s*,\s*(.*)$', args)
        args = described.group(1) if described else args
    # hl.bind(key, dispatcher, options) - the dispatcher comes first.

    command = re.search(r"exec_cmd\((.*)", args)
    if command:
        quoted = re.findall(r'"([^"]*)"', command.group(1))
        if quoted:
            # Project: "omarchy-system-lock"; live: bin .. "/omarchy-system-lock"
            return quoted[0].lstrip("/")

    args = args.split(", {")[0]  # drop trailing options tables
    args = re.sub(r'\{ mode = "(fullscreen|maximized)" \}', "", args)  # same intent, both spellings
    args = re.sub(
        r'direction = "([lru d])"',
        lambda match: f'direction = "{DIRECTION_NAMES[match.group(1)]}"',
        args,
    )
    return " ".join(args.split()).rstrip(")").strip().strip('"').strip()


def parse_file(path):
    """Return [(key, action_signature)] for one Lua file."""
    binds = []
    for line in path.read_text(encoding="utf-8").splitlines():
        match = BIND_RE.search(line)
        if not match:
            continue

        if match.group("var") is not None:
            tail = match.group("lit").strip().lstrip("+").strip()
            key = f"{MOD} + {tail}" if tail else MOD
        else:
            key = match.group("key")

        if not key:
            continue

        key = " ".join(key.split()).upper()
        binds.append((key, action_signature(match.group("style"), match.group("args"))))
    return binds


def parse_tree(target):
    binds = []
    if target.is_dir():
        for lua in sorted(target.glob("*.lua")):
            binds.extend(parse_file(lua))
    elif target.is_file():
        binds.extend(parse_file(target))
    return binds


def group_by_key(binds):
    grouped = {}
    for key, action in binds:
        grouped.setdefault(key, set()).add(action)
    return grouped


def expect_single(grouped, key, must_contain, label):
    actions = sorted(grouped.get(key, []))
    if len(actions) != 1:
        raise Failure(f"{label}: expected exactly one {key} binding, found {len(actions)} {actions}")
    if must_contain not in actions[0]:
        raise Failure(f"{label}: {key} does not run {must_contain}: {actions[0]}")


def main():
    project = parse_tree(BINDINGS)
    if not project:
        raise Failure(f"no bindings parsed from {BINDINGS}")
    project_by_key = group_by_key(project)

    print("== lock binding in the project tree ==")
    expect_single(project_by_key, "SUPER + L", "omarchy-system-lock", "project tree")

    print("== workspace layout toggle in the project tree ==")
    expect_single(
        project_by_key,
        "SUPER + SHIFT + L",
        "omarchy-hyprland-workspace-layout-toggle",
        "project tree",
    )

    if not LIVE.is_file():
        print("== live config not present, skipping parity checks ==")
        print(f"  ({LIVE} not found; run this on the target machine to verify parity)")
    else:
        live = parse_tree(LIVE)
        if not live:
            raise Failure(f"no bindings parsed from {LIVE}")
        live_by_key = group_by_key(live)

        print("== lock binding in the live config ==")
        expect_single(live_by_key, "SUPER + L", "omarchy-system-lock", "live config")

        print("== workspace layout toggle in the live config ==")
        expect_single(
            live_by_key,
            "SUPER + SHIFT + L",
            "omarchy-hyprland-workspace-layout-toggle",
            "live config",
        )

        print("== no key bound to two different actions across trees ==")
        conflicts = []
        for key in sorted(set(live_by_key) & set(project_by_key)):
            if key in INTENTIONAL_OVERRIDES:
                continue
            live_actions = live_by_key[key]
            project_actions = project_by_key[key]
            if not (live_actions & project_actions):
                conflicts.append(
                    f"\n  {key}: live={sorted(live_actions)} project={sorted(project_actions)}"
                )

        if conflicts:
            raise Failure(
                "same key bound to different actions (add a documented override to "
                "INTENTIONAL_OVERRIDES if this is intentional):" + "".join(conflicts)
            )

        shared = set(live_by_key) & set(project_by_key)
        unchecked = sorted(shared & set(INTENTIONAL_OVERRIDES))
        print(
            f"   {len(live_by_key)} live keys checked, {len(shared)} shared with the project tree, "
            f"{len(unchecked)} documented overrides"
        )

    print("keybinding tests passed")


if __name__ == "__main__":
    try:
        main()
    except Failure as failure:
        print(f"Keybinding check failed: {failure}", file=sys.stderr)
        sys.exit(1)
