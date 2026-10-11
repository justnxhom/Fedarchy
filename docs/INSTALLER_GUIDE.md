# Installer Guide

Reference for `scripts/install.sh` and `scripts/install-components.sh` as they
exist **today**. Every option, profile, and component below was read from the
current source and confirmed against the installer's own `--help` output.

> For the end-to-end first-time walkthrough, see
> [INSTALLATION.md](INSTALLATION.md). For what each component *is*, see
> [FEATURES.md](FEATURES.md).

---

## 1. What the installer is

The Fedarchy setup installer **deploys Fedarchy's own files into your home
directory**. It selects *which* Fedarchy components to apply and copies their
runtime resources into the locations Fedarchy expects.

It is emphatically **not** an operating-system installer. It does not install
Fedora, partition disks, configure bootloaders, or provision a machine. It
writes only inside `$HOME`, never uses `sudo`, and never installs or removes
system packages. You can check this yourself — the only occurrences of the word
`sudo` in the installer are its own help text and a preflight *hint* telling you
which packages to install yourself:

```bash
grep -n 'sudo' scripts/install.sh
# 147: ... "No sudo is used and no package is installed..."
# 189: error "Fedora installs them with: sudo dnf5 install ..."
# 939: ... "This installer never uses sudo and never installs packages."
```

No line in the installer actually *executes* `sudo`.

The installer itself never elevates. **Separately**, some `omarchy-*` commands it
installs may use `sudo`/`pkexec` when *you* choose to run them later (e.g.
applying a theme to system GTK or adding your user to a group). That is a
property of those commands, not of the installer.

---

## 2. Commands

| Command | Purpose | Needs confirmation? |
|---|---|---|
| `install` | Deploy the checkout to `$OMARCHY_PATH` (default `~/.local/share/fedarchy`) | Yes, unless `--yes` |
| `link` | Point `$OMARCHY_PATH` at this checkout instead of copying | Yes, unless `--yes` |
| `check` | Verify a deployed tree against the runtime contract — read-only | No |
| `rollback` | Restore the most recent backup | Yes, unless `--yes` |
| `uninstall` | Remove the deployment and restore the previous tree | Yes, unless `--yes` |
| `status` | Show deployment status — read-only | No |
| `list` | List available backups — read-only | No |

## 3. Modes

| Mode | Purpose |
|---|---|
| `--interactive`, `-i` | Guided installer: pick a profile, adjust it, review, agree |
| `--check`, `--doctor` | Read-only diagnostics of a deployed installation |
| `--test` | Run the installer's own isolated test suites |

## 4. Options

| Option | Purpose | Interactive? | May change user/system state? |
|---|---|---|---|
| `-h`, `--help` | Print the help screen and exit | No | No |
| `--version`, `-V` | Print the installer version (`1.0.0`) | No | No |
| `--check`, `--doctor` | Read-only diagnostics | No | No |
| `--dry-run` | Work out and print the plan **without changing anything** | No | **No** |
| `--interactive`, `-i` | Guided selection and confirmation | Yes | Only after you confirm |
| `--profile <name>` | Start from `minimal`, `recommended`, `preserve`, or `custom` | No | Only via `install` |
| `--component <id>` | Install exactly this component (repeatable) | No | Only via `install` |
| `--components a,b` | Same, comma-separated | No | Only via `install` |
| `-y`, `--yes` | Authorise mutations without a prompt | No | Yes — this is the consent switch |

`--yes` does **not** bypass preflight, safety checks, or required decisions. A
non-interactive run with no `--yes` prints the plan and exits non-zero rather
than assuming consent.

### Combining options

- `--dry-run --interactive` previews a customised install without writing.
- `--profile X --component Y` → **`--profile` wins and `--component` is ignored**
  (the installer checks the profile first and only falls back to the explicit
  component list when no profile was given). To install exactly one set of
  components, use `--component` *without* `--profile`.
- An unknown `--profile` exits non-zero and names the valid options:

  ```console
  $ bash scripts/install.sh --profile bogus --dry-run
  [ERROR] Unknown profile: bogus. Choose from: minimal, recommended, preserve, custom.
  ```
- Mutating commands without `--yes` and without a TTY stop after printing the
  plan and exit non-zero.

---

## 5. Profiles

Profiles are **starting points, not commitments** — you can add or remove any
component before anything is installed. Read from `profile_components()` in
`scripts/install-components.sh`:

| Profile | Components |
|---|---|
| `minimal` | `shell` `commands` `themes` |
| `recommended` | `shell` `commands` `themes` `hypr-config` `keybindings` `bar-widgets` |
| `preserve` | `shell` `commands` `themes` `app-configs` |
| `custom` | nothing pre-selected — you choose |

`preserve` is the "keep my setup" option: it selects the shell, commands, and
themes but omits Hyprland config and keybindings, so it is less likely to
conflict with an existing desktop.

---

## 6. Components

Read from `COMPONENT_SPECS` in `scripts/install-components.sh`. The
`id | required | depends-on | destination | what | why` fields are verbatim:

| Component | Required | Depends on | Lands in | What it is |
|---|---|---|---|---|
| `shell` | ✔ | — | `$OMARCHY_PATH` | The desktop shell, runtime resources, helper modules |
| `commands` | ✔ | — | `~/.local/bin` | The `omarchy-*` commands you type |
| `themes` | | — | `~/.config/omarchy/themes` | The full theme collection |
| `hypr-config` | | `shell` | `~/.config/hypr` | Hyprland config: window behaviour, layout |
| `keybindings` | | `hypr-config` | `~/.config/hypr` | Fedarchy's keyboard shortcuts |
| `app-configs` | | `shell` | `~/.config` | Ready-made config for terminals, browsers, apps |
| `bar-widgets` | | `shell` | `~/.config/omarchy/shell.json` | Which widgets appear on the bar |

**Dependencies are real, not decorative.** Choosing `keybindings` pulls in
`hypr-config` (which pulls in `shell`); the resolved set is always shown in the
plan before you agree. Declining a component simply omits it — the installer
does not substitute a default you did not choose.

`shell` and `commands` are required for the desktop to function; the others are
optional additions.

---

## 7. Safe behaviour

- **Preflight** — checks OS, privileges, required commands, source tree, target
  safety, disk space, target distinctness, and XDG policy *before* any change.
- **Read-only diagnostics** — `check`, `status`, `list`, `--dry-run`.
- **Dry-run** — prints the plan and changes nothing.
- **Explicit authorisation** — mutating commands require confirmation or `--yes`.
- **Conflict handling** — existing config files are **kept** unless you choose to
  replace them; components you decline are simply not applied.
- **Backups** — anything replaced is backed up first (`~/.config/fedarchy-backups`
  by default; `list` shows them).
- **Rollback** — `rollback` restores the most recent backup. This is a manual
  command, not an automatic undo of a partially failed run; see
  [Known limitations](KNOWN_LIMITATIONS.md).
- **Cancellation** — aborting at the confirmation prompt writes nothing.
- **Failure reporting** — non-zero exit and a clear message.

**What is not claimed:** the installer does not provide a full transactional
rollback of a run that fails midway. Recovery is via the backups listed by
`list`, applied with `rollback`.

---

## 8. Keybindings and the default-bindings flag

If you install Fedarchy's keybindings, the installer can write
`omarchy_default_bindings = false` into your Hyprland config when you decline
Fedarchy's default bindings, so your own entrypoint controls whether they load
(the Lua is guarded with `if _G.omarchy_default_bindings ~= false`).

**Status:** this behaviour is covered by **static tests** in
`tests/installer-ux-test.sh` (it is idempotent and collision-safe). It has **not**
been verified in a live Hyprland session. Treat live keybinding behaviour as
unconfirmed — see [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).

---

## 9. Unsupported components

Fedarchy has **no** fine-grained per-plugin selection component, **no** wallpaper
component (`Wallpapers/` is empty; backgrounds live inside themes), and **no**
whole-machine provisioning components. These are absent, not "coming soon", and
are not offered as installer options.

---

**See also:** [INSTALLATION.md](INSTALLATION.md) ·
[FEATURES.md](FEATURES.md) · [SECURITY.md](SECURITY.md) ·
[TESTING.md](TESTING.md) · [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md)