# Security and Safety

An honest account of what Fedarchy safeguards, what it cannot promise, and where
the real risk sits.

> This document describes the **current implementation**, not an aspiration.

---

## 1. Scope as a safety property

Fedarchy is a **desktop customization layer for a Fedora system you already have**.

It does not install an operating system, partition disks, format or encrypt
storage, configure bootloaders, install kernels, or prepare a machine for a new
owner. The upstream commands that did those things were **deliberately removed**
(see §6).

---

## 2. Installer safeguards (implemented)

| Safeguard | Where | What it does |
|---|---|---|
| **Preflight** | `scripts/install.sh` | Checks OS, non-root, required commands, source tree integrity, target safety, disk space, target/source distinctness, XDG policy — **before any change** |
| **No `sudo`** | `scripts/install.sh` | The installer never executes `sudo`. Only the word appears in help text and a preflight hint. It installs no packages |
| **Home-only writes** | `scripts/install.sh` | Everything lands under `$HOME` |
| **Dry run** | `--dry-run` | Prints the plan, changes nothing |
| **Read-only diagnostics** | `check`, `status`, `list`, `--check`/`--doctor` | Inspect without mutating |
| **Explicit authorisation** | `--yes` / interactive confirm | Mutating commands need consent; non-interactive without `--yes` exits non-zero rather than assuming it |
| **Conflict handling** | installer | Existing config files are **kept** unless you choose to replace them |
| **Backups** | installer | Replacements are backed up before being overwritten (`~/.config/fedarchy-backups`, or `FEDARCHY_BACKUP_DIR`) |
| **Rollback** | `rollback` | Restores the most recent backup (manual) |
| **Dependency resolution** | `install-components.sh` | Dependency components are resolved and **shown** before you agree |

`--yes` does **not** bypass preflight, safety checks, or required decisions.

---

## 3. Hook dispatch safety

`bin/omarchy-hook <name>` treats the name as untrusted:

- Rejects empty names, names containing `/`, and bare `.`/`..`, so a name cannot
  escape `~/.config/omarchy/hooks/`.
- Runs **only** executable files; documentation files (`README*`, `LICENSE`,
  `*.md`, `*.txt`, `*.rst`) in a `.d/` directory are skipped.
- Tested in `tests/hooks-backend-test.sh`, including assertions that mocked
  privileged operations are never reached.

→ [BACKEND.md](BACKEND.md#2-hook-discovery-and-dispatch)

---

## 4. The real privileged surface: installed commands

**The installer does not elevate, but some commands you later run do.**

- **107** commands invoke `sudo`
- **7** use `pkexec`: `omarchy-dev-install-ydoo`,
  `omarchy-install-chromium-claude`, `omarchy-launch-docker-tui`,
  `omarchy-theme-set-browser`, `omarchy-theme-set-browser-policy`,
  `omarchy-update-stay-awake`, `omarchy-windows-vm`

Most are ordinary user-initiated operations: DNF5 package management, per-app
installers, adding your user to a group (`usermod -aG`, used for `input`, `docker`,
`nordvpn`), or restoring boot/SDDM defaults.

Inspect before you run:

```bash
grep -l 'sudo\|pkexec' bin/omarchy-*
head -3 bin/<command>          # summary + args metadata
```

**Reasonable precautions:**
- Prefer `omarchy-theme-set` over the browser/GTK policy variants if you do not
  want a system-wide policy change.
- Read a command before running it as part of an "install everything" sweep.
- `install-*` and `remove-*` families genuinely change packages; use them
  deliberately.

---

## 5. Package-manager behaviour

Fedarchy's package integration is **DNF5-based**. Package commands (`omarchy-pkg-*`,
`omarchy-copr-*`, `omarchy-update-*`) operate on your system, not your home
directory. `omarchy-update-orphan-pkgs` was hardened so a **failed** DNF query is
reported rather than silently appearing as "no orphans" — covered by
`tests/backend-fedora.sh`.

---

## 6. Removed operations

These upstream commands are **not shipped**, and no menu, dispatcher, or
autostart entry can reach them:

`omarchy-provision-owner` · `omarchy-provision-user` · `omarchy-provision-first-run` ·
`omarchy-apply-hardware` · `omarchy-apply-system` · `omarchy-system-factory-reset` ·
`omarchy-system-factory-reset-finish` · `omarchy-drive-password` · `omarchy-drive-select` ·
`omarchy-hibernation-setup` · `omarchy-hibernation-remove` · `omarchy-hibernation-available` ·
`omarchy-refresh-limine` · `omarchy-snapshot` · `omarchy-dns`

Dependent menu entries, an autostart entry, and `default/bash/fns/drives` were
removed with them. Verified: no references remain in `bin/`, `shell/`, `default/`,
`config/`, or `scripts/`.

Rationale: [OMARCHY_PORT.md](OMARCHY_PORT.md#5-what-fedarchy-deliberately-does-not-attempt)

---

## 7. Plugins are trusted code

Third-party plugins run **unsandboxed** with your session privileges. The host
limits exposed objects, but a plugin can reach your files, processes, D-Bus
session, and network. Install plugins you would trust with your account.
→ [omarchy-plugins.md](omarchy-plugins.md)

---

## 8. What is **not** claimed

- Fedarchy is **not** "secure because the tests pass". Passing tests show logic,
  not safety of the whole system.
- There is **no** automatic transactional rollback if a run fails midway;
  recovery is via the backups listed by `list`.
- `themes/*/backgrounds/` image provenance is **not fully verified** →
  [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
- The installer is **not** XDG-portable: `CONFIG_HOME` is pinned to `~/.config`.
- Live desktop behaviour is **unverified** → [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).

---

## 9. Reporting a problem

Fedarchy is not yet publicly hosted and has **no established public security
contact or disclosure channel**. Do not invent one.

Until a real channel exists, report issues through whatever route the project
maintainer provides in person. When the project is published, a disclosure
process should be added here — **this gap is stated rather than papered over.**

---

**See also:** [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) ·
[INSTALLER_GUIDE.md](INSTALLER_GUIDE.md) · [COMMAND_REFERENCE.md](COMMAND_REFERENCE.md)