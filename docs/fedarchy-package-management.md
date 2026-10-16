# fedarchy and fedarchy-pkg

Fedarchy's package-management front end for Fedora.

**Fedarchy does not implement a package manager.** These commands decide which
native `dnf5` subcommand to run and whether to ask for confirmation, then hand
the work to DNF5. Dependency resolution, repository metadata, package state,
downloads and transaction execution all stay inside DNF5. There is no local
package database, no repository manager and no second dependency solver.

If Fedarchy were removed entirely, nothing about `dnf5` on this system would
change.

## Commands

```
fedarchy update [args...]        Run the system update (needs root)
fedarchy upgrade [args...]       Alias for update
fedarchy status                  Read-only system and update summary
fedarchy doctor                  Read-only diagnostics
fedarchy help                    Usage

fedarchy-pkg add <package>...    Install
fedarchy-pkg remove <package>... Remove
fedarchy-pkg search <term>...    Search
fedarchy-pkg info <package>...   Details
fedarchy-pkg list [--installed]  List
fedarchy-pkg provides <file>...  What provides a file
fedarchy-pkg history             Transaction history (defaults to `history list`)
fedarchy-pkg history info <id>   Details of one transaction
fedarchy-pkg undo <id>           Revert a transaction
fedarchy-pkg redo <id>           Re-apply a transaction
fedarchy-pkg check               Check for packaging problems
```

## Aliases

| Friendly | Native DNF5 |
|---|---|
| `add` | `install` |
| `remove`, `erase`, `uninstall`, `rm` | `remove` |
| `info`, `show` | `info` |
| `undo` / `redo` / `rollback` | `history undo` / `history redo` / `history rollback` |
| `fedarchy upgrade` | reuses `omarchy-update-dnf` |

## Passthrough

**Any subcommand not listed above is forwarded to `dnf5` unchanged.** DNF5's own
options keep working, and an unrecognised word is never reinterpreted as
something else:

```bash
fedarchy-pkg repoquery --duplicates
fedarchy-pkg groups list
fedarchy-pkg makecache
```

`fedarchy-pkg frobnicate all` runs `dnf5 frobnicate all` and lets DNF5 report
the error. It never becomes an install or a remove.

## Privileges

| Command | Root needed |
|---|---|
| `status`, `doctor` | no |
| `search`, `info`, `list`, `provides`, `history` | no |
| `add`, `remove`, `undo`, `redo`, `update` | yes — escalated automatically via `sudo` |

Read-only commands never escalate, so they never prompt for a password.

## Confirmation policy

Mutating operations confirm before running:

- **`-y` / `--yes`** — skip the prompt. This flag is consumed by the wrapper and
  is *not* forwarded, so DNF5's plan still gets printed.
- **No TTY** — proceeds unattended rather than blocking on a prompt nobody can
  answer. DNF5's own prompting rules still apply.
- **Otherwise** — prompts, and anything but a `yes` answer aborts without running.

## Transaction previews

The plan you see is DNF5's own, produced by DNF5's solver, by running the real
command with `--assumeno` and declining. There is no independent calculation, so
the preview cannot drift from what would really happen.

**A preview is not a guarantee.** Package state, repository metadata and network
conditions can all change between the preview and the real run.

## Limitations

- **Not every transaction can be reversed.** `undo` and `redo` are DNF5's own
  operations and depend on what the transaction actually did. DNF5 refuses some
  of them — that refusal is reported as-is, not worked around.
- **`fedarchy-pkg history` alone** prints nothing useful in DNF5, so the wrapper
  defaults it to `history list`.
- **Reboot versus restart** are different things. `status` reports an application
  restart recommendation separately from a system reboot; a running service that
  needs restarting is not a reason to reboot.
- **`doctor` runs `dnf5 makecache`.** That writes DNF5's own metadata cache and
  changes no repository configuration. It is the only way to honestly report
  repository health.

## Safety properties

- Every subprocess call uses a **bash argument array**. Package names are never
  concatenated into a shell string, so a name like `evil; rm -rf /` reaches DNF5
  as one literal argument. There is no `eval` anywhere in either script.
- A missing package manager is reported with an actionable message rather than
  silently falling back.
- `doctor` and `status` are read-only: they never install, remove, repair,
  reconfigure or clear caches.

## Tests

```bash
tests/fedarchy-pkg-test.sh
```

25 assertions against a **mocked `dnf5` and a mocked `sudo`**. The mock records
the argv it was handed, so alias translation, privilege decisions and
passthrough are all verified without a single real package operation. The
metacharacter case and the "unknown verb is not rewritten" case are the two that
guard the safety properties above.