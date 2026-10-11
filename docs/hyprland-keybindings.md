# Hyprland keybindings: two trees, one live config

Keybindings exist in two places, and only one of them is actually loaded:

| Tree | Loaded by | Purpose |
| --- | --- | --- |
| `default/hypr/bindings/*.lua` | nothing on this machine | shipped defaults for a fresh install |
| `~/.config/hypr/modules/binds.lua` | `~/.config/hypr/hyprland.lua` -> `require("modules.binds")` | the bindings you actually use |

`~/.config/hypr/hyprland.lua` only requires local `modules.*` files. It never
requires `default.hypr.*`, so **editing the project tree alone changes nothing
at runtime.** A binding changed in only one tree is silently dead, which is how
`SUPER + L` ended up meaning "lock" in the personal config while the project
tree still bound it to the workspace layout toggle.

## Rules

1. Change the binding in **both** trees, then `hyprctl reload`.
2. Keep the action identical in both. Only the key spelling may differ
   (`SUPER + L` vs `mod .. " + L"`).
3. If the personal config should intentionally remap a key away from the
   project default, record it in `INTENTIONAL_OVERRIDES` in
   `tests/hypr-bindings-test.py` with a one-line reason. Anything not listed
   there must agree, so new drift fails the suite instead of surprising you
   later.

## Current split

`SUPER + L` locks the system in both trees. The workspace layout toggle lives
on `SUPER + SHIFT + L` in both trees.

## Verification

```bash
python3 tests/hypr-bindings-test.py   # parity + conflict check
hyprctl binds -j | jq '.[] | select(.description | test("Lock system"))'
```

The test checks the project tree unconditionally. When
`~/.config/hypr/modules/binds.lua` exists it also checks that file and reports
how many live keys are shared, conflicting, or documented overrides; it skips
the parity section silently on a machine without that config.
