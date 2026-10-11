# AGENTS.md — Guidance for AI coding agents and maintainers

Project-specific instructions. Read this **before** changing anything in
`~/Fedarchy`.

---

## 1. What this project is

Fedarchy is a **Fedora-oriented port of [Omarchy](https://github.com/omacom/omarchy)**.

- It customises an **already-installed, already-working Fedora desktop**.
- It is **NOT** a distribution, OS installer, disk partitioner, bootloader
  configurator, or whole-machine provisioning tool.
- It is **NOT** an official Omarchy release and has **no endorsement** from DHH /
  David Heinemeier Hansson. Never imply otherwise in text you write.
- Target desktop is **Hyprland only**. Do not claim KDE/Plasma/GNOME support.

→ [docs/OMARCHY_PORT.md](docs/OMARCHY_PORT.md)

---

## 2. Hard scope boundary — do not cross

Fedarchy **deliberately removed** these upstream commands as out of scope. Do not
re-add them, document them as available, or build features that depend on them:

`omarchy-provision-owner` · `omarchy-provision-user` · `omarchy-provision-first-run` ·
`omarchy-apply-hardware` · `omarchy-apply-system` · `omarchy-system-factory-reset` ·
`omarchy-system-factory-reset-finish` · `omarchy-drive-password` · `omarchy-drive-select` ·
`omarchy-hibernation-setup` · `omarchy-hibernation-remove` · `omarchy-hibernation-available` ·
`omarchy-refresh-limine` · `omarchy-snapshot` · `omarchy-dns`

They are **intentionally unsupported**, not missing features. → [docs/SECURITY.md](docs/SECURITY.md)

---

## 3. Licensing and attribution — non-negotiable

- Omarchy is **MIT, © David Heinemeier Hansson**. Preserve that notice in any
  file carrying inherited code. Never strip or relicense it.
- **There is currently no named copyright holder for the Fedora-specific
  changes. Do not invent one.** Leave it stated as unresolved.
- Do not invent a licence for an asset (image, font, theme, icon) whose origin
  you cannot verify. Record the uncertainty instead.
  → [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

---

## 4. Directory responsibilities

| Directory | Responsibility |
|---|---|
| `bin/` | 453 standalone `omarchy-*` commands |
| `shell/` | Quickshell shell (QML + JS), `services/`, `plugins/` |
| `default/` | **Runtime resources** deployed to `$OMARCHY_PATH` |
| `config/` | **User-configuration templates** copied to `~/.config` |
| `themes/` | 22 theme definitions |
| `scripts/` | Installer (`install.sh`, `install-components.sh`), test runner |
| `tests/` | Test suites |

### `default/` vs `config/` — the distinction to get right

They share basenames and are **not** duplicates. `default/` holds what the system
**reads at runtime**; `config/` holds templates **copied into the user's config**.
Do not "deduplicate" by treating a shared basename as the same file.
→ [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#default-vs-config--an-important-distinction)

---

## 5. Installer manifest

Components are defined in **`COMPONENT_SPECS`** in
`scripts/install-components.sh` (pipe-delimited: `id | required | depends-on |
destination | what | why`). Profiles are in **`profile_components()`** in the same
file.

**Changing a component means updating `tests/installer-ux-test.sh`**, which
asserts the component set. Run both installer suites after any manifest change.

Quirk to remember: if both `--profile` and `--component` are passed, the
**profile wins** and `--component` is ignored.

---

## 6. Testing entry points

```bash
bash scripts/test.sh                # main suite — expect 40 passed, 0 failed
bash tests/installer-test.sh        # 67
bash tests/installer-ux-test.sh     # 81
bash tests/hooks-backend-test.sh    # 24
bash scripts/test-relocation.sh
```

Per-file checks: `bash -n` on shell, `qmllint -I shell <file>` on QML,
`python3 -m compileall -q bin tests` on Python.

**`qmllint` caveat:** use `-I shell`, **not** `--bare` — this build rejects
`--bare` and fails silently, producing a false "0 errors". Also, `qmllint` exits
255 with no output when Quickshell imports cannot be resolved; that is
environmental, not a syntax failure.

---

## 7. Safety rules when working in this tree

1. **Back up before editing.** Snapshots live in `~/Fedarchy-backups/`.
2. **Never run destructive or system-level operations on the developer's
   machine** — no `sudo`, no DNF installs, no disk/bootloader/partition tools.
3. **Use mocks for anything system-changing.** See
   `tests/hardware-mock-lib.sh`.
4. **Use synthetic `HOME` and temp destinations** in tests. Never write to the
   real `~/.config`, `$OMARCHY_PATH`, or `~/.local/bin` from a test.
5. **Do not run `scripts/install.sh` for real** unless explicitly asked. Use
   `--dry-run`, `--check`, or the isolated test suites.
6. **Never modify or delete live user files** (`~/.config/hypr`, `~/.config/omarchy`,
   the running session) as part of a test or cleanup.
7. **The running desktop is live.** Editing `shell/` triggers a Quickshell hot
   reload of the user's actual session. Never restart or kill Quickshell
   unprompted.

---

## 8. Honesty rules for anything you write

- **Inspection is not testing.** Say "verified by reading the code", not "tested",
  unless a test actually ran.
- **Syntax-clean ≠ behaviour-correct.** `bash -n` passing proves nothing about
  behaviour.
- **Mocked tests are not live integration.** Never present a mocked suite as
  proof that a feature works on real hardware.
- **Never invent:** repository URLs, contributors, versions, release dates,
  badges, coverage figures, CI status, compatibility claims, or installation
  results.
- **Never fabricate a legal identity**, copyright holder, security contact, or
  disclosure channel.
- Re-run the checks before quoting any figure. If you cannot re-run it, say the
  figure is unverified.
- Record unresolved gaps in [docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md)
  rather than hiding them.

---

## 9. Environment facts

- **No Git repository.** `.git` is absent. **Do not `git init`**, and do not assume
  a remote exists.
- **No CI.** No `.github/`, no pipeline. All results were produced manually.
- Fedora and Hyprland are the target; Fedora's package manager is **DNF5**.
- `OMARCHY_PATH` defaults to `~/.local/share/fedarchy` (installer) or
  `~/Fedarchy` (`omarchy-launch-shell`).
- `CONFIG_HOME` is **pinned to `~/.config`**. Do not assume `XDG_CONFIG_HOME`
  portability.

---

## 10. Keeping documentation true

The documentation suite is part of the deliverable. If you change behaviour,
update the document that **owns** that subject (see the table in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#10-documentation)), and link rather than
duplicate.

If you find documentation contradicting the implementation: **verify the code,
document the true behaviour, and record the discrepancy.** Do not silently change
executable code to match prose, and do not leave stale prose in place.

---

**Quick orientation:** [README.md](README.md) · [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) ·
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · [docs/TESTING.md](docs/TESTING.md) ·
[docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md)