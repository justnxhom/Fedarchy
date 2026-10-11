# Troubleshooting

Symptom-first. Each case gives an observable symptom, the likely cause, a
**read-only** diagnostic, and a fix.

**Rule of thumb: diagnose before you change anything.** Never delete a config
directory or a backup directory as a generic "fix" — back things up and ask what
the code expects first.

---

## Installer problems

### `install.sh: Unknown profile: X`

**Cause:** `--profile` only accepts `minimal`, `recommended`, `preserve`, `custom`.
**Fix:**
```bash
bash scripts/install.sh --help
bash scripts/install.sh --dry-run --profile recommended
```

### `--component` seems to be ignored

**Cause:** passing `--profile` **and** `--component` together — the profile wins
and the component list is discarded.
**Fix:** use `--component` alone.
```bash
bash scripts/install.sh --dry-run --component shell --component commands
```

### "A non-interactive run with no --yes exits non-zero"

**Cause:** correct behaviour. `install`, `link`, and `uninstall` print their plan
and refuse to assume consent without a terminal or `--yes`.
**Fix:** run it interactively, or pass `--yes` once you have reviewed the plan.

### Preflight fails on missing commands

**Symptom:** the installer lists missing tools and prints a `dnf5 install` line.
**Cause:** the installer never installs packages; it tells you what is missing.
**Fix:** run the printed `dnf5 install` yourself, then re-run the installer.

```bash
bash scripts/install.sh --check
```

### Preflight fails on the target path

**Symptom:** complaints about the target directory, disk space, or the target
matching the source.
**Cause:** safety checks. Fedarchy refuses to install over its own source, into
an unsafe path, or without space.
**Fix:** point `$OMARCHY_PATH` somewhere safe and distinct from your checkout:
```bash
OMARCHY_PATH="$HOME/.local/share/fedarchy" bash scripts/install.sh --dry-run
```

### Something went wrong mid-install — how do I undo it?

```bash
bash scripts/install.sh list       # what backups exist
bash scripts/install.sh rollback   # restore the most recent one
bash scripts/install.sh status     # what is deployed now
```
**Caveat:** rollback restores the most recent backup. It is not an automatic
transactional undo of a partial run.
→ [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md#45-no-transactional-rollback)

---

## Shell problems

### QML won't load / a plugin fails to appear

**Diagnostic (read-only):**
```bash
omarchy-shell ping
journalctl --user -n 50 | grep -i quickshell
```

**Things to check:**
- `$OMARCHY_PATH` points at a real Fedarchy tree.
- The shell's plugin directory contains the plugin you expect.
- A plugin you added recently is valid — plugins are **unsandboxed**, so a broken
  one can take the shell down with it. → [omarchy-plugins.md](omarchy-plugins.md)

> **Note:** editing files under `shell/` while the shell runs triggers a hot
> reload. That is expected, but it means a syntax error takes the UI down until
> you fix the file.

### A panel shows stale or empty data

**Cause:** the panel reads a system service (PipeWire, UPower, NetworkManager).
**Diagnostic:** check the underlying service directly, e.g.
```bash
wpctl status
nmcli general status
```
A panel being present does not mean the service is configured.

---

## Theme problems

### A theme doesn't apply

```bash
omarchy-theme-list        # is the name right?
omarchy-theme-current     # what is active?
```
Then check the theme directory actually contains `colors.toml`, and re-apply.
Theme application touches Qt/GTK caches; re-running `omarchy-theme-set` for the
same theme is safe and idempotent.

### My theme change didn't survive a restart

**Cause:** the theme was applied to user config, but something restored or
overwrote that config (e.g. a re-install that replaced it).
**Fix:** re-apply the theme, and check whether the installer replaced your config.

---

## Keybinding problems

### I edited the keybindings and nothing happened

**This is the most common surprise.** Keybindings exist in **two** trees and only
one is loaded:

| Tree | Loaded? |
|---|---|
| `default/hypr/bindings/*.lua` (project tree) | **No** — nothing loads it on a live machine |
| `~/.config/hypr/modules/binds.lua` | **Yes** — this is the live file |

Editing the project tree alone changes nothing at runtime. A binding changed in
only one tree is silently dead.
→ [hyprland-keybindings.md](hyprland-keybindings.md)

### I declined Fedarchy's keybindings and my config got a flag

If you installed keybindings but declined the defaults, the installer may have
written `omarchy_default_bindings = false` so your own entrypoint decides. This
is **statically tested but not live-verified** — report oddities.

---

## Command problems

### `omarchy-*`: command not found

```bash
ls ~/.local/bin/omarchy-theme-list
ls -l ~/.local/bin | head
```
If the file is missing, the `commands` component was not installed:
```bash
bash scripts/install.sh --dry-run --component commands
```

### A command I expected doesn't exist

Some upstream commands were **deliberately removed** (provisioning, disk, boot,
factory reset, DNS). They are out of scope, not deprecated.
→ [COMMAND_REFERENCE.md](COMMAND_REFERENCE.md#5-commands-that-do-not-exist)

### A command fails and the error is unhelpful

Read the command's own metadata — it documents its purpose and arguments:
```bash
head -5 ~/.local/bin/omarchy-<command>
```

---

## Development problems

### A test fails after I changed something

```bash
bash scripts/test.sh                     # main suite
bash tests/installer-test.sh             # installer
bash tests/installer-ux-test.sh          # installer UX
bash tests/hooks-backend-test.sh         # hooks & backend
```

Tests use synthetic homes and temp directories — they will not touch your real
`~/.config`, but they **do** expect the code they test to exist. If you removed
or renamed a command, update the tests that reference it.

### `qmllint` exits 255 with no output

That means **imports could not be resolved**, not that your file is broken. It is
the normal result outside a Quickshell runtime.
→ [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md#32-qml-validation-is-syntax-only)

### A test touches my real config

That should not happen — tests set `HOME` to a temp directory. If one appears to,
that is a **bug in the test's isolation**, worth reporting. Verify with:
```bash
grep -n 'HOME=' tests/<failing-test>
```

---

## Still stuck?

Go to [FAQ](FAQ.md) for conceptual questions, or
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) for things that are genuinely not
finished yet — the answer may be "that's a known gap", which is useful to know.

---

**See also:** [INSTALLATION.md](INSTALLATION.md) ·
[CONFIGURATION.md](CONFIGURATION.md) · [BACKEND.md](BACKEND.md) ·
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md)