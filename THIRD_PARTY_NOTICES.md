# Third-Party Notices

Fedarchy is a derivative work. This file records the third-party material that
ships with the project, why it is present, and what is and is not verified about
its provenance. It does not claim to be a complete licensing audit — see
[Known limitations](docs/KNOWN_LIMITATIONS.md) for what remains unresolved.

---

## 1. Omarchy (the upstream project)

| Field | Value |
|---|---|
| **Component** | The entire upstream foundation of this project |
| **Purpose** | Original vision, design direction, desktop shell, command surface, themes, installer concept |
| **Source** | <https://github.com/omacom/omarchy> |
| **Homepage** | <https://omarchy.org/> |
| **Licence** | MIT |
| **Required notice** | `Copyright (c) David Heinemeier Hansson` |
| **Verification status** | **Verified 2026-10-11** — the upstream `LICENSE` file was fetched directly from `https://raw.githubusercontent.com/omacom/omarchy/master/LICENSE` and matches the notice reproduced in this repository's [`LICENSE`](LICENSE) |

Fedarchy is an **unofficial** port. It is not an official Omarchy release and
carries no endorsement from David Heinemeier Hansson or the Omarchy
maintainers. See [docs/OMARCHY_PORT.md](docs/OMARCHY_PORT.md) for the full
relationship, provenance table, and scope statement.

### Provenance evidence

Fedarchy's command surface is demonstrably derived from Omarchy: all fifteen
commands that Fedarchy deliberately removed (see §4) are still present in the
upstream repository. This was checked directly against
`https://raw.githubusercontent.com/omacom/omarchy/master/bin/<command>` for each.

---

## 2. Bundled assets

### 2.1 Theme assets — **provenance NOT fully verified**

Fedarchy ships **22 themes** under [`themes/`](themes/), each containing a
`backgrounds/` directory with raster images, plus `colors.toml`,
`icons.theme`, `neovim.lua`, `vscode.json`, `preview.png`, `preview-unlock.png`,
and `unlock.png`.

| Field | Value |
|---|---|
| **Components** | Theme colour definitions, wallpapers/backgrounds, icon themes, editor colour maps |
| **Provenance** | **Inherited from Omarchy.** The per-theme directory layout matches the upstream convention |
| **Licence** | **Unverified at the individual-asset level.** See below |
| **Verification status** | **Partial** — directory structure confirmed; per-file licences not established |

**The unresolved point, stated plainly:** the MIT notice on the Omarchy
*repository* covers the repository's own content. It has not been verified that
every individual background image, icon theme, and preview PNG bundled here was
itself covered by that notice, nor whether any third party (an original wallpaper
artist, for example) holds separate rights in a specific image. No licence has
been invented for these files.

**Practical guidance:** if you redistribute Fedarchy, review
`themes/*/backgrounds/` for assets whose provenance you cannot confirm, and
either obtain permission or replace them. This is a real gap, not a formality.

### 2.2 Icon font — `default/fonts/omarchy/omarchy.ttf` (traced third-party logos)

This is a **separate and more specific** provenance concern than the theme
backgrounds, and it was identified during the pre-release audit.

`omarchy.ttf` is a private-use icon font whose glyphs are **traced or
redrawn third-party brand logos**. `default/fonts/omarchy/README.md` documents
each glyph and its source, including:

| Glyph | Source recorded in the font's own README |
|---|---|
| `U+E900` Omarchy | Upstream Omarchy |
| `U+E901` Pi | `pi.dev/logo-auto.svg` |
| `U+E902` OpenCode | `opencode.ai/favicon-96x96-v3.png` |
| `U+E903` omp | `omp.sh/favicon.svg` |
| `U+E904` Grok | `grok.com/images/favicon.svg` |
| `U+E905` Codex | The OpenAI mark (developers.openai.com) |
| `U+E906` LM Studio | simpleicons.org |
| `U+E907` Ollama | simpleicons.org |
| `U+E908` T3 Code | Traced from an AUR package icon (upstream publishes no monochrome SVG) |
| `U+E909` Ori | OpenRouter's own brand mark |
| `U+E90A` Hermes | Traced from a Nous Research desktop icon |
| `U+E90B` Perplexity | simpleicons.org |
| `U+E90C` OpenClaw | Traced from the openclaw package's `favicon.svg` |
| `U+E90D` Cursor | simpleicons.org |
| `U+E90E` Claude | simpleicons.org |

**Status: UNRESOLVED — requires maintainer decision before public release.**

- `default/fonts/omarchy/hermes.svg` carries an explicit
  `Copyright (c) 2025 Nous Research` notice, i.e. a **third party holds a
  copyright** in at least one traced glyph.
- Several glyphs were **traced** rather than copied from an official vector,
  which may fall outside whatever permission the original mark's publisher
  granted.
- Some sources are Simple Icons, whose *SVG data* is CC0, but Simple Icons
  explicitly does **not** grant trademark rights; brand marks remain the
  property of their owners.
- No licence file ships alongside the font. The font is small, so the question
  is legal rather than technical.

**Practical guidance:** redistribution of a font embedding third-party brand
logos may raise trademark questions independent of copyright. Before a public
release, either (a) confirm the upstream project's basis for shipping this font
and mirror it, (b) remove the glyphs whose rights are unclear, or (c) hold the
release until this is resolved. **No licence has been invented for these
glyphs.**

### 2.3 Empty asset directories

`assets/` and `Wallpapers/` exist as empty directories in the development tree
but contain **no files**. They are placeholders, not shipped resources, and —
like all empty directories — are not preserved by Git, so they will not appear
in a repository checkout. Nothing is documented as being available from them.

### 2.4 `logo.txt`

`logo.txt` contains an ASCII-art wordmark for the project name. It is an
original text asset created for this repository.

### 2.5 Konobeat — vendored plugin

| Field | Value |
|---|---|
| **Component** | [`shell/plugins/konobeat/`](shell/plugins/konobeat/) — the bar widget and service that draw the audio visualizer |
| **Purpose** | A spectrum and waveform visualizer for the bar, with the song and artist scrolling beside it |
| **Author** | Alec Xu |
| **Source** | <https://github.com/xvvhang/omarchy-konobeat-plugin> |
| **Licence** | MIT — the upstream text is reproduced verbatim in [`shell/plugins/konobeat/LICENSE`](shell/plugins/konobeat/LICENSE) |
| **Required notice** | `Copyright (c) 2026 Alec Xu` and `Copyright (c) David Heinemeier Hansson` (Omarchy-derived code) |
| **Verification status** | **Verified 2026-10-19** — the upstream `LICENSE` file was read directly from the installed checkout at revision `d0d0683` and carried over unchanged, and the manifest, the QML and the Python helper were taken from that same revision |

The plugin is vendored rather than installed from its upstream repository so
that the visualizer's appearance can be read from a configuration file the
user owns, and so that the project can keep the plugin in step with the rest
of the shell. The changes made to it are listed in
[`shell/plugins/konobeat/NOTICE.md`](shell/plugins/konobeat/NOTICE.md). The
upstream project remains the author of the work.

---

## 3. Software used at runtime but **not** bundled

These are installed on, or expected to already exist on, the user's Fedora
system. They are **dependencies, not redistributed components**, and their
licences are those of their own projects.

| Dependency | Role |
|---|---|
| Quickshell | Hosts the desktop shell (bar, panels, overlays) |
| Hyprland | Wayland compositor the shell is designed for |
| DNF5 / Fedora packages | Package operations |
| PipeWire / WirePlumber | Audio routing used by the audio panel |
| NetworkManager | Network state used by the network and Wi-Fi panels |
| UPower | Power and battery state |
| `rsync`, `realpath`, `date`, `cmp`, `readlink` | Required by the setup installer |

Fedarchy does not vendor any of these. See
[docs/INSTALLATION.md](docs/INSTALLATION.md) for what the installer expects to
find.

---

## 4. Deliberately removed upstream components

The following commands exist in upstream Omarchy but are **not shipped** by
Fedarchy, because whole-machine provisioning and destructive disk/bootloader
operations fall outside this project's scope:

`omarchy-provision-owner`, `omarchy-provision-user`, `omarchy-provision-first-run`,
`omarchy-apply-hardware`, `omarchy-apply-system`, `omarchy-system-factory-reset`,
`omarchy-system-factory-reset-finish`, `omarchy-drive-password`,
`omarchy-drive-select`, `omarchy-hibernation-setup`, `omarchy-hibernation-remove`,
`omarchy-hibernation-available`, `omarchy-refresh-limine`, `omarchy-snapshot`,
`omarchy-dns`.

They are listed here for provenance transparency — they are **not** hidden or
deprecated functionality, and they must not be documented as available. See
[docs/SECURITY.md](docs/SECURITY.md) and [docs/OMARCHY_PORT.md](docs/OMARCHY_PORT.md).

---

## 5. How to read this file

- **Verified** — checked against a primary source during this documentation phase.
- **Partial** — the general claim is supported, but not for every file.
- **Unverified** — no reliable evidence available; nothing has been invented.

Where provenance is unclear, this file says so rather than guessing. A licence
you have not verified is worse than an acknowledged gap.