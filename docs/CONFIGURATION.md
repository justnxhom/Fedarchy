# Configuration Guide

How to customise Fedarchy without breaking unrelated desktop settings.

---

## 1. The three kinds of configuration

| Kind | Directory | Who reads it |
|---|---|---|
| **Runtime resources** | `default/` → `$OMARCHY_PATH` | The shell and Hyprland at runtime |
| **User templates** | `config/` → `~/.config/…` | Installed application defaults |
| **Theme definitions** | `themes/` → `~/.config/omarchy/themes/` | `omarchy-theme-set` |

Both `default/` and `config/` are deployed by the installer
(`DEPLOYED_DIRS=(bin config default scripts shell themes)`), but they serve
different purposes — see [ARCHITECTURE.md](ARCHITECTURE.md#default-vs-config--an-important-distinction).

---

## 2. Canonical paths

| Path | Purpose |
|---|---|
| `$OMARCHY_PATH` | The deployed Fedarchy tree |
| `~/.local/bin` | Installed commands |
| `~/.config/omarchy/shell.json` | Shell enable/disable state for plugins & widgets |
| `~/.config/omarchy/themes/` | Installed themes |
| `~/.config/omarchy/hooks/` | Hook scripts |
| `~/.config/omarchy/plugins/` | User (third-party) plugins |
| `~/.config/hypr/` | **The Hyprland config that is actually loaded** |
| `~/.config/fedarchy/environment` | Generated environment file |
| `~/.local/state/fedarchy/` | Installer state |
| `~/.config/fedarchy-backups/` | Installer backups |

### The Hyprland caveat you must know

Editing the shipped `default/hypr/bindings/*.lua` in the project tree changes
**nothing** at runtime. Hyprland loads `~/.config/hypr/`, and only the files your
`hyprland.lua` requires are read. A binding changed in only one tree is silently
dead. Full explanation: [hyprland-keybindings.md](hyprland-keybindings.md).

---

## 3. Themes

```bash
omarchy-theme-list                     # list available themes
omarchy-theme-set nord                # apply one
omarchy-theme-current                 # show the active theme
```

A theme directory contains `colors.toml`, `backgrounds/`, `icons.theme`,
`neovim.lua`, `vscode.json`, `preview.png`, and `unlock.png`. Applying a theme
writes into `~/.config/omarchy/themed/` and updates Qt/GTK caches.

Switching themes is user-level and reversible — re-apply your previous theme.
→ [FEATURES.md](FEATURES.md#themes-22-bundled)

---

## 4. Shell settings

`~/.config/omarchy/shell.json` records which plugins and bar widgets are enabled.
It is one of the installer's declared **runtime-contract** files, so
`install.sh check` verifies it is present and correct.

Widget selection is **all-or-nothing per component** — there is no fine-grained
per-widget installer component. Individual widgets are toggled through
`shell.json`, not through the installer's component model.

---

## 5. Hyprland configuration

Applying the `hypr-config` component writes into `~/.config/hypr`. If you already
have a Hyprland setup you care about, choose the **`preserve`** profile, which
omits `hypr-config` and `keybindings`, or decline those components.

When you do install keybindings and decline Fedarchy's defaults, the installer can
write `omarchy_default_bindings = false` into your config so your own entrypoint
controls whether they load. **This is covered by static tests only** — it has not
been verified in a live Hyprland session.

---

## 6. Keybindings

Fedarchy's shortcuts live under `default/hypr/bindings/*.lua` (shipped defaults)
but the **live** bindings are `~/.config/hypr/modules/binds.lua`. Both trees must
agree for a binding to work. → [hyprland-keybindings.md](hyprland-keybindings.md)

---

## 7. Application configuration

The `app-configs` component writes ready-made configuration for terminals and
other applications into `~/.config` (alacritty, foot, ghostty, kitty, chromium,
wireplumber, and others). Files that already exist are **kept** unless you choose
to replace them; anything replaced is backed up first.

---

## 8. Environment variables

| Variable | Effect |
|---|---|
| `OMARCHY_PATH` | Root of the deployed Fedarchy tree. Default `~/.local/share/fedarchy` for the installer; `~/Fedarchy` for `omarchy-launch-shell` if unset |
| `FEDARCHY_BACKUP_DIR` | Where installer backups go. Default `~/.config/fedarchy-backups` |
| `XDG_STATE_HOME` | Installer state. Default `~/.local/state` |
| `XDG_DATA_HOME` | Installer data root. Default `~/.local/share` |

### XDG handling — read this before assuming

Fedarchy's installer deliberately pins `CONFIG_HOME="$HOME/.config"`. It is
**not** fully XDG-portable: **do not assume a custom `XDG_CONFIG_HOME` is
supported.** Components and commands still rely on the conventional
`~/.config` location, so moving it can leave the shell reading a different tree
than the one you configured. This is a known limitation →
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).

---

## 9. Conflicts, backups, and recovery

- **Existing files are kept** by default; you choose whether to replace.
- **Replacements are backed up** before they are overwritten, into
  `~/.config/fedarchy-backups` (or `FEDARCHY_BACKUP_DIR`).
- Inspect backups with `bash scripts/install.sh list`.
- Restore the most recent one with `bash scripts/install.sh rollback`.

→ [Installer guide → Safe behaviour](INSTALLER_GUIDE.md#7-safe-behaviour)

---

## 10. State and cache

| Location | Contents |
|---|---|
| `~/.local/state/fedarchy/` | Installer state, e.g. chosen profile |
| `~/.cache/` (Qt/GTK) | Theme caches, regenerated on theme change |

Neither is essential to back up before an update; both are rebuildable.

---

**See also:** [INSTALLER_GUIDE.md](INSTALLER_GUIDE.md) ·
[hyprland-keybindings.md](hyprland-keybindings.md) ·
[ARCHITECTURE.md](ARCHITECTURE.md) · [TROUBLESHOOTING.md](TROUBLESHOOTING.md)