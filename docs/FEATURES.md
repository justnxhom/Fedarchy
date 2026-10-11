# Feature Catalog

What Fedarchy actually offers, based on its current source. Each entry says what
it does, why you might want it, where it lives, and — importantly — its honest
status and limitations.

Status key: **Available** (working, in the codebase) · **Optional** (component
you can select) · **Externally managed** (depends on a system service) ·
**Partially supported** · **Not shipped** · **Not runtime-verified**.

---

## Desktop shell (Quickshell)

| Feature | What it is | Why you might want it | Where | Status |
|---|---|---|---|---|
| **Unified bar** | A status bar hosted in the shell | Glanceable workspace info in one place | `shell/plugins/bar/` | Available |
| **Panels** | Dropdown panels for audio, network/Wi-Fi, Bluetooth, power, clock, weather, monitor, disk/network speedtest, Dropbox, Tailscale | Reach settings without hunting for apps | `shell/plugins/panels/` | Available |
| **Menu** | Launcher/system menu | One entry point for actions | `shell/plugins/menu/` | Available |
| **Background** | Wallpaper/background switching | Multiple backgrounds per theme | `shell/plugins/background/` | Available |
| **Notifications** | Notification centre | On-screen notification history | `shell/plugins/notifications/` | Available, **not runtime-verified** |
| **Lock screen** | Lock/unlock screen with themed assets | Lock the session with your theme | `shell/plugins/lock/` | Available |
| **OSD** | On-screen display for volume/brightness | Immediate feedback on media keys | `shell/plugins/osd/` | Available |
| **Clipboard history** | Clipboard manager | Recover what you copied | `shell/plugins/clipboard/` | Available |
| **Agents / reminders** | Agent-backed reminder helpers | Lightweight reminders | `shell/plugins/agents/`, `shell/plugins/reminders/` | Available |

The shell is one long-running Quickshell process; the bar, panels, and overlays
are **plugins** inside it. See [Architecture](ARCHITECTURE.md) and
[`shell/README.md`](../shell/README.md).

### Plugin system
Fedarchy supports third-party plugins via the Omarchy plugin contract. Plugins
are **trusted, unsandboxed** code running with your session privileges.
→ [docs/omarchy-plugins.md](omarchy-plugins.md)

---

## Command-line toolkit (453 commands)

`omarchy-*` utilities, installed to `~/.local/bin`. Grouped by purpose (full
catalogue in [COMMAND_REFERENCE.md](COMMAND_REFERENCE.md)):

| Group | Examples | Status |
|---|---|---|
| Themes | `omarchy-theme-set`, `omarchy-theme-current`, `omarchy-theme-list` | Available |
| Hardware | `omarchy-brightness-*`, `omarchy-power-*`, audio controls | Available; some **externally managed** (UPower, WirePlumber) |
| Packages | `omarchy-pkg-add`, `omarchy-pkg-installed`, COPR helpers | Available, DNF5-based |
| Apps & web apps | `omarchy-install-app`, `omarchy-webapp-install` | Optional; **many may install packages** |
| Plugins | `omarchy-plugin-add`, `omarchy-plugin-*` | Available |
| Network | `omarchy-network-*`, `omarchy-wifi-*` | Available |
| Updates | `omarchy-update`, `omarchy-update-*` | Available |

---

## Themes (22 bundled)

Each theme under `themes/` ships colours, backgrounds, and per-app colour maps:

| File | Purpose |
|---|---|
| `colors.toml` | The theme's colour palette |
| `backgrounds/` | Wallpapers for the background plugin |
| `icons.theme` | Icon-theme mapping |
| `neovim.lua`, `vscode.json` | Editor colour schemes |
| `preview.png`, `unlock.png` | Theme previews / lock-screen asset |

Switch with `omarchy-theme-set <name>`. → [CONFIGURATION.md](CONFIGURATION.md#3-themes)

**Limitation:** per-file provenance for bundled background images is not fully
verified — see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

---

## Hyprland integration

| Feature | What it is | Status |
|---|---|---|
| Hyprland config | Window behaviour, layout, monitors | Optional component; may conflict with an existing config |
| Keybindings | Keyboard shortcuts | Optional; see the two-tree caveat below |

> **Important:** Hyprland keybindings exist in **two** places and only one is
> loaded at runtime. Editing the shipped `default/hypr/bindings/*.lua` alone does
> **nothing** on a live machine — the active file is `~/.config/hypr/modules/binds.lua`.
> → [docs/hyprland-keybindings.md](hyprland-keybindings.md)

---

## Installation & customization

| Feature | What it is | Status |
|---|---|---|
| Setup installer | Component-selecting, home-only, no-`sudo` deploy | Available; **not validated on real hardware** |
| Profiles | `minimal` / `recommended` / `preserve` / `custom` starting points | Available |
| Component selection | Add/remove components individually | Available |
| Dry run | Preview the plan without changing anything | Available |
| Rollback | Restore the most recent backup | Available (manual) |

→ [INSTALLER_GUIDE.md](INSTALLER_GUIDE.md)

---

## Developer facilities

| Feature | What it is | Status |
|---|---|---|
| Regression suite | 40-test main suite (`scripts/test.sh`) | Available, passing |
| Installer suites | 67 + 81 installer/UX tests | Available, passing |
| Backend & hook tests | Mocked system-command coverage (24 tests) | Available, passing |
| Relocation testing | Synthetic-home / temp-dir testing | Available |
| Plugin validation | `omarchy-plugin-*` + validate tests | Available |

→ [TESTING.md](TESTING.md) · [DEVELOPMENT.md](DEVELOPMENT.md)

---

## Explicitly *not* shipped

These exist upstream in Omarchy but are outside Fedarchy's desktop scope. They
are **not** missing features and are not documented as available:

Disk partitioning/formatting, disk encryption, bootloader configuration,
whole-machine factory reset, OEM/user provisioning, hibernation setup, and
system DNS configuration.

See [SECURITY.md](SECURITY.md) and [OMARCHY_PORT.md](OMARCHY_PORT.md) for why,
and [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) for the full list of
removed commands.

Also absent (placeholders, not features): `assets/` and `Wallpapers/` are empty
directories; there is no fine-grained per-widget selection component.

---

**See also:** [FAQ.md](FAQ.md) · [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) ·
[COMMAND_REFERENCE.md](COMMAND_REFERENCE.md)