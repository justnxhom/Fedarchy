# Changelog

All notable changes to Fedarchy.

**This project has no release history.** There is no Git repository, no version
tags, no published releases, and no identifiable commit or author history to draw
on. Rather than invent a plausible-looking changelog, this document records the
**verified state of the work to date** under `Unreleased`.

Dates below are the dates the work was performed and verified, not release dates.

---

## Unreleased

### Scope: desktop customization for an existing Fedora system

- Established Fedarchy as an **unofficial Fedora-oriented port of
  [Omarchy](https://github.com/omacom/omarchy)**, explicitly **not** an official
  release and **not** endorsed by DHH or the Omarchy maintainers.
- Documented the inherited-vs-adapted relationship, with provenance verified
  against the upstream repository and its MIT licence.

### Installation

- Rebuilt `scripts/install.sh` as a **component-selecting, home-directory-only**
  installer with preflight checks, dry-run, explicit authorisation, conflict
  handling, backups, and rollback.
- Added `scripts/install-components.sh` with a pipe-delimited `COMPONENT_SPECS`
  manifest, dependency resolution, and four profiles (`minimal`, `recommended`,
  `preserve`, `custom`).
- Installer made idempotent and collision-safe for backups, including the
  `omarchy_default_bindings = false` keybinding flag handling.
- **The installer never executes `sudo` and never installs packages.** Only the
  word `sudo` appears, in help text and a preflight dependency hint.

### Portability

- Made the tree relocatable: tests now use temporary `HOME`/`XDG_STATE_HOME`
  instead of the real home directory.
- Replaced `/home/$username` assumptions with `getent`-based home resolution.
- Made the theme picker resolve `Path.home()` and skip cleanly when absent
  instead of failing on a hard-coded path.
- Added a script-relative project-root fallback for the migration helper.

### Fedora integration

- DNF5-based package operations, with `omarchy-update-orphan-pkgs` hardened so a
  **failed** query is reported rather than appearing as an empty result.

### Safety and removal

- **Removed 15 upstream commands** as outside the project's desktop scope:
  `omarchy-provision-owner`, `omarchy-provision-user`,
  `omarchy-provision-first-run`, `omarchy-apply-hardware`, `omarchy-apply-system`,
  `omarchy-system-factory-reset`, `omarchy-system-factory-reset-finish`,
  `omarchy-drive-password`, `omarchy-drive-select`, `omarchy-hibernation-setup`,
  `omarchy-hibernation-remove`, `omarchy-hibernation-available`,
  `omarchy-refresh-limine`, `omarchy-snapshot`, and `omarchy-dns`.
- Removed the dependent menu entries, autostart entry, and
  `default/bash/fns/drives`. Verified no surviving references in `bin/`, `shell/`,
  `default/`, `config/`, or `scripts/`.
- Removed system DNS configuration from the network panel, the menu model, and the
  main menu, preserving the panel's remaining functionality (tested).
- `omarchy-hook` now skips documentation files in `.d/` hook directories and
  rejects unsafe hook names (`..`, `/`, empty).
- `omarchy-theme-set` background cleanup timers no longer inherit stdout, fixing a
  hang under synthetic homes.
- Removed 38 redundant narration comments across 21 shell files with **no
  executable-code changes**.

### Testing

- Added installer, installer-UX, hooks/backend, relocation, and lifecycle suites.
- **Current verified results:** main suite **40/40**, installer **67/67**,
  installer-UX **81/81**, hooks/backend **24/24**, `bash -n` **488 scripts / 0
  failures**, `qmllint` **105 files / 0 diagnostics**, Python compiles.
- All system-changing tests use mocks, synthetic homes, and temporary
  destinations. No test touches the real `$HOME`, `$OMARCHY_PATH`, `sudo`, or
  hardware.

### Documentation

- Added a full documentation suite: `README.md` plus `docs/` covering getting
  started, installation, installer guide, features, architecture, backend,
  porting/attribution, configuration, command reference, testing, development,
  troubleshooting, FAQ, security, and known limitations.
- Added `AGENTS.md` (project-specific guidance for AI agents), `CONTRIBUTING.md`,
  `LICENSE`, `THIRD_PARTY_NOTICES.md`, and this changelog.

### Known gaps at this point

Not fixed in this period, and documented rather than hidden:

- No installation has been validated on real, separate Fedora hardware.
- Live Hyprland keybinding behaviour is statically tested but **not** live-verified.
- Live PipeWire / UPower / NetworkManager / notification integration is unverified.
- ShellCheck is unavailable, so no shellcheck-level analysis has run.
- QML linting is syntax-only; Quickshell imports are unresolvable outside a
  runtime.
- No published distribution channel, no repository, and no CI.
- Theme asset provenance is not fully verified per file.
- No named copyright holder for the Fedora-specific modifications, and no public
  security-disclosure channel.

→ [docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md)

---

## Attribution

Much of this project — the shell, the command surface, the theming model, the
installer concept — originates in **Omarchy** by **DHH (David Heinemeier
Hansson)** and its contributors, MIT licensed.

Fedarchy is an unofficial adaptation. See
[docs/OMARCHY_PORT.md](docs/OMARCHY_PORT.md),
[LICENSE](LICENSE), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).