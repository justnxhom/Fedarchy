# Testing Guide

How to reproduce Fedarchy's verification. Every figure below was **re-run** while
writing this documentation.

---

## 1. The numbers (verified 2026-10-11)

| Check | Command | Result |
|---|---|---|
| Main regression suite | `bash scripts/test.sh` | **40 passed, 0 failed** |
| Installer suite | `bash tests/installer-test.sh` | **67 passed, 0 failed** |
| Installer UX suite | `bash tests/installer-ux-test.sh` | **81 passed, 0 failed** |
| Hooks & backend | `bash tests/hooks-backend-test.sh` | **24 passed, 0 failed** |
| Shell syntax | **`bash -n` over every shell script in the tree** | **494 scripts, 0 failures** |
| QML lint | `qmllint -I shell` over `shell/**/*.qml` | **105 files, 0 diagnostics** |
| Python compile | `python3 -m compileall -q bin tests` | OK |

Run the whole thing:

```bash
cd ~/Fedarchy
bash scripts/test.sh
bash tests/installer-test.sh
bash tests/installer-ux-test.sh
bash tests/hooks-backend-test.sh
```

> An earlier audit reported 497 shell scripts. The current, re-counted figure is
> **494** after the risky-command cleanup. Use the number above.

---

## 2. What each check actually proves

This distinction matters more than the pass marks.

| Check | Proves | Does **not** prove |
|---|---|---|
| `bash -n` | The script is syntactically valid | That it behaves correctly |
| `qmllint` | The QML parses; no diagnostics emitted | That it renders, or type-checks against Quickshell |
| `compileall` | Python files compile | That they run correctly |
| `scripts/test.sh` | The registered behavioural assertions pass | Anything about live system services |
| Mocked suites | Logic is correct when external tools are stubbed | That the real tool behaves the same |

**Syntax validation is not behavioural coverage.** Being syntax-clean does not
mean a command has ever been run.

---

## 3. Coverage, measured honestly

A rough proxy — the number of distinct commands **named** in any behavioural test:

```bash
grep -rhoE 'omarchy-[a-z0-9-]+' tests/ --include='*.sh' --include='*.py' \
  | sort -u | wc -l        # 140
ls bin | wc -l              # 453
```

**~30% (140/453)** by this measure. Treat it as a *lower bound* and a weak proxy:
naming a command in a test does not prove its full behaviour is covered, and some
coverage may live indirectly. The honest summary is that **most commands have no
dedicated behavioural test.**

---

## 4. Test categories in the suite

| Category | Files | What it covers |
|---|---|---|
| Backend / Fedora | `backend-fedora.sh`, `copr-search-test.sh`, `menu-package-actions.sh` | DNF5 behaviour, failed-query handling, COPR search |
| Hooks & safety | `hooks-backend-test.sh` | Hook dispatch, dangerous-command guards (mocked) |
| Installer | `installer-test.sh`, `installer-ux-test.sh` | Deploy, profiles, components, dry-run, keybinding flag, backups |
| Lifecycle | `lifecycle-install-test.sh`, `lifecycle-shell-test.sh`, `lifecycle-hyprland-test.sh` | Install/shell/Hyprland contracts |
| Themes | 9 theme suites | Set, staging, app configs, GTK/Qt, install, picker, fonts |
| Plugins | `plugin-validate-test.sh`, `plugin-registry-lifecycle-test.sh`, `plugin-update-test.sh` | Plugin contract and lifecycle |
| Shell/UI | `background-transition-test.js`, `clock-format-cycle-test.js`, `media-*.js` | QML/JS logic |
| Layout | `workspace-layout-test.sh`, `hypr-bindings-test.py` | Workspace/lock/bindings |

---

## 5. Isolation techniques

Fedarchy's tests are careful not to touch your real system:

- **Synthetic homes** — tests set `HOME` (and `XDG_STATE_HOME`) to a temp
  directory, so theme/workspace/config tests cannot touch your real config.
  (`tests/workspace-layout-test.sh`, `tests/theme-picker-test.py`.)
- **Temporary destinations** — install/deploy tests write to a temp target, never
  to `$OMARCHY_PATH`.
- **Mocked external tools** — hardware/backend suites stub system tools
  (`tests/hardware-mock-lib.sh`) so no `sudo`, DNF, or device is touched.
- **Refusal tests** — the hooks suite asserts that dangerous operations are *not*
  reached (e.g. `copr-remove` never reaches a disable step) using mocks.

**Your real `~/.config` and running desktop are safe to run these against.**

---

## 6. Running the shell live (optional)

To inspect the real shell (read-only; does not change anything):

```bash
omarchy-shell ping          # is it up?
journalctl --user -n 50    # recent shell messages
```

> Editing files under `shell/` while the shell is running triggers a **hot
> reload** of the running desktop. That is expected behaviour, not a bug — but
> know it before you edit.

---

## 7. Live / real-system verification — **not yet performed**

The following are **unverified**. No evidence exists that they work on real
hardware:

- A full install onto a separate, physical Fedora machine.
- Live Hyprland behaviour: keybindings actually firing, the network/Wi-Fi panel
  against real NetworkManager, bar widgets on a real session.
- Live integration with PipeWire/WirePlumber (audio panel), UPower (power/battery),
  and the notification daemon.
- Theme application to a real running session.

### Suggested procedure (for maintainers, on a throwaway machine)

*Not yet performed — presented as a procedure, not as a result.*

1. Install Fedora with Hyprland on a spare machine or VM with GPU.
2. Check out Fedarchy, run `bash scripts/test.sh` (expect 40/40).
3. Run `bash scripts/install.sh --dry-run --profile recommended`; read the plan.
4. Run `bash scripts/install.sh --interactive`; apply the recommended profile.
5. Verify: `bash scripts/install.sh check`, `omarchy-shell ping`, switch themes,
   open each panel, test a few keybindings.
6. Log the results — and add them to this page.

Until someone does this and records the outcome, treat these behaviours as
**unconfirmed**. → [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md)

---

**See also:** [DEVELOPMENT.md](DEVELOPMENT.md) · [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) ·
[BACKEND.md](BACKEND.md)