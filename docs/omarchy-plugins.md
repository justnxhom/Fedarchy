# Fedarchy Third-Party Plugins

Fedarchy uses the Omarchy Quattro plugin contract. Plugins are trusted, unsandboxed code running with the user's session privileges. The host limits exposed objects, but a plugin is not isolated from the user's files, processes, D-Bus session, or network.

## Locations

- First-party plugins: `$OMARCHY_PATH/shell/plugins/`
- User plugins: `~/.config/omarchy/plugins/<plugin-id>/`
- User plugin state and settings remain outside the plugin directory when the plugin supports that layout.
- Enabled state is stored in `~/.config/omarchy/shell.json`.

The shell must have `OMARCHY_PATH` set to the Fedarchy checkout. User plugin discovery is event-driven through `inotifywait` when available; manual `rescanPlugins` remains available if the watcher is unavailable.

## Manifest

A plugin has a root `manifest.json`:

```json
{
  "schemaVersion": 1,
  "id": "example.weather",
  "name": "Example Weather",
  "version": "1.0.0",
  "description": "A small Quattro widget.",
  "kinds": ["bar-widget", "service"],
  "entryPoints": {
    "barWidget": "BarWidget.qml",
    "service": "Service.qml"
  },
  "barWidget": {
    "displayName": "Example Weather",
    "description": "A small Quattro widget.",
    "category": "Weather",
    "defaultSection": "right",
    "allowMultiple": false
  }
}
```

Supported kinds and entry-point keys are `bar`/`bar`, `bar-widget`/`barWidget`, `panel`/`panel`, `overlay`/`overlay`, `menu`/`menu`, and `service`/`service`. Every declared kind must have its matching entry point. Entry points are relative paths inside the plugin directory; absolute paths, traversal, and symlinks are rejected.

`omarchy.*` is reserved for first-party plugins. Bar widgets default to the center section when `defaultSection` is omitted. A third-party plugin is enabled when its ID is present in the appropriate bar layout or `plugins` configuration. First-party non-widget plugins are enabled unless listed in `disabledPlugins`.

## Commands

```text
omarchy plugin list
omarchy plugin list --json
omarchy plugin add <git-url> [--enable] [--yes]
omarchy plugin validate <path>
omarchy plugin enable <id> [--section left|center|right] [--index N]
omarchy plugin disable <id>
omarchy plugin update [id] [--yes]
omarchy plugin remove <id> [--yes]
```

`add` clones into a hidden staging directory, validates the manifest and entry points, rejects ID collisions, moves the result atomically, and rescans. Git updates require a clean worktree, fast-forward only, validate after fetch, and restore the previous commit if validation fails. Removal disables the runtime, removes stale layout/configuration references, preserves Git-managed contents in a timestamped hidden backup, and rescans.

## Runtime APIs

The host may inject `omarchyPath`, `manifest`, `shell`, `pluginRegistry`, and `barWidgetRegistry` according to plugin kind. Bar widgets receive the supported `bar` facade. Services can be queried through `shell call <id> <method> <arg>`. Panels, overlays, and menus are summoned and hidden through their existing Quattro lifecycle.

The facades are capability boundaries, not a sandbox. A plugin should not retain or expose internal host objects. Services are singleton instances inside the current Quickshell process; panels, overlays, and menus are lazy-loaded.

## Fedora limitations

Fedarchy does not restore `pacman`, `paru`, `yay`, AUR, or UWSM integration for plugins. A plugin that requires an Arch-only package manager or session manager is not compatible and must report that limitation. Plugin installation never runs repository install hooks, manifest commands, or `sudo`.

## Development testing

Use `tests/fixtures/fedarchy-test-plugin/` as a local service plus bar-widget fixture. Run:

```text
bash tests/plugin-validate-test.sh
bash tests/plugin-registry-lifecycle-test.sh
bash tests/plugin-update-test.sh
bash scripts/test.sh
```

The integration fixture is intentionally multi-kind so service teardown and bar-widget registration are tested separately. A real external plugin must still be installed, enabled, restarted, disabled, re-enabled, and removed before compatibility is claimed.

## Vendored first-party plugins

Most first-party plugins in `shell/plugins/` were written for this project.
One is **third-party code carried into the repository**:

| Plugin | Upstream | Licence |
|---|---|---|
| `omarchy.konobeat` | [Konobeat](https://github.com/xvvhang/omarchy-konobeat-plugin) by Alec Xu | MIT — see [`shell/plugins/konobeat/NOTICE.md`](../shell/plugins/konobeat/NOTICE.md) |

It is vendored rather than installed from its upstream repository so that the
audio visualizer's appearance can be read from a configuration file the user
owns. It did not come from upstream Omarchy, and it is not part of this
project's Omarchy port. The full provenance record is in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

## Current compatibility

Fedarchy follows the current Quattro manifest, registry, bar layout, loader, lifecycle, and CLI shape. It adds Fedora-native package/backend behavior, controlled capability facades, safer configuration mutation, and a stricter validator. It does not claim that every Arch-oriented plugin is portable; external dependencies and helper binaries must be checked individually.
