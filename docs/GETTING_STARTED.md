# Getting Started

A short, jargon-light tour of Fedarchy — read this before you change anything.

---

## What Fedarchy is

Fedarchy is a **desktop customization layer for Fedora**. Think of it as a
carefully curated set of desktop niceties — a status bar, a set of panels, a
large command toolkit, themes, and sensible Hyprland defaults — that you can
apply to a Fedora desktop you already use.

## What it changes, and what it does not

**It changes** things *inside your home directory*: your Hyprland config files,
your shell/panel configuration, your themes, your keybindings file, and a handful
of app configs.

**It does not change**: your operating system, your disk, your bootloader, or
your machine's identity. Fedarchy does not install Fedora, format anything, or
take over your computer. Its setup installer never uses `sudo` and never installs
system packages.

If you want to *replace* your operating system, this is the wrong tool. If you
want your existing Fedora desktop to feel like a polished, keyboard-driven
workspace — this is exactly what it is for.

## Which desktop it targets

Fedarchy is built for **Hyprland**. It does not claim support for KDE Plasma,
GNOME, or other desktop environments. See
[FAQ → Can I keep my current desktop environment?](FAQ.md#can-i-keep-my-current-desktop-environment).

## The pieces you can choose

Fedarchy does **not** apply everything by force. You pick:

| Component | What it gives you |
|---|---|
| **shell** | The Quickshell desktop shell: bar, panels, overlays |
| **commands** | The `omarchy-*` command-line tools |
| **themes** | 22 bundled themes |
| **hypr-config** | Window behaviour and layout defaults for Hyprland |
| **keybindings** | Fedarchy's keyboard shortcuts |
| **app-configs** | Ready-made config for terminals, browsers, and other apps |
| **bar-widgets** | Which widgets appear on your bar |

There are also **profiles** (`minimal`, `recommended`, `preserve`, `custom`) as
convenient starting points — but you can add or drop any component afterwards.
Full detail in the [Installer guide](INSTALLER_GUIDE.md).

## Inspect before you install

Nothing below modifies anything:

```bash
cd ~/Fedarchy
bash scripts/install.sh --help              # what it can do
bash scripts/install.sh --dry-run --profile recommended   # the plan
bash scripts/test.sh                        # does the suite pass here
```

## Then install

```bash
bash scripts/install.sh --interactive
```

You'll pick a profile, adjust components, review the plan, and confirm. See
[Installation](INSTALLATION.md) for the full walkthrough and how to undo it.

## Where to go next

- Ready to install? → [INSTALLATION.md](INSTALLATION.md)
- Want to know what each part does? → [FEATURES.md](FEATURES.md)
- Curious how it works? → [ARCHITECTURE.md](ARCHITECTURE.md)
- Something broke? → [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Common questions → [FAQ.md](FAQ.md)

---

## A few terms, defined

- **Quickshell** — the lightweight, Qt/QML-based tool Fedarchy uses to draw its
  bar, panels, and overlays. [quickshell.org](https://quickshell.org/)
- **Hyprland** — a Wayland compositor (window manager) for Linux; the desktop
  environment Fedarchy is built for.
- **Wayland** — the modern Linux display protocol that Hyprland uses.
- **Component** — one selectable piece of Fedarchy (see the table above).
- **Profile** — a preset starting set of components.
- **Dry run** — ask the installer what it *would* do without changing anything.