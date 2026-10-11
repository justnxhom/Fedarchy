# Development Guide

How to work on Fedarchy. Every path and command below is real and current.

> Safety rules for AI agents working in this tree are in [`../AGENTS.md`](../AGENTS.md).

---

## 1. Get oriented

```bash
cd ~/Fedarchy
bash scripts/test.sh          # must be 40/40 before you start
```

Know the shape before you edit:

| Directory | Responsibility |
|---|---|
| `bin/` | 453 standalone `omarchy-*` commands |
| `shell/` | Quickshell shell: QML + JS, services, plugins |
| `default/` | **Runtime resources** (hypr Lua, wayland session, bash, systemd) |
| `config/` | **User-configuration templates** → `~/.config` |
| `themes/` | 22 theme definitions |
| `scripts/` | Installer, test runner, dev-run, relocation test |
| `tests/` | 35 test files |

**`default/` vs `config/` is the distinction most worth internalising.** They look
similar and are not interchangeable — see
[ARCHITECTURE.md](ARCHITECTURE.md#default-vs-config--an-important-distinction).

---

## 2. Run the shell while developing

```bash
bash scripts/dev-run.sh      # development runner
omarchy-restart-shell        # restart after changes
omarchy-shell ping           # is it alive?
```

> The running shell **hot-reloads** when files under `shell/` change. A syntax
> error will take the UI down until you fix it. That is expected, not a bug.

---

## 3. Add a command

A command is a standalone executable in `bin/`. The minimum viable shape:

```bash
#!/bin/bash
# omarchy:summary=One line describing what it does
# omarchy:args=[required] [optional]

set -euo pipefail
# ... work ...
```

Conventions:
- Self-describing metadata header (`omarchy:summary`, `omarchy:args`) — 437 of
  453 commands have one; keep that ratio.
- Quote variables; validate arguments; fail loudly with a non-zero exit.
- Prefer sourcing shared helpers over re-implementing them.
- Make the command safe under a synthetic `HOME` if it writes files.

Then verify:
```bash
bash -n bin/omarchy-yourcommand
bash scripts/test.sh
```

---

## 4. Add or modify a shell component

The shell is QML + JS under `shell/`.

- **Plugin** (bar widget, panel, overlay): create it under `shell/plugins/<name>/`.
  First-party plugins live here; user plugins live in
  `~/.config/omarchy/plugins/<plugin-id>/`.
- **Service** (long-lived singleton): put it in `shell/services/`. Services exist
  **once per session**, so shared state belongs here, not inside a plugin.
- **Shared UI**: `shell/Ui/` and `shell/Commons/`.

Validate:
```bash
qmllint -I shell shell/plugins/<name>/*.qml
```
Remember `qmllint` resolves Quickshell imports only inside a runtime → see
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md#32-qml-validation-is-syntax-only).

---

## 5. Modify the installer component manifest

The manifest is `COMPONENT_SPECS` in `scripts/install-components.sh`, pipe-delimited:

```
id | required | depends-on | destination | what | why
```

Profiles live in `profile_components()` in the same file. To add a component:

1. Add its row to `COMPONENT_SPECS`.
2. Add it to any profile that should include it.
3. Wire its copy step in `scripts/install.sh`.
4. **Update the tests** — `tests/installer-ux-test.sh` asserts the component set.

```bash
bash tests/installer-test.sh
bash tests/installer-ux-test.sh
```

→ [INSTALLER_GUIDE.md](INSTALLER_GUIDE.md#6-components)

---

## 6. Themes

A theme is a directory under `themes/` containing `colors.toml`, `backgrounds/`,
`icons.theme`, `neovim.lua`, `vscode.json`, `preview.png`, `unlock.png`.

```bash
bash tests/theme-set-test.sh
bash tests/theme-install-test.sh
```

**Provenance:** new assets need a known source and licence. Do not add an image
whose origin you cannot state — see
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

---

## 7. Add a regression test

Tests go in `tests/`. Two conventions:

**Shell suite** (self-contained, prints a result):
```bash
#!/bin/bash
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# ... assertions ...
```
Register it in `scripts/test.sh` with `run_suite "name" bash tests/your-test.sh`.

**Isolation is mandatory:**
- Use a temp `HOME`/`XDG_STATE_HOME` — never the real one.
- Write to a temp directory — never to `$OMARCHY_PATH` or `~/.config`.
- Mock system-changing tools (`tests/hardware-mock-lib.sh`) — never invoke
  `sudo`, DNF, or hardware directly.

```bash
bash scripts/test.sh
```

---

## 8. Portability checks

Fedarchy must work regardless of where the tree lives or who the user is.

```bash
bash scripts/test-relocation.sh
```
Tests must not assume `/home/<user>`, must resolve `Path.home()`, and must use
`getent` rather than parsing `/home/$username`. Two real bugs came from this:
`tests/workspace-layout-test.sh` (HOME isolation) and
`tests/theme-picker-test.py` (hard-coded path).

---

## 9. Validation checklist before you call it done

```bash
bash scripts/test.sh                     # 40/40
bash tests/installer-test.sh             # 67
bash tests/installer-ux-test.sh          # 81
bash tests/hooks-backend-test.sh         # 24
bash -n on every shell script you touched
qmllint -I shell on every QML file you touched
python3 -m compileall -q bin tests
```

Do not report a figure you did not re-run.

---

## 10. Documentation

Keep docs synchronised with the implementation. When you change a command,
installer option, profile, or component, update the owning document:

| Subject | Owner |
|---|---|
| Overview / navigation | [`../README.md`](../README.md) |
| First-time setup | [INSTALLATION.md](INSTALLATION.md) |
| Installer options & profiles | [INSTALLER_GUIDE.md](INSTALLER_GUIDE.md) |
| User-facing capabilities | [FEATURES.md](FEATURES.md) |
| Structure | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Internals | [BACKEND.md](BACKEND.md) |
| Customisation & paths | [CONFIGURATION.md](CONFIGURATION.md) |
| CLI surface | [COMMAND_REFERENCE.md](COMMAND_REFERENCE.md) |
| Verification | [TESTING.md](TESTING.md) |
| Provenance | [OMARCHY_PORT.md](OMARCHY_PORT.md) |
| Gaps | [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) |

Summarise and link; do not copy sections between documents.

---

**See also:** [CONTRIBUTING.md](../CONTRIBUTING.md) · [TESTING.md](TESTING.md) ·
[ARCHITECTURE.md](ARCHITECTURE.md) · [`../AGENTS.md`](../AGENTS.md)