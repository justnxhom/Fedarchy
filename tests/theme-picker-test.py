#!/usr/bin/env python3

import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

# theme-picker.py is a user-config file that lives outside this repository, so
# it is resolved from the invoking user's home. Resolve it at import time: the
# test below repoints HOME at a temporary directory before loading the module,
# and a path built after that would point at the temporary home instead.
THEME_PICKER = Path.home() / ".config/theme-switcher/theme-picker.py"


class ThemePickerTest(unittest.TestCase):
    def test_display_entries_use_real_theme_ids(self):
        if not THEME_PICKER.is_file():
            self.skipTest(f"theme-picker.py is not installed at {THEME_PICKER}")
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home"
            omarchy = Path(temporary) / "Fedarchy"
            (home / ".config/theme-switcher").mkdir(parents=True)
            for name in ("tokyo-night", "catppuccin-latte"):
                (omarchy / "themes" / name).mkdir(parents=True)
            entries = [
                {"name": "Night", "family": "Tokyo Night", "bgBase": "#111111", "accentPrimary": "#222222", "accentCyan": "#333333", "accentGreen": "#444444", "accentOrange": "#555555", "accentRed": "#666666", "textPrimary": "#777777"},
                {"name": "Latte", "family": "Catppuccin", "bgBase": "#eeeeee", "accentPrimary": "#222222", "accentCyan": "#333333", "accentGreen": "#444444", "accentOrange": "#555555", "accentRed": "#666666", "textPrimary": "#777777"},
            ]
            (home / ".config/theme-switcher/themes.json").write_text(json.dumps(entries))
            os.environ["HOME"] = str(home)
            os.environ["OMARCHY_PATH"] = str(omarchy)
            spec = importlib.util.spec_from_file_location("theme_picker", THEME_PICKER)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            mapped = module.mapped_themes(entries)
            self.assertEqual({item["theme"]["id"] for item in mapped}, {"tokyo-night", "catppuccin-latte"})
            self.assertIn("\x1finfo\x1ftokyo-night", module.build_row(next(item for item in mapped if item["theme"]["id"] == "tokyo-night")))


if __name__ == "__main__":
    unittest.main()
