# Installation

Installing Fedarchy onto a **Fedora system you already have installed**.

> Fedarchy is a desktop customization layer. It is not a distro, not an OS
> installer, and not a whole-machine provisioning tool. If you are looking to
> install Fedora itself, stop here — see [FAQ](FAQ.md#does-fedarchy-install-a-different-operating-system).

---

## 1. Before you start

### You need

| Requirement | Why |
|---|---|
| An already-installed, working **Fedora** desktop | Fedarchy customises an existing system |
| **Hyprland** | Fedarchy's shell is built for Hyprland (see [FAQ](FAQ.md#can-i-keep-my-current-desktop-environment)) |
| Bash, `rsync`, `realpath`, `date`, `cmp`, `readlink` | The installer's own preflight requires these |
| A source checkout of Fedarchy | Fedarchy is not yet published to a package repo |

The installer never installs system packages. If preflight reports a missing
dependency, it prints the exact `dnf5` command for you to run yourself.

### You do not need (and Fedarchy will not do)

- A spare disk, a bootable USB, or a partitioner
- Bootloader configuration
- Disk encryption
- A fresh/blank machine

---

## 2. Get the source

Fedarchy is currently distributed as **source only**. There is no public package
repository, release feed, or stable clone URL yet — see
[Known limitations](KNOWN_LIMITATIONS.md#21-no-published-distribution-channel).

For now you need a local checkout. In the examples below it lives at
`~/Fedarchy`:

```bash
cd ~/Fedarchy
ls bin scripts shell   # confirm you have the source tree
```

If you obtained Fedarchy some other way (a bundle, an archive), unpack it
somewhere stable and `cd` into the project root. The installer deploys
*whichever checkout it is run from*.

---

## 3. Look before you leap

All three of these are **read-only**. None modify your system.

```bash
# What can the installer do?
bash scripts/install.sh --help

# Does the project's test suite pass on this machine?
bash scripts/test.sh

# What exactly would be installed, and where?
bash scripts/install.sh --dry-run --profile recommended
```

Read the dry-run plan carefully. It is the single best way to understand what
Fedarchy will touch before you let it.

---

## 4. Choose what you want

Fedarchy offers real component selection so it does not impose every preference
on you.

- **Profiles** are starting points (`minimal`, `recommended`, `preserve`,
  `custom`). See [Installer guide → Profiles](INSTALLER_GUIDE.md#5-profiles).
- **Components** can be added or removed individually.
- If you already have a Hyprland setup you care about, start from the
  `preserve` profile (shell + commands + themes + app configs) so you do not
  overwrite your window/keybinding config by surprise.

To see every option, see the [Installer guide](INSTALLER_GUIDE.md).

---

## 5. Install

The supported interactive path:

```bash
bash scripts/install.sh --interactive
```

This walks you through profile selection, lets you adjust components, shows the
resolved plan (including any dependencies pulled in automatically), and asks for
confirmation. Nothing is written until you confirm.

For a scripted/non-interactive run (e.g. after you have tested the plan):

```bash
bash scripts/install.sh --profile recommended --yes
```

`--yes` authorises the mutation; it does **not** skip preflight or safety
checks.

> A note on profile/component precedence: if you pass **both** `--profile` and
> `--component`, the profile is used and `--component` is ignored. Use
> `--component` on its own to install exactly those components.

---

## 6. Verify

```bash
# Deployed tree matches the runtime contract?
bash scripts/install.sh check

# What is deployed?
bash scripts/install.sh status

# Backups available for rollback?
bash scripts/install.sh list
```

To use the shell, start it via your Hyprland session (the autostart entry is part
of the `shell` component), or try a command from a terminal:

```bash
omarchy-theme-set catppuccin    # switch theme
omarchy-shell ping              # is the shell up?
```

---

## 7. When preflight fails

The installer checks your OS, that you are not running it as root, that its
required commands exist, that the source tree is intact, that the target path is
safe, that there is enough disk space, and that the target is distinct from the
source — *before* changing anything.

If preflight reports a missing command, it prints the `dnf5 install` line to run
yourself. If it complains about the target path, see
[Troubleshooting](TROUBLESHOOTING.md).

---

## 8. Undo

```bash
bash scripts/install.sh rollback    # restore the most recent backup
bash scripts/install.sh uninstall   # remove the deployment
bash scripts/install.sh list        # see what backups exist
```

Anything the installer replaces is backed up before it is replaced. See
[Installer guide → Safe behaviour](INSTALLER_GUIDE.md#7-safe-behaviour) for what
rollback does and does not cover.

---

## 9. Verification status — please read

Fedarchy has **not** yet been validated by a full installation onto a separate,
real Fedora machine. What *is* verified:

- Installer logic is covered by 67 installer tests and 81 installer-UX tests
  (using mocked/sandboxed environments).
- Shell syntax, QML lint, and the 40-test regression suite pass.

What is **not** verified: a clean end-to-end install on physical hardware, and
live desktop-service integration. Treat your first install as an informed trial,
consult the dry-run plan, and know how to roll back. The full list is in
[Known limitations](KNOWN_LIMITATIONS.md).

---

**See also:** [GETTING_STARTED.md](GETTING_STARTED.md) ·
[INSTALLER_GUIDE.md](INSTALLER_GUIDE.md) · [TROUBLESHOOTING.md](TROUBLESHOOTING.md) ·
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md)