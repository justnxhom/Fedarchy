/* GTK application colours, set to the active Fedarchy theme.
 *
 * Generated from default/themed/gtk.css.tpl. Edit that template rather than the
 * copies in ~/.config/gtk-3.0 and ~/.config/gtk-4.0: a theme switch overwrites
 * both.
 *
 * This is written to BOTH the GTK 3 and GTK 4 directories on purpose. The two
 * are separate configurations that do not read each other, and a system running
 * this desktop has applications on both: GTK 4 for the file manager and the
 * newer GNOME tools, GTK 3 for older dialogs and utilities. A palette that
 * reached only one of them is what makes a theme look half applied.
 *
 * The named colours are the GTK 3 vocabulary, so GTK 3 widgets pick the
 * palette up without any of the rules below having to match them. The rules
 * then handle what those names do not cover, above all the plain window and
 * file-view backgrounds: GTK 4 draws those from its own theme rather than from
 * a named colour, which is why styling only the headerbar leaves the file
 * manager looking themed on top and stock everywhere else.
 */

@define-color bg_color {{ background }};
@define-color fg_color {{ foreground }};
@define-color accent_color {{ accent }};
@define-color surface_color {{ lighter_background }};
@define-color muted_color {{ muted }};

/* GTK 3 named palette. */
@define-color theme_fg_color {{ foreground }};
@define-color theme_bg_color {{ background }};
@define-color theme_base_color {{ background }};
@define-color theme_text_color {{ foreground }};
@define-color theme_selected_bg_color {{ selection }};
@define-color theme_selected_fg_color {{ foreground }};
@define-color insensitive_bg_color {{ dark_background }};
@define-color insensitive_fg_color {{ muted }};
@define-color insensitive_base_color {{ background }};
@define-color borders {{ mix muted background 50% }};
/* Link text takes the foreground, not a hue of its own.
 *
 * `link_color` and `visited_link_color` are named colours: redefining them here
 * overrides them for every GTK application at once, not just the ones this
 * stylesheet names. Most themes set link_color to a blue close to the accent,
 * and where a theme's `blue` *is* its accent -- gruvbox uses #7daea3 for both --
 * that made every link render in the theme accent, which reads as a mistake
 * rather than as emphasis. The accent stays on the things it is meant for: the
 * suggested-action background below, the focus outline, and the selection
 * background. */
@define-color link_color {{ foreground }};
@define-color visited_link_color {{ foreground }};
@define-color warning_color {{ yellow }};
@define-color error_color {{ red }};
@define-color success_color {{ green }};

/* The named surface, hover and pressed tokens.
 *
 * The generic tokens above are what GTK itself reads -- `bg_color`, `fg_color`,
 * `theme_bg_color` -- and overriding them is enough to make a window the right
 * colour at rest. It is not enough for anything that changes state, and that was
 * the whole of this file's gap: libadwaita paints hover and pressed backgrounds
 * from its own named tokens, which the theme resolves to its own greys.
 *
 * So a themed window was surrounded by theme-grey: hovering a headerbar button,
 * a sidebar row or a card produced a slab of dark grey that looked like a
 * rendering fault, while the same widget sitting idle showed the palette
 * correctly. It was only visible while interacting, which is why it read as the
 * theme not being applied at all rather than as a token that was missed.
 *
 * These are the tokens the surfaces are drawn from, plus the shades they shift to
 * on hover and press. They are defined from the palette rather than from the
 * theme, so an app stays on-theme while it is being used and not only while it is
 * being looked at.
 */
@define-color window_bg_color {{ background }};
@define-color window_fg_color {{ foreground }};
@define-color view_bg_color {{ background }};
@define-color view_fg_color {{ foreground }};
@define-color headerbar_bg_color {{ background }};
@define-color headerbar_fg_color {{ foreground }};
@define-color headerbar_border_color {{ mix muted background 50% }};
@define-color headerbar_backdrop_color {{ background }};

@define-color sidebar_bg_color {{ background }};
@define-color sidebar_fg_color {{ foreground }};
@define-color sidebar_border_color {{ mix muted background 50% }};
@define-color sidebar_backdrop_color {{ background }};

@define-color card_bg_color {{ lighter_background }};
@define-color card_fg_color {{ foreground }};
@define-color popover_bg_color {{ lighter_background }};
@define-color popover_fg_color {{ foreground }};

/* Hover is one step towards the foreground, press is a little further, so the
 * two read as the same gesture at different depths instead of as two unrelated
 * greys. */
@define-color headerbar_shade_color {{ mix background foreground 8% }};
@define-color headerbar_darker_shade_color {{ mix background foreground 14% }};
@define-color sidebar_shade_color {{ mix background foreground 8% }};
@define-color card_shade_color {{ mix lighter_background foreground 6% }};
@define-color popover_shade_color {{ mix lighter_background foreground 6% }};
@define-color shade_color {{ mix background foreground 8% }};

/* Client-side titlebar buttons. GTK draws these from their own literal colours,
 * so they stay theme-grey on hover unless they are named here. */
@define-color wm_button_hover_color_a {{ mix background foreground 12% }};
@define-color wm_button_hover_color_b {{ background }};
@define-color wm_button_active_color_a {{ mix background foreground 18% }};
@define-color wm_button_active_color_b {{ mix background foreground 14% }};
@define-color wm_button_active_color_c {{ mix background foreground 10% }};

/* Accent as a background, and the destructive pair. Left undefined they resolve
 * to the theme's own blue and red, which is what selection and the affected
 * controls fall back to. */
@define-color accent_bg_color {{ accent }};
@define-color accent_fg_color {{ foreground }};
@define-color destructive_bg_color {{ red }};
@define-color destructive_fg_color {{ foreground }};

/* The window itself. Without this the surface behind everything else stays the
 * stock theme colour, which is the most visible part of a file manager.
 *
 * Scoped to the window node deliberately. GtkPopover is styled by the
 * `popover` node but also receives the `.background` style class, so a bare
 * `.background` rule here matches every menu, popover and tooltip and paints
 * their whole allocated area with the window colour -- which reads as one large
 * rectangle instead of a card. The toplevel is the `window` node carrying that
 * same class, so `window` and `window.background` cover the real window without
 * reaching anything that floats above it. */
window,
window.background {
  background-color: @bg_color;
  color: @fg_color;
}

/* No border-bottom here.
 *
 * This rule used to carry one, and it never rendered: while the header bars
 * still had rounded corners, GTK drew the bottom edge following the curve and
 * the line was effectively invisible. Squaring the corners made it appear for
 * the first time, and it then showed a seam that did not line up -- an
 * application with two header bars of its own (a file manager with a sidebar
 * and a content view) puts them at different heights, so one line sat 5px
 * below the other.
 *
 * Leaving the border off restores the appearance this theme always had, and
 * the separation between the header bar and the content is carried by the
 * background difference instead. */
headerbar,
.titlebar {
  background-color: @bg_color;
  color: @fg_color;
}

headerbar button {
  color: @fg_color;
  background: transparent;
  border-radius: 6px;
  padding: 4px 8px;
}

headerbar button:hover {
  background: alpha(@fg_color, 0.1);
}

button.suggested-action {
  background-color: @accent_color;
  color: @bg_color;
}

/* File lists and icon views. */
view,
iconview,
listview,
textview text {
  background-color: @bg_color;
  color: @fg_color;
}

label,
entry {
  color: @fg_color;
}

selection {
  background-color: @surface_color;
  color: @fg_color;
}

* {
  -gtk-icon-style: symbolic;
  outline-color: @accent_color;
}
