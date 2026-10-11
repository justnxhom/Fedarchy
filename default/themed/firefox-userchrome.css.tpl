/* Firefox browser chrome, recoloured to the active Fedarchy theme.
 *
 * Generated from default/themed/firefox-userchrome.css.tpl. Edit that template
 * rather than the copy in the profile: a theme switch overwrites this file.
 *
 * Firefox styles its own chrome with the design-system custom properties
 * defined in chrome/toolkit/skin/classic/global/design-system/tokens-shared.css.
 * Redefining those on :root retints the frame, toolbars, url bar, panels, side
 * bar, menus and about: pages at once, without naming a single widget selector.
 * That is deliberate: a selector list has to be re-audited against every
 * Firefox release, whereas these token names are the theme's own vocabulary and
 * an unknown one is simply ignored.
 *
 * Every declaration below is !important, and that is not optional. The active
 * theme (the built-in one, whichever it is) supplies its own values for these
 * same custom properties, and its values take precedence over a plain
 * declaration here -- a theme that sets --toolbox-background-color wins that one
 * and loses the rest, which is what a half-themed browser looks like. !important
 * outranks both a later stylesheet and an inline style, so the palette lands
 * whichever way the theme is applied. :root:root is belt and braces: the
 * doubled pseudo-class outranks the theme's :root on specificity, so the two
 * agree even if a future Firefox stops honouring !important on custom properties.
 *
 * Firefox only reads this file when
 * toolkit.legacyUserProfileCustomizations.stylesheets is true.
 * omarchy-theme-set-firefox pins that in the profile, because it cannot be
 * changed from here at all: the pref is off by default and Firefox ignores
 * userChrome.css without it.
 *
 * Web page content is deliberately untouched. This is the application chrome
 * only, which is what a desktop theme is expected to own.
 */

:root:root {
  /* Frame and titlebar. darker_bg sits a step below the window background so
   * the toolbar band reads as a separate surface rather than a flat block.
   *
   * The -inactive pair has to be set as well, and this is the same shape of gap as
   * the GTK hover colours: Firefox keeps a second set of variables for the window
   * that is not focused, and when only the active ones are themed the toolbar falls
   * back to the browser's own grey the moment you click away. The browser then
   * looked themed while in use and stock while idle -- the reverse of every other
   * application, and the giveaway that a whole state had been missed rather than a
   * single colour.
   *
   * They deliberately match the active values, so focus does not change the
   * toolbar's appearance. Nothing is lost by it: focus is already carried by the
   * tab strip and by the border, both of which still change. */
  --toolbox-background-color: {{ darker_bg }} !important;
  --toolbox-text-color: {{ fg }} !important;
  --toolbox-background-color-inactive: {{ darker_bg }} !important;
  --toolbox-text-color-inactive: {{ fg }} !important;

  /* Left at full opacity. Firefox fades the titlebar of an inactive window by
   * default, which over a themed background reads as the window going grey rather
   * than as a focus change. */
  --inactive-titlebar-opacity: 1 !important;

  --toolbar-background-color: {{ dark_bg }} !important;
  --toolbar-text-color: {{ fg }} !important;
  --toolbar-background-color-inactive: {{ dark_bg }} !important;
  --toolbar-text-color-inactive: {{ fg }} !important;
  --toolbarseparator-color: {{ mix muted background 50% }} !important;

  /* Bookmark bar, for the same reason. Firefox derives the inactive shade from
   * its own default as a mix towards white, so setting only the active one still
   * leaves it stock whenever the window is not focused. */
  --smartbar-background-color: {{ dark_bg }} !important;
  --smartbar-inactive-background-color: {{ dark_bg }} !important;

  /* Url bar and search field. The field is a shade off the toolbar so it looks
   * inset without needing a heavy border. */
  --toolbar-field-background-color: {{ background }} !important;
  --toolbar-field-background-color-focus: {{ background }} !important;
  --toolbar-field-text-color: {{ fg }} !important;
  --toolbar-field-text-color-focus: {{ fg }} !important;
  --toolbar-field-border-color: {{ mix muted background 40% }} !important;

  /* The focus border deliberately matches the resting border rather than taking
   * the accent. Every other focusable surface in the browser is marked with the
   * accent -- tabs, the sidebar, menu highlights -- so this one is the odd case
   * where the accent made the address bar look like an error or an alert the
   * moment it was clicked, rather than like the thing you were reaching for.
   * Focus stays legible: the border is still there, it just stops changing. */
  --toolbar-field-border-color-focus: {{ mix muted background 40% }} !important;

  /* Toolbar buttons.
   *
   * Every toolbar button carries `outline: 1px solid
   * var(--toolbarbutton-outline-color)`, so the outline is always drawn and only
   * its colour decides whether you see it. Firefox points that token at
   * --border-color-interactive-hover, which is invisible until hover; overriding
   * it here boxed in the back, forward, reload and new-tab buttons at once.
   * Left alone deliberately -- only the icon fill is themed. */
  --toolbarbutton-icon-fill: {{ fg }} !important;

  /* Buttons and general text. */
  --button-background-color: {{ mix muted background 30% }} !important;
  --button-background-color-hover: {{ mix muted background 45% }} !important;
  --button-background-color-active: {{ mix muted background 60% }} !important;
  --button-text-color: {{ fg }} !important;
  --text-color: {{ fg }} !important;
  --text-color-deemphasized: {{ muted }} !important;
  --icon-color: {{ fg }} !important;

  /* Surfaces: the page canvas, cards, and the table styling about: pages use. */
  --background-color-canvas: {{ background }} !important;
  --card-background-color: {{ dark_bg }} !important;
  --table-background-color: {{ background }} !important;
  --table-header-background-color: {{ dark_bg }} !important;
  --table-border-color: {{ mix muted background 40% }} !important;

  /* Popovers, panels, and the sidebar (bookmarks, history). */
  --panel-background-color: {{ background }} !important;
  --panel-text-color: {{ fg }} !important;
  --panel-border-color: {{ mix muted background 50% }} !important;
  --panel-separator-color: {{ mix muted background 40% }} !important;
  --popup-background-color: {{ background }} !important;
  --popup-border-color: {{ mix muted background 50% }} !important;
  --sidebar-background-color: {{ background }} !important;
  --sidebar-text-color: {{ fg }} !important;
  --sidebar-border-color: {{ mix muted background 50% }} !important;

  /* Inputs, so a text field inside a dialog matches the url bar. */
  --input-text-background-color: {{ background }} !important;
  --input-text-color: {{ fg }} !important;
  --input-text-border-color: {{ mix muted background 50% }} !important;

  /* Accent, for selection, focus rings, and the primary action. */
  --color-accent-primary: {{ accent }} !important;
  --color-accent-primary-hover: {{ mix accent fg 25% }} !important;
  --color-accent-primary-active: {{ mix accent background 25% }} !important;
  --color-accent-primary-selected: {{ mix accent background 15% }} !important;
  --focus-outline-color: {{ accent }} !important;
  --focus-outline-color-inactive: {{ muted }} !important;
  --text-color-accent-primary-selected: {{ fg }} !important;
  --button-text-color-primary: {{ background }} !important;
  --button-background-color-primary: {{ accent }} !important;

  /* Links. */
  --link-color: {{ blue }} !important;
  --link-color-hover: {{ mix blue fg 25% }} !important;
  --link-color-active: {{ mix blue fg 40% }} !important;

  /* Tabs.
   *
   * Every tab's background is drawn with `outline: 1px solid
   * var(--tab-outline-color)`, so the outline is always there and only its
   * colour decides whether you see it. Firefox's value is transparent: tabs
   * carry no edge of their own and the selected one is told apart by its fill.
   * Stated explicitly rather than left to a default, because that default is
   * the difference between a tab strip and a row of boxes. */
  --tab-outline-color: transparent !important;
  --tab-hover-outline-color: transparent !important;

  /* The one border that is wanted: the tab you are actually on. Applied to the
   * selected tab's background rather than through --tab-outline-color, which
   * would draw it on every tab. */
  --tab-selected-outline-color: {{ mix accent foreground 15% }} !important;
}

#tabbrowser-tabs .tabbrowser-tab[selected] > .tab-stack > .tab-background {
  outline: 1px solid var(--tab-selected-outline-color) !important;
  outline-offset: -1px !important;
}
