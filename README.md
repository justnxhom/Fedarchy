# Fedarchy

**A Fedora-oriented port of [Omarchy](https://omarchy.org/) that customises a Fedora desktop you already have.**

Fedarchy adapts selected parts of the [Omarchy](https://github.com/omacom/omarchy)
desktop experience to Fedora's package ecosystem and environment. It installs a
Quickshell desktop shell, a command-line toolkit, themes, Hyprland configuration,
and keyboard shortcuts — onto an **existing Fedora installation**.

Fedarchy is **not** a distribution, **not** an operating-system installer, and
**not** an official Omarchy release.

> **Unofficial port.** Fedarchy is a community adaptation with no affiliation to,
> or endorsement from, DHH / David Heinemeier Hansson or the Omarchy maintainers.
> See [docs/OMARCHY_PORT.md](docs/OMARCHY_PORT.md).

---

## Credits

Fedarchy exists because [Omarchy](https://omarchy.org/) exists. The original
vision — a modern, keyboard-driven Linux desktop — is the work of
**DHH (David Heinemeier Hansson)** and the Omarchy contributors. Fedarchy inherits
the shell, the command surface, the theming model, the installer concept, and
much else, and ports them to Fedora.

That upstream work is what makes a project like this possible. Fedarchy's
contribution is the Fedora-specific engineering described in
[docs/OMARCHY_PORT.md](docs/OMARCHY_PORT.md), which also sets out clearly what
Fedarchy does *not* claim as original.

---

## What Fedarchy is — and is not

Fedarchy customises a Fedora desktop that is **already installed and working**.

| Fedarchy does | Fedarchy does not |
|---|---|
| Install a Quickshell desktop shell and panels | Install Fedora or replace your OS |
| Install `omarchy-*` command-line utilities | Partition, format, or encrypt disks |
| Apply themes, Hyprland config, and keybindings | Configure bootloaders or kernel installs |
| Offer ready-made app configuration | Prepare a machine for a new owner |
| Let you pick which components to apply | Provision or take over your machine wholesale |

Fedarchy targets **Hyprland**. It does not claim support for KDE Plasma, GNOME,
or any other desktop environment.

Because the setup installer offers real component selection, Fedarchy does not
force every preference onto your desktop. See
[docs/GETTING_STARTED.md](docs/GETTING_STARTED.md) for what each piece changes.

---

## Features

### Desktop shell (Quickshell)
A single long-running [Quickshell](https://quickshell.org/) instance hosts the
bar, panels, and overlays as plugins — audio, network/Wi-Fi, Bluetooth, power,
clock, weather, monitor, and more.
→ [docs/FEATURES.md](docs/FEATURES.md)

### Command-line toolkit
453 `omarchy-*` utilities for themes, hardware, packages, plugins, web apps, and
desktop maintenance.
→ [docs/COMMAND_REFERENCE.md](docs/COMMAND_REFERENCE.md)

### Themes
22 bundled themes, each with colours, backgrounds, and per-application colour
maps (Neovim, VS Code, icon themes), switchable with `omarchy-theme-set`.
→ [docs/CONFIGURATION.md](docs/CONFIGURATION.md)

### Hyprland integration
Window behaviour, layouts, and monitors, with an optional keybindings component.
→ [docs/hyprland-keybindings.md](docs/hyprland-keybindings.md)

### Optional components
Choose only the shell, only the commands, add themes, keybindings, app configs,
or bar widgets — or start from a profile and adjust it.
→ [docs/INSTALLER_GUIDE.md](docs/INSTALLER_GUIDE.md)

### Developer facilities
A regression suite (40 tests), installer test suites, portability/relocation
checks, and a plugin contract.
→ [docs/TESTING.md](docs/TESTING.md)

---

## Quick start

Fedarchy is currently distributed as source. There is **no public package
repository or release feed** yet — see [docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md).
From a local checkout (`~/Fedarchy` in the examples below):

```bash
# 1. See what the installer supports — read-only, changes nothing.
bash scripts/install.sh --help

# 2. Run the project's test suite — read-only.
bash scripts/test.sh

# 3. Preview an installation plan — changes nothing.
bash scripts/install.sh --dry-run --profile recommended

# 4. Guided installation (choose components, review, confirm).
bash scripts/install.sh --interactive
```

Every command above is safe to run for inspection. Only step 4 modifies your
system, and even then it writes only inside your home directory, never uses
`sudo`, and never installs packages. The full walkthrough is in
[docs/INSTALLATION.md](docs/INSTALLATION.md).

---

## Installation maturity — what is actually verified

Honesty about evidence matters more than an impressive checklist.

| Evidence | Status |
|---|---|
| Shell syntax (494 shell scripts) | ✅ 0 failures |
| QML lint (105 files) | ✅ 0 diagnostics |
| Main regression suite | ✅ **40/40 passing** |
| Installer suites | ✅ 67 + 81 + 24 tests passing |
| Behavioural tests using **mocked** system commands | ✅ Extensive |
| Relocation / synthetic-home tests | ✅ Included |
| Real Fedora installation on separate hardware | ❌ **Not yet performed** |
| Live Hyprland / PipeWire / UPower behaviour | ⚠️ **Not runtime-verified** |

The automated tests use mocks and temporary directories. They are strong evidence
that the *logic* is correct, but they are **not** proof of live desktop
integration or of a successful installation on real hardware. The full picture,
including every gap, is in [docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md).

---

## Documentation

**Getting started**
· [GETTING_STARTED.md](docs/GETTING_STARTED.md) — what it is, before you change anything
· [INSTALLATION.md](docs/INSTALLATION.md) — full install onto an existing Fedora
· [INSTALLER_GUIDE.md](docs/INSTALLER_GUIDE.md) — every option, profile, and component

**Using Fedarchy**
· [FEATURES.md](docs/FEATURES.md) — feature catalog
· [CONFIGURATION.md](docs/CONFIGURATION.md) — themes, keybindings, paths, env vars
· [COMMAND_REFERENCE.md](docs/COMMAND_REFERENCE.md) — the CLI surface
· [FAQ.md](docs/FAQ.md) · [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

**Understanding the project**
· [ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the pieces fit
· [BACKEND.md](docs/BACKEND.md) — internal implementation
· [OMARCHY_PORT.md](docs/OMARCHY_PORT.md) — upstream relationship and attribution

**Contributing and development**
· [DEVELOPMENT.md](docs/DEVELOPMENT.md) · [TESTING.md](docs/TESTING.md)
· [CONTRIBUTING.md](CONTRIBUTING.md) · [AGENTS.md](AGENTS.md)

**Trust and transparency**
· [SECURITY.md](docs/SECURITY.md) · [KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md)
· [LICENSE](LICENSE) · [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) · [CHANGELOG.md](CHANGELOG.md)

---

## Status and scope

Fedarchy is a **desktop customization layer**, not a system installer. Commands
for whole-machine provisioning and destructive disk/bootloader operations that
exist upstream are deliberately **not** shipped here; see
[docs/SECURITY.md](docs/SECURITY.md). Where the project's behaviour is unverified,
the documentation says so rather than claiming more than the tests prove.

---

*Fedarchy is an unofficial port of [Omarchy](https://github.com/omacom/omarchy),
© DHH / David Heinemeier Hansson, MIT licensed. See [LICENSE](LICENSE) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).*