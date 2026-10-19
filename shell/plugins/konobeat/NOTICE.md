# Konobeat — upstream notice

This plugin is **vendored third-party code**, carried into the Fedarchy
repository so that the visualizer's appearance can be configured from a file
the user owns.

| Field | Value |
|---|---|
| **Upstream project** | Konobeat |
| **Author** | Alec Xu |
| **Upstream repository** | <https://github.com/xvvhang/omarchy-konobeat-plugin> |
| **Licence** | MIT — see [`LICENSE`](LICENSE) in this directory |
| **Vendored on** | 2026-10-19 |
| **Upstream revision** | `d0d0683` ("Add marketplace preview screenshot and README preview") |

The upstream licence text is reproduced verbatim in [`LICENSE`](LICENSE). It
covers two copyright holders: Alec Xu for the plugin, and David Heinemeier
Hansson for the parts derived from Omarchy. Fedarchy is an unofficial
derivative of Omarchy — see the project's `THIRD_PARTY_NOTICES.md` and
`docs/OMARCHY_PORT.md` for that relationship.

## What Fedarchy changed

- The plugin id is `omarchy.konobeat`, matching the other first-party plugins
  in this repository. The reserved `omarchy.*` namespace is what keeps a
  third party from claiming it.
- The visualizer's appearance — the number of bars, its width, its height and
  its colour — is read from `~/.config/omarchy/konobeat.json`. See
  [`README.md`](README.md).
- The service's IPC target was `media`, which the shell's own media service
  already answers on, so the handler was registered and then ignored. It is
  now `omarchy.konobeat.media`.
- The number of bands is derived in `VisualizerConfig.js` rather than in the
  QML, so that the derivation and the configuration file can be unit tested.

Everything else is upstream's, unchanged.
