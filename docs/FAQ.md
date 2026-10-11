# FAQ

Short answers. Each links to the detailed guide instead of repeating it.

---

### What exactly is Fedarchy?

A desktop customization layer for **Fedora**. It installs a Quickshell desktop
shell, a `omarchy-*` command toolkit, themes, Hyprland configuration, and
keybindings — onto a Fedora system you already have.

→ [GETTING_STARTED.md](GETTING_STARTED.md)

### How is it related to Omarchy?

Fedarchy is a **Fedora-oriented port of [Omarchy](https://omarchy.org/)**. It
inherits Omarchy's shell, command surface, theming model, and installer concept,
and adapts them to Fedora's package ecosystem. Fedarchy does not claim the
original work as its own.

→ [OMARCHY_PORT.md](OMARCHY_PORT.md)

### Is Fedarchy an official Omarchy release?

**No.** It is an unofficial port with no endorsement from DHH / David
Heinemeier Hansson or the Omarchy maintainers.

→ [OMARCHY_PORT.md](OMARCHY_PORT.md)

### Does it replace Fedora?

**No.** Fedarchy customises Fedora. It installs no operating system and does not
touch your disk, bootloader, or partitions.

### Does Fedarchy install a different operating system?

**No.** If you want to install Fedora itself, use Fedora's own installer. If you
want your existing Fedora desktop polished, that is what Fedarchy is for.

→ [INSTALLATION.md](INSTALLATION.md)

### Can I keep my current desktop environment?

Only if it is **Hyprland**. Fedarchy is built for Hyprland and does **not** claim
support for KDE Plasma, GNOME, or any other desktop environment.

Fedarchy *does* let you keep your **Hyprland** configuration — see the next
question.

### Do I have to replace my existing Hyprland installation?

**No.** Start from the **`preserve`** profile, which installs the shell, commands,
themes, and app configs but omits `hypr-config` and `keybindings`. Existing files
are kept unless you choose to replace them, and replacements are backed up.

→ [INSTALLER_GUIDE.md](INSTALLER_GUIDE.md#5-profiles)

### Can I keep my own keybindings?

Yes — decline the `keybindings` component, or install it and decline Fedarchy's
defaults (the installer can write `omarchy_default_bindings = false` so your own
entrypoint decides). Note this is **statically tested but not live-verified**.

→ [CONFIGURATION.md](CONFIGURATION.md#6-keybindings)

### Can I select only a few components?

Yes. Choose components individually with `--component`, or start from a profile
and adjust. Dependencies are resolved and **shown** before you agree — e.g.
selecting `keybindings` also pulls in `hypr-config` and `shell`.

```bash
bash scripts/install.sh --dry-run --component shell --component commands
```

→ [INSTALLER_GUIDE.md](INSTALLER_GUIDE.md#6-components)

### Can I preserve my existing application configurations?

Yes. Files that already exist are kept unless you choose to replace them;
anything replaced is backed up first.

→ [CONFIGURATION.md](CONFIGURATION.md#9-conflicts-backups-and-recovery)

### What does the installer actually change?

Files **inside your home directory** — Hyprland config, shell config, themes, app
configs, plus `~/.local/bin` for commands. It never uses `sudo`, never installs
packages, and never touches your disk or bootloader.

→ [SECURITY.md](SECURITY.md#2-installer-safeguards-implemented)

### What does `--dry-run` do?

It works out and prints the plan **without changing anything**. It is the safest
way to see what an install would do. Combine with `--interactive` to preview a
customised install.

### Can I undo an install?

```bash
bash scripts/install.sh list       # backups
bash scripts/install.sh rollback   # restore the most recent one
bash scripts/install.sh uninstall  # remove the deployment
```
Rollback is manual, not an automatic transactional undo of a partial run.

### How do I run the tests?

```bash
bash scripts/test.sh                    # main suite — currently 40/40
bash tests/installer-test.sh            # 67
bash tests/installer-ux-test.sh         # 81
bash tests/hooks-backend-test.sh        # 24
```
They use synthetic homes and mocked system tools, so they are safe to run and do
not touch your real config.

→ [TESTING.md](TESTING.md)

### What has actually been verified?

**Verified:** shell syntax (494 scripts, 0 failures), QML lint (105 files, 0
diagnostics), 40/40 regression suite, installer and backend suites, mocked
behavioural tests, relocation tests.

**Not verified:** installation on real Fedora hardware, live Hyprland keybinding
behaviour, and live PipeWire / UPower / NetworkManager / notification integration.

→ [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md)

### What is intentionally outside the project's scope?

Installing an OS, disk partitioning/formatting/encryption, bootloader
configuration, kernel installation, factory reset, and machine provisioning. 15
upstream commands doing these things were deliberately removed.

→ [SECURITY.md](SECURITY.md#6-removed-operations)

### Does Fedarchy use my `XDG_CONFIG_HOME`?

**Not fully.** The installer pins configuration to `~/.config`. Use the
conventional location.

→ [CONFIGURATION.md](CONFIGURATION.md#xdg-handling--read-this-before-assuming)

### Why is my keybinding edit doing nothing?

Because keybindings live in two trees and only `~/.config/hypr/modules/binds.lua`
is loaded at runtime. Editing the project tree alone changes nothing.

→ [hyprland-keybindings.md](hyprland-keybindings.md)

### Are third-party plugins safe?

They are **trusted, unsandboxed code** running with your session privileges. Only
install plugins you would trust with your account.

→ [omarchy-plugins.md](omarchy-plugins.md)

### Where do I get Fedarchy from?

From source. There is no published package repository or release feed yet.

→ [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md#21-no-published-distribution-channel)

### How do I report a security problem?

There is no established public disclosure channel yet, and none has been
invented. → [SECURITY.md](SECURITY.md#9-reporting-a-problem)

---

**See also:** [GETTING_STARTED.md](GETTING_STARTED.md) ·
[INSTALLATION.md](INSTALLATION.md) · [TROUBLESHOOTING.md](TROUBLESHOOTING.md) ·
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md)