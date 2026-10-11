# Qt colour scheme, for applications using the qt5ct / qt6ct platform theme.
#
# Generated from default/themed/qt-colors.conf.tpl. Edit that template, not this
# copy: a theme switch rewrites this file.
#
# The file is named Fedarchy.colors and installed to the user's colour-scheme
# directory; qt5ct.conf points at it by path, the same arrangement the GTK
# application configs use.
#
# One thing to know when reading the [Colors:*] sections: in Qt's palette,
# `Foreground*` roles are TEXT. ForegroundActive is the text of active and
# selected items, and ForegroundLink is hyperlink text. Setting either of those to
# the accent puts the theme's accent on ordinary text -- a selected file name in
# Dolphin, every link in a Qt application -- which reads as a mistake rather than
# as emphasis. All of them take the text colour here, and the accent stays on
# the roles that are meant to be noticed: DecorationFocus, DecorationHover, and
# the Selection background.
[ColorEffects:Disabled]
Color={{ muted_rgb }}
ColorAmount=0
ColorEffect=0
ContrastAmount=0.65
ContrastEffect=0
IntensityAmount=0.1
IntensityEffect=0

[ColorEffects:Inactive]
ChangeSelectionColor=false
Color={{ muted_rgb }}
ColorAmount=-0.1
ColorEffect=0
ContrastAmount=0.1
ContrastEffect=0
Enable=false
IntensityAmount=0
IntensityEffect=0

[Colors:Button]
BackgroundAlternate={{ lighter_background_rgb }}
BackgroundNormal={{ lighter_background_rgb }}
DecorationFocus={{ accent_rgb }}
DecorationHover={{ accent_rgb }}
ForegroundActive={{ foreground_rgb }}
ForegroundInactive={{ muted_rgb }}
ForegroundLink={{ foreground_rgb }}
ForegroundNegative={{ red_rgb }}
ForegroundNeutral={{ orange_rgb }}
ForegroundNormal={{ foreground_rgb }}
ForegroundPositive={{ green_rgb }}
ForegroundVisited={{ muted_rgb }}

[Colors:Complementary]
BackgroundAlternate={{ background_rgb }}
BackgroundNormal={{ background_rgb }}

[Colors:Selection]
BackgroundAlternate={{ mix_rgb lighter_background selection 50% }}
BackgroundNormal={{ selection_rgb }}
DecorationFocus={{ accent_rgb }}
DecorationHover={{ accent_rgb }}
ForegroundActive={{ foreground_rgb }}
ForegroundInactive={{ muted_rgb }}
ForegroundLink={{ foreground_rgb }}
ForegroundNegative={{ red_rgb }}
ForegroundNeutral={{ orange_rgb }}
ForegroundNormal={{ foreground_rgb }}
ForegroundPositive={{ green_rgb }}
ForegroundVisited={{ muted_rgb }}

[Colors:Tooltip]
BackgroundAlternate={{ lighter_background_rgb }}
BackgroundNormal={{ lighter_background_rgb }}
DecorationFocus={{ accent_rgb }}
DecorationHover={{ accent_rgb }}
ForegroundActive={{ foreground_rgb }}
ForegroundInactive={{ muted_rgb }}
ForegroundLink={{ foreground_rgb }}
ForegroundNegative={{ red_rgb }}
ForegroundNeutral={{ orange_rgb }}
ForegroundNormal={{ foreground_rgb }}
ForegroundPositive={{ green_rgb }}
ForegroundVisited={{ muted_rgb }}

[Colors:View]
BackgroundAlternate={{ lighter_background_rgb }}
BackgroundNormal={{ background_rgb }}
DecorationFocus={{ accent_rgb }}
DecorationHover={{ accent_rgb }}
ForegroundActive={{ foreground_rgb }}
ForegroundInactive={{ muted_rgb }}
ForegroundLink={{ foreground_rgb }}
ForegroundNegative={{ red_rgb }}
ForegroundNeutral={{ orange_rgb }}
ForegroundNormal={{ foreground_rgb }}
ForegroundPositive={{ green_rgb }}
ForegroundVisited={{ muted_rgb }}

[Colors:Window]
BackgroundAlternate={{ lighter_background_rgb }}
BackgroundNormal={{ background_rgb }}
DecorationFocus={{ accent_rgb }}
DecorationHover={{ accent_rgb }}
ForegroundActive={{ foreground_rgb }}
ForegroundInactive={{ muted_rgb }}
ForegroundLink={{ foreground_rgb }}
ForegroundNegative={{ red_rgb }}
ForegroundNeutral={{ orange_rgb }}
ForegroundNormal={{ foreground_rgb }}
ForegroundPositive={{ green_rgb }}
ForegroundVisited={{ muted_rgb }}

[General]
ColorScheme=Fedarchy
Name=Fedarchy

[KDE]
colorScheme=Fedarchy

[WM]
activeBackground={{ lighter_background_rgb }}
activeBlend={{ foreground_rgb }}
activeForeground={{ foreground_rgb }}
inactiveBackground={{ background_rgb }}
inactiveBlend={{ lighter_background_rgb }}
inactiveForeground={{ muted_rgb }}
