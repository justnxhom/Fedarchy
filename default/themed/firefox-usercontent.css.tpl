/* Firefox new tab page: background and furniture.
 *
 * Generated from default/themed/firefox-usercontent.css.tpl. Edit that template,
 * or drop your own copy at ~/.config/omarchy/themed/firefox-usercontent.css.tpl
 * to override it. A theme switch rewrites this file.
 *
 * This lives in userContent.css rather than userChrome.css on purpose:
 * about:newtab is a content page, not browser chrome, so userChrome.css never
 * reaches it. The palette for the browser's own furniture is in the other file.
 *
 * Note the scope this implies. userContent.css is applied to EVERY page you
 * load, not just about:newtab, so nothing here may style a bare element
 * selector. A `body { background-color: ... }` rule here would repaint every
 * website you visit. The background is therefore set through Firefox's own
 * custom property, which only about: pages know how to read -- the page paints
 * itself with `body { background-color: var(--newtab-background-color) }`, so
 * overriding the property is the supported way in, and inert everywhere else.
 */

:root:root {
  /* The new tab background is the theme's accent, so opening a new tab shows the
   * theme's identity colour rather than another shade of the same dark panel.
   *
   * The text has to be set here too, and it is `background` rather than
   * `foreground`. Every foreground in a typical palette is light, and most accents
   * are mid-to-light as well, so pairing them puts light text on a light
   * background: measured across the installed themes, foreground on accent falls
   * under 4.5:1 for all but four of them. Background on accent clears 4.5:1 for
   * the other 22, with hinterlands (2.86) and rose-pine (3.14) the weakest.
   * Neither is a decision the template engine can make for itself -- it offers
   * only mix/mix_strip/mix_rgb and no luminance function, so it cannot ask which of
   * two colours is readable on this particular accent. */
  --newtab-background-color: {{ accent }} !important;
  --newtab-text-primary-color: {{ background }} !important;
  --newtab-text-secondary-color: {{ mix background accent 25% }} !important;

  /* The surface behind the shortcut tiles, cards and menus, which sit on the
   * background above. Nudged back towards the background so a tile reads as a
   * tile rather than vanishing into the page. This one also matters twice over:
   * the page draws a box-shadow in it around every shortcut, to fake a gap, so the
   * tiles would otherwise be ringed in the old colour. */
  --newtab-background-color-secondary: {{ mix accent background 15% }} !important;
}

/* The new tab's own furniture: the wordmark, its search field, and the
   customize control.
   The customize control needs two selectors, because Firefox builds it as one of
   two different elements depending on the browser.nova.enabled pref -- a plain
   <button class="personalize-button">, or a <moz-button class="open-customization-button">
   whose contents are drawn from a shadow root. Hiding only the first leaves the
   control on screen on a build that takes the second branch, which is what
   happened here: the icon was present, and vanished only while the panel it opens
   was animating, then came back.

   Every selector is a single class. That is not only what this file may contain --
   userContent.css is applied to every page loaded, so a compound selector could
   match an unrelated site -- it is also all that is needed. The transition adds
   its animation classes to the same element that already carries
   .personalize-button, so hiding that class hides the control in every one of its
   states. */
.logo-and-wordmark,
.logo-and-wordmark-wrapper,
.search-wrapper,
.personalize-button,
.open-customization-button,
.personalize-animate,
.customize-menu {
  display: none !important;
}
