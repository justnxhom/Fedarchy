# Contributing

Fedarchy is an **unofficial, community-run port**. There is no company behind it,
no support team, and no guaranteed response time. Small, careful contributions are
genuinely valuable.

---

## Before you contribute

**Fedarchy is not yet publicly hosted.** There is no public repository URL, issue
tracker, or PR process — so this guide describes *how to work in the tree* rather
than pointing you at a forge. When a public home is established, this page should
be updated with the real URLs.

Until then, coordinate with whoever maintains your copy of the tree.

---

## What makes a good contribution here

Fedarchy's value is that it is **carefully scoped and honestly tested**. Changes
that help most:

- Fixing a real portability bug (hard-coded paths, `/home/<user>` assumptions)
- Improving test isolation or coverage
- Fixing an actual defect in a command, with a regression test
- Fedora-specific integration correctness
- Documentation accuracy and clarity

Changes that do **not** fit the project's scope:

- Whole-machine provisioning, disk/bootloader operations, or factory reset
- Support for desktop environments other than Hyprland
- Re-introducing the removed upstream commands
- Restating the documentation suite as one giant README

→ [OMARCHY_PORT.md](docs/OMARCHY_PORT.md)

---

## Ground rules

1. **Respect the scope.** Fedarchy customises an existing Fedora desktop. It does
   not install an OS, partition disks, or configure bootloaders. Do not add
   features outside that boundary.
2. **Preserve upstream attribution and the MIT notice.** Inherited Omarchy code
   keeps its `Copyright (c) David Heinemeier Hansson` notice. Do not strip it or
   relicense material with unclear provenance.
   → [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
3. **Add tests.** A bug fix should come with a regression test that fails without
   it. → [DEVELOPMENT.md](docs/DEVELOPMENT.md#7-add-a-regression-test)
4. **Keep tests isolated.** Synthetic homes, temp directories, mocked
   system tools. Never let a test touch a real `$HOME`, `$OMARCHY_PATH`, `sudo`,
   DNF, or hardware.
5. **Match the existing style.** Bash with a `set -e` guard, a self-describing
   `# omarchy:summary=` header, quoted variables, loud failures.
6. **Do not run destructive operations on your own machine.** Test through mocks
   and temporary environments.
7. **Update the documentation** that owns whatever you changed.

---

## The pre-submission checklist

```bash
bash scripts/test.sh                # expect 40 passed, 0 failed
bash tests/installer-test.sh        # 67
bash tests/installer-ux-test.sh     # 81
bash tests/hooks-backend-test.sh    # 24
bash scripts/test-relocation.sh
```

Then, for what you touched:
```bash
bash -n <changed shell scripts>
qmllint -I shell <changed QML files>
```

**Never report a number you did not re-run.** If something fails, say so and
explain, rather than quietly leaving it out.

---

## Reporting issues

Describe:
1. What you did, and what you expected.
2. What happened instead (the actual output).
3. Your environment — Fedora version, Hyprland present?, fresh install or upgrade.
4. Relevant diagnostics: `bash scripts/install.sh --check`, `omarchy-shell ping`,
   `journalctl --user -n 50`, and the failing test output if any.

Be honest if you cannot reproduce something. An honest "this might be a stale
deployed copy" is far more useful than a confident wrong diagnosis.

---

## Honest documentation

If you contribute, please keep the project's honesty discipline:

- Do **not** claim a feature is tested when only its syntax was checked.
- Do **not** claim a real installation succeeded unless it actually did.
- Do **not** claim endorsement or official status.
- Add new gaps to [KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md) rather than
  quietly leaving them undocumented.

---

## Licensing your contribution

Fedarchy is MIT-licensed and inherits Omarchy's MIT terms. There is currently
**no named copyright holder for Fedora-specific changes** — see
[LICENSE](LICENSE). Until that is resolved, treat contributions as falling under
the repository's existing MIT terms, and raise the question with the maintainer
rather than assuming one.

---

## Code of conduct

Be decent to each other. Assume good faith, critique code rather than people, and
remember that a welcoming community is part of what makes a project like Omarchy
worth porting in the first place.

---

**See also:** [DEVELOPMENT.md](docs/DEVELOPMENT.md) ·
[TESTING.md](docs/TESTING.md) · [SECURITY.md](docs/SECURITY.md) ·
[KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md)