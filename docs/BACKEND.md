# Backend Internals

A source-grounded guide to how Fedarchy actually works. Each subsystem lists its
entry points, inputs/outputs, dependencies, failure handling, and the tests that
cover it.

> For the directory map see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## 1. CLI entry points and dispatch

### Shape

Fedarchy does **not** use a central CLI dispatcher. Each of the 453 files in
`bin/` is a standalone executable script. The one true dispatcher is
`bin/omarchy-hook`.

Most commands follow the same pattern:

1. Declare `set -euo pipefail` (or `set -e`).
2. Declare an `# omarchy:summary=` / `# omarchy:args=` metadata header — this is
   what makes commands self-describing.
3. Source shared helpers or resolve `$OMARCHY_PATH`.
4. Validate arguments.
5. Do the work, usually by shelling out to a system tool.
6. Report a clear error and exit non-zero on failure.

### Package-manager integration

Fedarchy is DNF5-based. The `omarchy-pkg-*` family and the menu's package
actions call `dnf5`. `bin/omarchy-update-orphan-pkgs` was hardened during the
portability work so that a **failed** DNF query is reported rather than being
silently treated as an empty result — a test in `tests/backend-fedora.sh` covers
this.

**Inputs:** user arguments. **Outputs:** terminal output, exit status, system
state via DNF5. **Failure:** non-zero exit with a message; a failed query is
never presented as "nothing found".

---

## 2. Hook discovery and dispatch

**Entry point:** `bin/omarchy-hook <name> [args...]`

**Behaviour:**
- Rejects empty hook names, names containing `/`, and the bare names `.` and
  `..` — this prevents a hook name from escaping the hooks directory. (Dots
  *inside* a name, e.g. `a..b`, are allowed; with slashes excluded, only a whole
  name of `.` or `..` could traverse.)
- Runs `~/.config/omarchy/hooks/<name>` if it is a file.
- Runs every **executable** file in `~/.config/omarchy/hooks/<name>.d/`.
- Skips documentation files (`README*`, `LICENSE`, `*.md`, `*.txt`, `*.rst`) so a
  dropped-in README is not executed as a hook.

**Dependencies:** bash only. **Failure:** exit 1 for no name, exit 2 for an
invalid name. **Tests:** `tests/hooks-backend-test.sh`.

Hook names are **fixed labels chosen by code** (e.g. `post-update`, `theme-set`,
`font-set`), which is why they are validated rather than taken as free-form paths.

---

## 3. Theme selection and configuration

**Entry points:** `omarchy-theme-set <name>`, `omarchy-theme-current`,
`omarchy-theme-list`, plus the `theme` family (43 commands).

**Flow:**
1. Validate the theme name against `themes/`.
2. Copy colour definitions into the user config tree (`~/.config/omarchy/themed/`,
   per `config/omarchy/themed`).
3. Apply backgrounds from the theme's `backgrounds/` directory.
4. Apply per-app colour maps (Neovim, VS Code) and icon-theme mappings.
5. Update Qt/GTK caches.

**Safety work during the port:**
- `omarchy-theme-set` had a **hang** in synthetic-home tests caused by background
  cleanup timers inheriting stdout. The timers are now detached/redirected, and
  the test runs under `timeout` and passes.
- The theme-picker test resolves `Path.home()` and skips cleanly when no theme is
  present, instead of failing on a hard-coded path.

**Tests:** `theme-set`, `theme-staging`, `theme-app-configs`,
`theme-browser-gtk`, `theme-qt-cache`, `theme-tui-apps`, `theme-install`,
`theme-plugin-add`, `theme-picker`, `theme-font`.

---

## 4. Quickshell initialization and plugin lifecycle

**Entry point:** `shell/shell.qml`, launched per graphical session (Hyprland
autostart). `bin/omarchy-launch-shell` resolves the shell config as
`${OMARCHY_PATH%/}/shell` and exports `OMARCHY_PATH`.

**Startup:**
1. `shell.qml` instantiates the services in `shell/services/`.
2. `PluginRegistry` discovers plugins from `shell/plugins/` (first-party) and
   `~/.config/omarchy/plugins/<plugin-id>/` (user).
3. Bar widgets register through `BarWidgetRegistry` and `PluginBarWidgetRegistryApi`.
4. Plugins render bar, panels, and overlays.

**Long-lived singletons** (one per session): `PluginRegistry`, `AppLibrary`,
`AppSearch.js`, `BarWidgetRegistry`, `AuthServiceStore.js`, and the
`Plugin*Api.qml` host APIs that bound the objects a plugin can reach.

**Plugin discovery** is event-driven via `inotifywait` when available; a manual
`rescanPlugins` remains for when the watcher is unavailable.

**Hot reload:** a package upgrade rewriting `$OMARCHY_PATH/shell` would otherwise
re-trigger a reload, so `omarchy-launch-shell` guards against it.

**Tests:** `tests/lifecycle-shell-test.sh`,
`tests/plugin-registry-lifecycle-test.sh`, `tests/plugin-update-test.sh`,
`tests/plugin-validate-test.sh`, `tests/media-service-contract-test.js`.

> **Trust model:** plugins are trusted, unsandboxed code with your session
> privileges. The host limits exposed objects, but a plugin can still reach your
> files, processes, D-Bus session, and network. → [omarchy-plugins.md](omarchy-plugins.md)

---

## 5. IPC between shell and CLI

The shell and the CLI talk over **D-Bus / IPC** exposed by `omarchy-shell`.
Shell UI actions invoke `omarchy-*` commands; commands such as `omarchy-theme-set`
and `omarchy-restart-shell` drive the shell.

A trivial round-trip check:

```bash
omarchy-shell ping     # → ok
```

**Tests:** `tests/lifecycle-shell-test.sh`, `tests/shell-config-test.sh`.

---

## 6. Desktop-service integrations (externally managed)

These panels do not own their state; they read it from system services.

| Panel | Backs onto | Notes |
|---|---|---|
| Audio | PipeWire / WirePlumber (`wpctl`, `pactl`) | Not runtime-verified |
| Network / Wi-Fi | NetworkManager (`nmcli`) | DNS configuration was **removed** from Fedarchy |
| Power | UPower (`upower`) | Not runtime-verified |
| Bluetooth | `bluetoothctl` | — |
| Monitor | Hyprland / DRM | — |
| Dropbox, Tailscale | Their own clients | Panel presence ≠ service configured |

---

## 7. Installer component resolution

**Files:** `scripts/install.sh` (1152 lines) and `scripts/install-components.sh`
(137 lines).

**Manifest** — `COMPONENT_SPECS`, pipe-delimited:
```
id | required | depends-on | destination | what | why
```

**Resolution:**
1. `profile_components <profile>` expands a profile to component ids, or explicit
   `--component`/`--components` supplies them.
2. `resolve_dependencies` walks `depends-on` transitively (`keybindings` →
   `hypr-config` → `shell`).
3. The resolved set, with destinations, is printed in the plan for review.
4. Preflight must pass before any mutation.
5. Replaced files are backed up; deployment syncs `DEPLOYED_DIRS` into
   `$OMARCHY_PATH`.

**Commands:** `install`, `link`, `check`, `rollback`, `uninstall`, `status`,
`list`. **Tests:** 67 installer tests + 81 installer-UX tests.

---

## 8. Environment and runtime-resource resolution

`bin/omarchy-launch-shell`:

```bash
export OMARCHY_PATH="${OMARCHY_PATH:-$HOME/Fedarchy}"
SHELL_CONFIG="${OMARCHY_PATH%/}/shell"
```

The installer uses:

| Variable | Default |
|---|---|
| `OMARCHY_PATH` | `${XDG_DATA_HOME:-$HOME/.local/share}/fedarchy` |
| `FEDARCHY_BACKUP_DIR` | `$HOME/.config/fedarchy-backups` |
| `XDG_STATE_HOME` | `$HOME/.local/state` |
| `XDG_DATA_HOME` | `$HOME/.local/share` |

`CONFIG_HOME` is pinned to `$HOME/.config` deliberately — see
[CONFIGURATION.md](CONFIGURATION.md#xdg-handling--read-this-before-assuming).

---

## 9. Notable backend limitations

- Shell argument handling is per-command; there is no shared validation library.
- 107 commands invoke `sudo` and 7 use `pkexec` when *run by the user* — the
  installer itself never elevates.
- Syntax validation is **not** behavioural coverage: 494 shell scripts pass `bash -n`,
  but only ~30% of commands are named in any behavioural test (a rough proxy).
  → [TESTING.md](TESTING.md)
- **ShellCheck is unavailable** on the primary system, so no shellcheck-level
  analysis has been run.

---

**See also:** [ARCHITECTURE.md](ARCHITECTURE.md) · [COMMAND_REFERENCE.md](COMMAND_REFERENCE.md) ·
[SECURITY.md](SECURITY.md) · [TESTING.md](TESTING.md)