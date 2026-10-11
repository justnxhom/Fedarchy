#!/usr/bin/env python3
"""Generate the Fedarchy first-release inventory.

Emits two file lists:
  RELEASE  — supported for the first public commit
  HOLDBACK — must not enter public history until rights are resolved

Classification is evidence-based, not blanket: a whole source directory is
never excluded, and media files are judged individually.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# --- HOLDBACK: third-party brand marks of unresolved provenance ------------
# Confirmed: these are traced/redrawn trademarked logos, or are otherwise
# third-party marks whose redistribution terms are not evidenced.
HOLDBACK_REASON = {
    "default/fonts/omarchy/omarchy.ttf":
        "Icon font embedding 14 traced/redrawn third-party brand logos "
        "(OpenAI/Codex, Anthropic/Claude, Perplexity, Cursor, Grok, Ollama, "
        "OpenRouter, Nous Research, Pi, omp, OpenCode, LM Studio, T3 Code, "
        "OpenClaw). Traced, not copied from official vectors. No font licence "
        "shipped, upstream or here. Font binary carries no copyright string.",
    "default/fonts/omarchy/hermes.svg":
        "Traced Hermes mark carrying an explicit 'Copyright (c) 2025 Nous "
        "Research' notice — a third party demonstrably holds rights.",
    "shell/plugins/agents/assets/claude.svg":
        "Anthropic brand mark. Byte-identical to upstream Omarchy, which "
        "asserts no trademark permission. Same class of issue as the icon font.",
    "shell/plugins/agents/assets/codex.svg":
        "OpenAI brand mark. Byte-identical to upstream Omarchy, which asserts "
        "no trademark permission. Same class of issue as the icon font.",
    "shell/plugins/agents/assets/codex-light.svg":
        "OpenAI brand mark (light variant). Same class of issue.",
}

# Files excluded by .gitignore / not publishable as debris
DEBRIS = {
    "shell/Ui/OpticalGlyph.qml.bak": "stale editor backup; live .qml is in use",
    "shell/plugins/.panels/cava.bak.20260925182541/BarWidget.qml":
        "developer debris: manual backup of a removed panel, unreferenced",
    "shell/plugins/.panels/cava.bak.20260925182541/manifest.json":
        "developer debris: manual backup of a removed panel, unreferenced",
}

# --- PRECAUTION: inherited, unmodified, but per-asset rights unverified ----
# Not a confirmed legal defect: these are byte-identical to upstream Omarchy
# and inherit exactly the status upstream already publishes under. The
# precaution is that no per-asset licence was ever evidenced upstream either.
# Restricted to raster/vector *artwork* under themes/ — the colour palettes
# (colors.toml), icon mappings (icons.theme) and editor colour maps are
# functional configuration data, not expressive marks, and are released.
PRECAUTION_SUBSTRINGS = ["/backgrounds/"]


def main():
    release, holdback, debris, precaution = [], [], [], []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames
                       if os.path.join(dirpath, d) != os.path.join(ROOT, ".git")]
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ROOT)
            if rel in HOLDBACK_REASON:
                holdback.append(rel)
            elif rel in DEBRIS:
                debris.append(rel)
            elif any(s in "/" + rel for s in PRECAUTION_SUBSTRINGS):
                precaution.append(rel)
            else:
                release.append(rel)

    def w(name, items):
        path = os.path.join(ROOT, name)
        with open(path, "w", encoding="utf-8") as fh:
            for i in sorted(items):
                fh.write(i + "\n")
        return len(items)

    print(f"RELEASE   : {w('RELEASE-INVENTORY.txt', release):5} files")
    print(f"HOLDBACK  : {w('HOLDBACK-INVENTORY.txt', holdback):5} files")
    print(f"DEBRIS    : {w('DEBRIS-INVENTORY.txt', debris):5} files (already gitignored)")
    print(f"PRECAUTION: {w('PRECAUTION-INVENTORY.txt', precaution):5} files "
          f"(inherited themes/, no per-asset licence)")
    print()
    print("HOLDBACK detail:")
    for r in sorted(holdback):
        print(f"  - {r}")
        print(f"      {HOLDBACK_REASON[r][:150]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())