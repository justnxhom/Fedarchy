# Omarchy Port and Attribution

This document explains Fedarchy's relationship to
[Omarchy](https://github.com/omacom/omarchy): what was inherited, what was
adapted for Fedora, what Fedarchy deliberately does not attempt, and where
provenance could not be established.

---

## 1. Credit

Fedarchy begins and ends with upstream recognition.

**Omarchy** is the work of **DHH (David Heinemeier Hansson)** and the Omarchy
contributors. The vision — a modern, opinionated, keyboard-driven Linux desktop
that a developer can actually use — is theirs. The shell architecture, the
`omarchy-*` command surface, the theming model, the profile-based installer
concept, and the broad shape of the configuration tree are inherited work.

Fedarchy is grateful for that foundation and does not claim it.

Fedarchy also does **not** claim that DHH personally authored every line of
upstream; that is the work of a contributor community. Nor does it imply that
DHH has reviewed, tested, or approved Fedarchy.

---

## 2. The relationship, stated plainly

- Fedarchy is an **unofficial, Fedora-oriented port and adaptation** of Omarchy.
- It targets an **already-installed, already-working Fedora system**.
- It is **not** an official Omarchy release and carries **no endorsement** from
  DHH or the Omarchy maintainers.
- It does **not** support every upstream feature. Some have been adapted, some
  reworked, and some deliberately excluded (see §5).
- It is **not** a distribution, OS installer, or whole-machine provisioning tool.

### Verified upstream facts

| Fact | Value | How verified |
|---|---|---|
| Upstream website | <https://omarchy.org/> | HTTP 200, 2026-10-11 |
| Upstream repository | <https://github.com/omacom/omarchy> | HTTP 200, 2026-10-11 |
| Upstream licence | MIT | Fetched `LICENSE` from upstream `master` |
| Upstream copyright | `Copyright (c) David Heinemeier Hansson` | Same fetch; reproduced in this repo's [`LICENSE`](../LICENSE) |

---

## 3. What is inherited, and what is adapted

The table below is an honest provenance summary. "Fedarchy adaptation" describes
work verifiable in this repository's source and tests; it does not claim the
concept was invented here.

| Area | Omarchy foundation | Fedarchy adaptation | Evidence |
|---|---|---|---|
| **Desktop shell** | Quickshell-based shell hosting bar, panels, overlays as plugins | Retained and re-verified against Fedora's session/runtime paths; relocation-safe | `shell/`, `shell/README.md`, `tests/lifecycle-shell-test.sh` |
| **Package integration** | Arch-family package manager assumptions | **DNF5-based** package operations | `bin/omarchy-pkg-*`, `tests/backend-fedora.sh` |
| **Installer concept** | Profile-driven setup installer | Reworked into a **component-selecting, home-directory-only** installer with preflight, dry-run, backups, rollback, and no-`sudo` guarantees | `scripts/install.sh`, `scripts/install-components.sh`, `tests/installer-test.sh`, `tests/installer-ux-test.sh` |
| **Environment / paths** | Upstream environment assumptions | Fedora environment handling; `~/.config`-centric deployment; `OMARCHY_PATH` resolution | `default/environment.d/`, `bin/omarchy-launch-shell` |
| **Theming** | Theme model, `omarchy-theme-set` | Retained; hardened for synthetic-home safety and background cleanup | `themes/` (22), `tests/theme-set-test.sh` |
| **Hyprland config** | Hyprland configuration and keybindings | Adapted; explicit note that live keybinding files live under `~/.config/hypr`, not the shipped tree | `docs/hyprland-keybindings.md` |
| **Plugins** | Plugin contract and registry | Retained; documented trust model (unsandboxed, session-privilege code) | `docs/omarchy-plugins.md` |
| **Portability / tests** | Upstream test approach | Expanded: relocation, synthetic homes, hook safety, installer UX, backend regressions | `tests/`, `scripts/test-relocation.sh` |
| **System provisioning** | Upstream ships disk/bootloader/provisioning commands | **Removed** — outside scope | `bin/` (absent), `docs/SECURITY.md` |

### On provenance limits

An exact line-by-line diff against a specific upstream commit cannot be produced
here, because this checkout has **no Git history** (`.git` is absent) and no
pinned upstream version. Claims in the table are therefore grounded in the
**current source and tests in this repository**, not in a reconstructed diff.
Where a distinction between "inherited" and "adapted" cannot be evidenced, it is
described at the level the evidence supports rather than asserted more finely.

---

## 4. Fedora-specific engineering, where evidenced

These are the contributions this port can actually point to in code and tests:

1. **DNF5 package integration** — `bin/omarchy-pkg-*` and menu package actions are
   built for DNF5; backend behaviour is exercised in `tests/backend-fedora.sh`.
2. **A component-selecting, non-privileged installer** — `scripts/install.sh` and
   `scripts/install-components.sh` implement profile/component selection,
   dependency resolution, dry-run, preflight, and backup/rollback, and write only
   under the user's home. Verified by 67 installer tests and 81 installer-UX tests.
3. **Portability corrections** — relocation-safe paths (temporary `HOME` in tests,
   `getent`-based home resolution, script-relative project-root fallback),
   documented in `tests/workspace-layout-test.sh`, `tests/theme-picker-test.py`, and
   `bin/omarchy-provision-owner`'s successor code.
4. **Hook and backend safety** — the hook dispatcher skips documentation files and
   rejects unsafe hook names (`tests/hooks-backend-test.sh`).
5. **Deliberate scope reduction** — removal of system-provisioning and destructive
   commands, with dependent menu/autostart cleanup, leaving only the desktop
   customization surface.

---

## 5. What Fedarchy deliberately does not attempt

The following exist in upstream Omarchy but are **not** part of Fedarchy, because
they belong to whole-machine provisioning and system-level destructive operations
that fall outside "customise an existing Fedora desktop":

`omarchy-provision-owner`, `omarchy-provision-user`, `omarchy-provision-first-run`,
`omarchy-apply-hardware`, `omarchy-apply-system`, `omarchy-system-factory-reset`,
`omarchy-system-factory-reset-finish`, `omarchy-drive-password`,
`omarchy-drive-select`, `omarchy-hibernation-setup`, `omarchy-hibernation-remove`,
`omarchy-hibernation-available`, `omarchy-refresh-limine`, `omarchy-snapshot`,
and `omarchy-dns`.

These are **not** missing headline features and must not be presented as such —
Fedarchy is a desktop port, and machine-level provisioning is simply out of scope.
They are documented for provenance transparency in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and
[docs/SECURITY.md](SECURITY.md).

---

## 6. Respectful framing

Fedarchy credits the upstream project clearly and repeatedly, distinguishes
inherited work from Fedora-specific work, and does not overstate its own novelty
or its relationship to DHH. Where the documentation is unsure, it says so.

---

**See also:** [LICENSE](../LICENSE) · [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) ·
[ARCHITECTURE.md](ARCHITECTURE.md) · [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md)