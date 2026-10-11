# Known Limitations

An honest, evidence-based list of what is incomplete or unverified. Each entry
says what is missing, what still works, and what would resolve it.

*Re-checked against the current source and test results on 2026-10-11.*

---

## 1. Verification gaps

### 1.1 No real-Fedora installation testing — **user impact: high**

- **Missing:** Fedarchy has never been installed end-to-end on a separate,
  physical Fedora machine.
- **What works:** all installer logic is covered by 67 installer tests and 81
  installer-UX tests in sandboxed environments.
- **Evidence:** `tests/installer-test.sh`, `tests/installer-ux-test.sh`.
- **Not tested:** real filesystem layouts, real `$HOME` contents, real
  permissions, real conflicts with a live Hyprland install.
- **Workaround:** run `--dry-run` first, read the plan, and know how to `rollback`.
- **To resolve:** perform the procedure in [TESTING.md](TESTING.md#7-live--real-system-verification--not-yet-performed)
  on a throwaway machine and record the outcome.

### 1.2 Live desktop integrations unverified

PipeWire/WirePlumber (audio panel), UPower (power/battery), the notification
daemon, and NetworkManager (network/Wi-Fi panel) behaviour is **not
runtime-verified**. The panels read real service state; the tests mock the
services.

### 1.3 Hyprland keybindings — static checks only

The `omarchy_default_bindings = false` mechanism and the two-tree keybinding
layout are covered by **static tests** only. They have **not** been confirmed in
a live Hyprland session. Treat live keybinding behaviour as unconfirmed.
→ [hyprland-keybindings.md](hyprland-keybindings.md)

---

## 2. Scope and packaging

### 2.1 No published distribution channel

Fedarchy has **no package repository, release feed, or stable clone URL.** Source
is distributed as a checkout. Nothing in this documentation invents a repository
address. Until one exists, the documented workflow is local source.

### 2.2 No CI

There is no `.github/`, no pipeline, and no repository (`.git` is absent). Test
results quoted in this documentation were produced **manually**. There is no
automated gate on changes, and no badges are shown anywhere for that reason.

### 2.3 Whole-machine provisioning is intentionally absent

Disk partitioning, encryption, bootloader configuration, kernel installation, and
factory reset are **out of scope by design** — not missing features. 15 upstream
commands were removed for this reason. → [SECURITY.md](SECURITY.md)

---

## 3. Tooling and analysis gaps

### 3.1 ShellCheck unavailable

ShellCheck is not installed on the primary development system, so no
shellcheck-level analysis has been run. `bash -n` catches syntax errors only —
it cannot detect quoting bugs, word-splitting hazards, or unused variables.

**To resolve:** install ShellCheck and run it across `bin/` and `scripts/`.

### 3.2 QML validation is syntax-only

`qmllint` emits **no diagnostics** across 105 files, but it cannot resolve
Quickshell module imports outside a Quickshell runtime (it exits with code 255
and no output when imports are unresolvable). So:

- Syntax/parse errors **are** caught.
- Full type checking against Quickshell's QML modules is **not** performed.

> **Correction worth recording:** earlier reports claimed "0 QML errors" using
> `qmllint --bare`. That flag is **not supported** by this build — the command
> failed immediately and reported nothing, so those results were false negatives.
> The figures in this document come from the correct invocation
> (`qmllint -I shell <file>`).

### 3.3 Behavioural test coverage is partial

Roughly **30%** of commands (140/453) are named in some behavioural test; the
rest are covered by syntax validation only. The metric is a weak proxy, but the
honest summary is that **most commands have no dedicated behavioural test**.
→ [TESTING.md](TESTING.md#3-coverage-measured-honestly)

---

## 4. Functional limitations

### 4.1 XDG configuration-root support is not comprehensive

The installer pins `CONFIG_HOME="$HOME/.config"`. Moving your config via
`XDG_CONFIG_HOME` can leave the shell reading a different tree than you
configured. Use the conventional location.
→ [CONFIGURATION.md](CONFIGURATION.md#xdg-handling--read-this-before-assuming)

### 4.2 No fine-grained widget selection

Bar widgets are not individually selectable at install time; the `bar-widgets`
component is one unit. Per-widget toggling is done through
`~/.config/omarchy/shell.json`, not the installer's component model.

### 4.3 Empty asset directories

`assets/` and `Wallpapers/` exist but are **empty**. Backgrounds live inside
`themes/*/backgrounds/`. Nothing is available from those two directories.

### 4.4 Installer precedence quirk

If you pass **both** `--profile` and `--component`, the profile is used and
`--component` is silently ignored (the installer checks the profile first). Use
`--component` on its own for exact selection. This is current behaviour, not a
recommendation.
→ [INSTALLER_GUIDE.md](INSTALLER_GUIDE.md#combining-options)

### 4.5 No transactional rollback

`rollback` restores the most recent backup. It is **not** an automatic undo of a
run that failed partway. Recovery is manual.

---

## 5. Provenance and legal

### 5.1 Theme asset licences not fully verified

The bundled background images, icon themes, and previews were inherited from
Omarchy. It has **not** been verified that every individual file was covered by
the upstream repository's MIT notice, or whether any third party holds separate
rights in a specific image. **No licence has been invented.**

**If you redistribute Fedarchy**, review `themes/*/backgrounds/` and obtain
permission or replace anything you cannot confirm.
→ [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)

All 22 bundled theme directories match upstream Omarchy theme-for-theme (Fedarchy
adds none of its own and omits only upstream's `starship`), so this question is
inherited rather than newly introduced — but it is still unresolved here.

### 5.1a Icon font embeds traced third-party brand logos — **release blocker**

`default/fonts/omarchy/omarchy.ttf` contains redrawn brand logos for 14
third-party products, and `hermes.svg` carries an explicit
`Copyright (c) 2025 Nous Research`. Several glyphs were *traced* rather than
copied from an official vector, and no licence file ships with the font.

This raises a **trademark/redistribution question independent of the background
images**, and was identified during the pre-release audit. It needs a
maintainer decision before the repository is made public.
→ [THIRD_PARTY_NOTICES.md §2.2](../THIRD_PARTY_NOTICES.md#22-icon-font--defaultfontsomarchyomarchyttf-traced-third-party-logos)

### 5.2 No named copyright holder for Fedora-specific changes

The [`LICENSE`](../LICENSE) preserves the upstream MIT notice as required, and
states that no copyright holder has yet been designated for the Fedora-specific
modifications. **One is deliberately not invented.** Until a holder is
designated, this is an open legal question for the maintainer to resolve.

### 5.3 No security contact

There is no established public security-disclosure channel, and none has been
fabricated. → [SECURITY.md](SECURITY.md#9-reporting-a-problem)

---

## 6. What is *not* a limitation

These are **intentional scope decisions**, not defects, and are not "missing
features":

- No OS installation, disk partitioning, encryption, or bootloader configuration.
- No provisioning or factory reset.
- No KDE Plasma or GNOME support — Fedarchy targets Hyprland.
- No per-plugin installer component — plugins are managed with
  `omarchy-plugin-*` at runtime.

---

**See also:** [TESTING.md](TESTING.md) · [SECURITY.md](SECURITY.md) ·
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) ·
[OMARCHY_PORT.md](OMARCHY_PORT.md)