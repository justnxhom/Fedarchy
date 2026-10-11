# Command Reference

Fedarchy exposes **453** commands in `bin/`, installed to `~/.local/bin`. This
page organises the ones you are likely to use, and describes how to explore the
rest safely.

> This is **not** a "run everything" list. Many commands install packages, modify
> system settings, or need hardware. Read a command's own metadata before running it.

---

## 1. How to read a command's own documentation

Every command carries a self-describing header. This is the authoritative,
per-command documentation — more reliable than any table below:

```bash
head -5 ~/.local/bin/omarchy-theme-set
# #!/bin/bash
# omarchy:summary=Apply an Omarchy theme
# omarchy:args=<theme-name>
```

**437 of 453** commands carry `omarchy:summary` metadata. To search it:

```bash
grep -l 'omarchy:summary' ~/.local/bin/* | wc -l
grep -h 'omarchy:summary' ~/.local/bin/omarchy-theme-* | sort -u
```

Run a command with an unexpected argument or no arguments and it will usually
print its own usage.

---

## 2. Common commands

| Command | What it does | Changes state? | Notes |
|---|---|---|---|
| `omarchy-theme-list` | List available themes | No | Read-only |
| `omarchy-theme-set <name>` | Apply a theme | User config | Reversible by re-applying another |
| `omarchy-theme-current` | Show the active theme | No | Read-only |
| `omarchy-shell ping` | Check the shell is running | No | Read-only |
| `omarchy-restart-shell` | Restart the desktop shell | Session | Disrupts the running shell briefly |
| `omarchy-launch-shell` | Start the shell | Session | Normally autostarted by Hyprland |
| `omarchy-hook <name>` | Run a named hook | Depends on hook | Name is validated; see [BACKEND](BACKEND.md#2-hook-discovery-and-dispatch) |
| `omarchy-plugin-add <id>` | Install a user plugin | User config | Plugin code is **unsandboxed** |
| `omarchy-pkg-add <pkg>` | Install a Fedora package | **System (DNF5)** | Uses package privileges |
| `omarchy-webapp-install <url>` | Create a web app | User config | — |

---

## 3. Command families

Sizes verified from `bin/`. These are *categories*, not endorsements — check a
command's header before running it.

| Family | Count | Purpose | State |
|---|---|---|---|
| `omarchy-theme-*` | 43 | Theme application and per-app theme integration | User config; some use `pkexec` (e.g. browser/GTK policy) |
| `omarchy-install-*` | 40 | Install apps, browsers, editors, AI CLIs, services | **May install packages** |
| `omarchy-remove-*` | 30 | Remove installed components | **Removes things** |
| `omarchy-hw-*` | 28 | Hardware control (backlight, power, etc.) | Runtime/system |
| `omarchy-launch-*` | 25 | Launch applications | No |
| `omarchy-hyprland-*` | 25 | Hyprland window/layout control | Session |
| `omarchy-update-*` | 17 | System and package updates | **System** |
| `omarchy-restart-*` | 16 | Restart shell/session components | Session |
| `omarchy-menu-*` | 14 | Menu integration | User config |
| `omarchy-toggle-*` | 13 | Toggle features on/off | Varies |
| `omarchy-dev-*` | 11 | Developer environment helpers | Varies |
| `omarchy-refresh-*` | 10 | Refresh caches/state | User config |
| `omarchy-plugin-*` | 10 | Plugin management | User config |
| `omarchy-copr-*` | 10 | COPR repository helpers | **System packages** |
| `omarchy-system-*` | 9 | System helpers | Varies |
| `omarchy-audio-*` | 9 | Audio control (WirePlumber) | Runtime |
| `omarchy-capture-*` | 8 | Screen capture | User files |
| `omarchy-plymouth-*` | 7 | Boot splash theme | **System** (may use sudo) |
| `omarchy-agent-*` | 7 | AI/agent integrations | Varies |
| `omarchy-pkg-*` | 6 | DNF5 package operations | **System packages** |
| `omarchy-notification-*` | 6 | Notification handling | Runtime |
| `omarchy-webapp-*` | 5 | Web-app wrappers | User config |
| `omarchy-network-*` / `wifi-*` | 5+ | Network state | Runtime |

Full listing: `ls ~/.local/bin/omarchy-*` or `ls bin/`.

---

## 4. What changes system state

Two tiers, and the distinction matters:

**The installer never elevates.** `scripts/install.sh` contains no `sudo`
execution — only the word in help text and a preflight hint. It writes only
inside `$HOME` and installs no packages.

**Some installed commands do elevate when *you* run them.** 107 commands invoke
`sudo` and 7 use `pkexec`. Examples: package helpers (`omarchy-pkg-*`,
`omarchy-copr-*`), update commands, COPR helpers, and some theme integrations
(browser/GTK policy, stay-awake).

Check before you run:

```bash
grep -l 'sudo\|pkexec' bin/omarchy-*
```

Review them. → [SECURITY.md](SECURITY.md)

---

## 5. Commands that do **not** exist

The following exist in upstream Omarchy but were deliberately **removed** from
Fedarchy as out of scope. Do not expect them; they are not deprecated features:

`omarchy-provision-owner` · `omarchy-provision-user` ·
`omarchy-provision-first-run` · `omarchy-apply-hardware` · `omarchy-apply-system` ·
`omarchy-system-factory-reset` · `omarchy-system-factory-reset-finish` ·
`omarchy-drive-password` · `omarchy-drive-select` · `omarchy-hibernation-setup` ·
`omarchy-hibernation-remove` · `omarchy-hibernation-available` ·
`omarchy-refresh-limine` · `omarchy-snapshot` · `omarchy-dns`

Rationale: [SECURITY.md](SECURITY.md) · [OMARCHY_PORT.md](OMARCHY_PORT.md#5-what-fedarchy-deliberately-does-not-attempt)

---

## 6. Testing commands are not user commands

`tests/*.sh` and `scripts/test.sh` are development tooling, not part of the
installed CLI. → [TESTING.md](TESTING.md)

---

## 7. Coverage caveat

Not every command has a behavioural test. Roughly **30%** of commands are named
in some behavioural test; the rest are covered only by syntax validation.
Syntax-clean does **not** mean behaviour-tested. → [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md)

---

**See also:** [BACKEND.md](BACKEND.md) · [FEATURES.md](FEATURES.md) ·
[SECURITY.md](SECURITY.md) · [TESTING.md](TESTING.md)