#!/bin/bash
set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hardware-mock-lib.sh"

BRIGHTNESS="$ROOT/bin/omarchy-brightness-display"
BRIGHTNESS_DDC="$ROOT/bin/omarchy-brightness-display-ddc"
BRIGHTNESS_KBD="$ROOT/bin/omarchy-brightness-keyboard"

# hw_internal_env <current-percent> -- a laptop panel driven through the internal
# backlight, with Hyprland reporting eDP-1 as focused and no Apple display.
hw_internal_env() {
  hw_new_env
  hw_install_backlight "$1"
  hw_mock omarchy-hyprland-monitor-focused "printf 'eDP-1\n'; exit 0"
  hw_mock_fail omarchy-hyprland-monitor-focused-apple
  hw_mock_osd
}

hw_level() { cat "$HW_TMP/backlight-level"; }

# ------------------------------------------------------------ internal: reading

hw_internal_env 40
hw_check_eq "an internal display read returns the current percentage" "40" "$("$BRIGHTNESS" 2>/dev/null)"
hw_not_called "brightnessctl -d intel_backlight set" \
  || hw_fail "a read must not set the backlight"

# -------------------------------------------- internal connector name handling

# A name padded with whitespace used to satisfy the old eDP-* glob and be routed
# to the internal backlight, while the Apple probe and every downstream name
# comparison were handed a name no device answers to.
"$BRIGHTNESS" --monitor "  eDP-1  " >/dev/null 2>&1
hw_not_called "ddcutil" || hw_fail "a padded internal name must not reach the DDC path"

# The bare prefixes the old globs accepted are not panel connectors, so they must
# not quietly drive the internal backlight.
hw_new_env
hw_install_backlight 40
hw_mock omarchy-hyprland-monitor-focused "printf 'eDP-1\n'; exit 0"
hw_mock_fail omarchy-hyprland-monitor-focused-apple
hw_mock_osd
hw_mock omarchy-brightness-display-ddc "printf '99\n'; exit 0"
hw_mock hyprctl "exit 0"

"$BRIGHTNESS" --monitor "eDP-" 40% >/dev/null 2>&1
hw_not_called "brightnessctl -d intel_backlight set 40%" \
  || hw_fail "a bare eDP- prefix is not a panel connector and must not drive the backlight"
hw_called "omarchy-brightness-display-ddc" || hw_fail "a bare eDP- prefix must not drive the backlight"

for internal in eDP-1 LVDS-1 DSI-2 eDP-12; do
  hw_new_env
  hw_install_backlight 40
  hw_mock omarchy-hyprland-monitor-focused "printf '%s\n'; exit 0" "$internal"
  hw_mock_fail omarchy-hyprland-monitor-focused-apple
  hw_mock_osd
  hw_mock omarchy-brightness-display-ddc "printf '99\n'; exit 0"
  "$BRIGHTNESS" "+5%" >/dev/null 2>&1
  hw_check_eq "the panel connector $internal is treated as internal" "45" "$(hw_level)"
done

# An external connector still routes to DDC, and a whitespace-padded one reaches
# the DDC helper under its trimmed name rather than matching nothing at all.
hw_new_env
hw_install_backlight 40
hw_install_ddc 0 50 100
hw_mock omarchy-hyprland-monitor-focused "printf 'DP-1\n'; exit 0"
hw_mock_fail omarchy-hyprland-monitor-focused-apple
hw_mock_osd
hw_mock omarchy-brightness-display-ddc "\"$BRIGHTNESS_DDC\" \"\${1}\" \"\${2:-}\"; exit \$?"

hw_check_eq "a padded external name is trimmed before the DDC helper sees it" "50" \
  "$("$BRIGHTNESS" --monitor " DP-1 " 2>/dev/null)"

# ------------------------------------------------------- brightness set failures

hw_internal_env 40
OMARCHY_TEST_SET_FAILS=1
export OMARCHY_TEST_SET_FAILS
hw_check_fails "a failing backlight setter is reported, not swallowed" "$BRIGHTNESS" +5%
hw_not_called "OSD -i brightness" || hw_fail "a failed brightness set must not raise a success OSD"
unset OMARCHY_TEST_SET_FAILS

hw_check "a successful set returns success" "$BRIGHTNESS" +5%
hw_check_eq "a successful set applies the requested level" "45" "$(hw_level)"
hw_check_eq "a successful set raises exactly one OSD" "1" "$(hw_osd_count)"
hw_check_eq "the OSD reports the level that was actually applied" "45" "$(hw_osd_last -p)"

# The setter succeeding and the OSD failing is still a failure for the caller.
hw_internal_env 40
hw_mock_fail omarchy-osd
hw_check_fails "a failing OSD after a real brightness change is not reported as success" \
  "$BRIGHTNESS" +5%
hw_check_eq "a failing OSD does not undo the brightness change" "45" "$(hw_level)"

# ------------------------------------------------------------- DPMS propagation

hw_internal_env 40
hw_mock hyprctl "printf 'hyprctl %s\n' \"\$*\" >>\"\$OMARCHY_TEST_LOG\"; exit \${OMARCHY_TEST_HYPRCTL_RC:-0}"

hw_check "display off succeeds when hyprctl accepts the dispatch" "$BRIGHTNESS" off
hw_called 'hl.dsp.dpms({ action = "disable" })' || hw_fail "off must dispatch a DPMS disable"

OMARCHY_TEST_HYPRCTL_RC=1
export OMARCHY_TEST_HYPRCTL_RC
hw_check_fails "a rejected DPMS disable is reported, not silently succeeded" "$BRIGHTNESS" off
unset OMARCHY_TEST_HYPRCTL_RC

# With every active monitor already lit the dispatch is skipped entirely.
hw_lit_env() {
  hw_new_env

  cat >"$HW_TMP/bin/hyprctl" <<'MOCK'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true
if [[ $1 == monitors ]]; then
  json='[{"name":"eDP-1","disabled":false,"dpmsStatus":true}]'
  [[ -n ${OMARCHY_TEST_MONITORS_JSON:-} ]] && json="$OMARCHY_TEST_MONITORS_JSON"
  printf '%s\n' "$json"
  exit 0
fi
exit "${OMARCHY_TEST_HYPRCTL_RC:-0}"
MOCK
  chmod +x "$HW_TMP/bin/hyprctl"
}

hw_lit_env
hw_check "display on succeeds when a display is already lit" "$BRIGHTNESS" on
hw_not_called 'hl.dsp.dpms({ action = "enable" })' \
  || hw_fail "a redundant DPMS enable must be skipped when the panel is already lit"

hw_lit_env
OMARCHY_TEST_MONITORS_JSON='[{"name":"eDP-1","disabled":false,"dpmsStatus":false}]'
export OMARCHY_TEST_MONITORS_JSON
OMARCHY_TEST_HYPRCTL_RC=1
export OMARCHY_TEST_HYPRCTL_RC
hw_check_fails "a rejected DPMS enable is reported, not silently succeeded" "$BRIGHTNESS" on
hw_called 'hl.dsp.dpms({ action = "enable" })' || hw_fail "display on must dispatch a DPMS enable"
unset OMARCHY_TEST_MONITORS_JSON OMARCHY_TEST_HYPRCTL_RC

# ------------------------------------------------------------ argument rejection

hw_internal_env 40
for bad in "50" "+" "%" "5 %" "1000%" "50%%" "up" "" "1e2%" " 50%"; do
  hw_check_fails "a malformed brightness step '$bad' is rejected" "$BRIGHTNESS" "$bad"
done
hw_check_fails "a missing --monitor value is rejected" "$BRIGHTNESS" --monitor
hw_check_fails "a trailing second step is rejected" "$BRIGHTNESS" +5% -5%
hw_not_called "brightnessctl -d intel_backlight set" \
  || hw_fail "a rejected invocation must not move the backlight"
hw_check_eq "a rejected invocation leaves the backlight untouched" "40" "$(hw_level)"

# ------------------------------------------------------------- step boundaries

hw_internal_env 100
"$BRIGHTNESS" +5% >/dev/null 2>&1
hw_check_eq "a step up at maximum stays at 100" "100" "$(hw_level)"

hw_internal_env 5
"$BRIGHTNESS" 5%- >/dev/null 2>&1
hw_check_eq "a step down at 5 uses the single-percent step" "4" "$(hw_level)"

hw_internal_env 6
"$BRIGHTNESS" 5%- >/dev/null 2>&1
hw_check_eq "a step down above 5 uses the full step" "1" "$(hw_level)"

hw_internal_env 1
"$BRIGHTNESS" 5%- >/dev/null 2>&1
hw_check_eq "a step down at the minimum never goes below one percent" "1" "$(hw_level)"

hw_internal_env 4
"$BRIGHTNESS" +5% >/dev/null 2>&1
hw_check_eq "a step up below 5 uses the single-percent step" "5" "$(hw_level)"

hw_internal_env 1
"$BRIGHTNESS" 1% >/dev/null 2>&1
hw_check_eq "an absolute set to one percent is honoured" "1" "$(hw_level)"

hw_internal_env 50
"$BRIGHTNESS" 100% >/dev/null 2>&1
hw_check_eq "an absolute set to 100 percent is honoured" "100" "$(hw_level)"

# The precise ALT bindings use one-percent steps, which must be accepted too.
hw_internal_env 50
hw_check "a precise one-percent step up is accepted" "$BRIGHTNESS" +1%
hw_check_eq "a precise one-percent step up applies one percent" "51" "$(hw_level)"

hw_internal_env 51
hw_check "a precise one-percent step down is accepted" "$BRIGHTNESS" 1%-
hw_check_eq "a precise one-percent step down applies one percent" "50" "$(hw_level)"

# --no-osd changes the level but never raises an OSD.
hw_internal_env 40
hw_check "a brightness change succeeds with --no-osd" "$BRIGHTNESS" --no-osd +5%
hw_check_eq "--no-osd still applies the change" "45" "$(hw_level)"
hw_check_eq "--no-osd raises no OSD" "0" "$(hw_osd_count)"

# ------------------------------------------------- private lock, never /tmp

hw_internal_env 40
"$BRIGHTNESS" +5% >/dev/null 2>&1
[[ -f "$XDG_RUNTIME_DIR/omarchy-brightness-display.lock" ]] \
  || hw_fail "the brightness lock must live in the private runtime directory"
[[ ! -e /tmp/omarchy-brightness-display.lock ]] \
  || hw_fail "the brightness lock must never appear at a predictable /tmp path"

# With no runtime directory at all the script must still work, using a private
# state directory rather than /tmp.
hw_internal_env 40
env -u XDG_RUNTIME_DIR "$BRIGHTNESS" +5% >/dev/null 2>&1
hw_check_eq "a brightness change works with no XDG_RUNTIME_DIR" "45" "$(hw_level)"
[[ ! -e /tmp/omarchy-brightness-display.lock ]] \
  || hw_fail "no XDG_RUNTIME_DIR must not produce a /tmp lock"
[[ -f "$XDG_STATE_HOME/omarchy/omarchy-brightness-display.lock" ]] \
  || hw_fail "the fallback lock must live under the private state directory"
[[ $(stat -c '%a' "$XDG_STATE_HOME/omarchy") == "700" ]] \
  || hw_fail "the fallback state directory must not be world-readable"

# Rapid repeats. Sequential presses are never dropped.
hw_internal_env 50
for _ in $(seq 1 12); do
  "$BRIGHTNESS" +5% >/dev/null 2>&1
done
hw_check_eq "twelve sequential presses each land a five-percent step" "100" "$(hw_level)"
hw_check_eq "twelve sequential presses raise twelve OSDs" "12" "$(hw_osd_count)"

# Concurrent presses are deliberately dropped by the lock, but never interleaved:
# every invocation that did apply a change must show up in the OSD count, and the
# final level must equal the starting level plus five per applied change.
hw_internal_env 50
for _ in $(seq 1 12); do
  "$BRIGHTNESS" +5% >/dev/null 2>&1 &
done
wait
applied="$(hw_osd_count)"
level="$(hw_level)"
if ((applied > 0 && applied <= 12 && level == 50 + applied * 5)); then
  hw_ok "concurrent presses apply cleanly with no lost updates (applied $applied)"
else
  hw_fail "concurrent presses lost or duplicated updates (applied $applied, level $level)"
fi

# The lock must actually be held: while one invocation is inside its OSD, a
# second one must be dropped rather than racing it.
hw_internal_env 50
hw_mock omarchy-osd 'sleep 1; printf "OSD %s\n" "$*" >>"$OMARCHY_TEST_LOG"; exit 0'
"$BRIGHTNESS" +5% >/dev/null 2>&1 &
sleep 0.3
hw_check "a brightness change holds the lock while it is running" "$BRIGHTNESS" +5%
wait
hw_check_eq "a dropped overlapping press raises no second OSD" "1" "$(hw_osd_count)"
hw_check_eq "a dropped overlapping press moves the backlight only once" "55" "$(hw_level)"

# With no writable private directory the lock is skipped, not faked somewhere
# shared: the change still applies, only without mutual exclusion.
hw_internal_env 50
chmod 500 "$XDG_RUNTIME_DIR"
hw_check "a brightness change works with an unwritable runtime directory" "$BRIGHTNESS" +5%
hw_check_eq "an unwritable runtime directory still applies the change" "55" "$(hw_level)"
chmod 700 "$XDG_RUNTIME_DIR"

# A lock file another user could pre-create must not be created in /tmp, and a
# pre-created /tmp lock must not be honoured.
hw_internal_env 50
: >/tmp/omarchy-brightness-display.lock 2>/dev/null || true
hw_check "a pre-created /tmp lock does not block a brightness change" "$BRIGHTNESS" +5%
hw_check_eq "a pre-created /tmp lock does not change the applied level" "55" "$(hw_level)"
rm -f /tmp/omarchy-brightness-display.lock 2>/dev/null || true

# ------------------------------------------------------------- DDC / CI display

hw_new_env
hw_install_ddc 0 50 100
hw_mock_osd

hw_check_eq "a DDC read returns the monitor percentage" "50" "$("$BRIGHTNESS_DDC" DP-1 2>/dev/null)"
hw_check_eq "a DDC step up returns the new percentage" "55" "$("$BRIGHTNESS_DDC" DP-1 +5% 2>/dev/null)"
hw_check_eq "a DDC step up reaches the monitor" "55" "$(cat "$HW_TMP/ddc-current")"
hw_check_eq "a DDC step down returns the new percentage" "50" "$("$BRIGHTNESS_DDC" DP-1 5%- 2>/dev/null)"

"$BRIGHTNESS_DDC" DP-1 20% >/dev/null 2>&1
hw_check_eq "a DDC absolute set reaches the monitor" "20" "$(cat "$HW_TMP/ddc-current")"
hw_check_eq "a DDC absolute set above maximum clamps" "100" "$("$BRIGHTNESS_DDC" DP-1 500% 2>/dev/null)"
hw_check_eq "a DDC step up past maximum clamps" "100" "$("$BRIGHTNESS_DDC" DP-1 +5% 2>/dev/null)"

hw_new_env
hw_install_ddc 0 2 100
hw_mock_osd
hw_check_eq "a DDC step down at the bottom clamps" "1" "$("$BRIGHTNESS_DDC" DP-1 5%- 2>/dev/null)"
hw_check_eq "a DDC absolute set below the bottom clamps" "1" "$("$BRIGHTNESS_DDC" DP-1 0% 2>/dev/null)"

hw_new_env
hw_install_ddc 0 3 100
hw_mock_osd
hw_check_eq "a DDC step up below five uses a single percent" "4" "$("$BRIGHTNESS_DDC" DP-1 +5% 2>/dev/null)"

hw_new_env
hw_install_ddc 0 5 100
hw_mock_osd
hw_check_eq "a DDC step down at five uses a single percent" "4" "$("$BRIGHTNESS_DDC" DP-1 5%- 2>/dev/null)"

hw_new_env
hw_install_ddc 0 0 100
hw_mock_osd
hw_check_eq "a DDC read at zero brightness still reports zero" "0" \
  "$("$BRIGHTNESS_DDC" DP-1 2>/dev/null)"

# Failure propagation on the write.
hw_new_env
hw_install_ddc 0 50 100
hw_mock_osd
OMARCHY_TEST_SET_FAILS=1
export OMARCHY_TEST_SET_FAILS
hw_check_fails "a rejected DDC set is reported" "$BRIGHTNESS_DDC" DP-1 +5%
unset OMARCHY_TEST_SET_FAILS

# A rejected set must not leave a cached bus behind that would keep the monitor
# unavailable for the rest of the cache lifetime.
hw_new_env
hw_install_ddc 0 50 100
hw_mock_osd
OMARCHY_TEST_SETVCP_FAILS=1
export OMARCHY_TEST_SETVCP_FAILS
"$BRIGHTNESS_DDC" DP-1 +5% >/dev/null 2>&1
unset OMARCHY_TEST_SETVCP_FAILS
hw_check_eq "a rejected DDC set leaves no stale bus cache" "55" \
  "$("$BRIGHTNESS_DDC" DP-1 +5% 2>/dev/null)"

# Argument rejection on the helper.
hw_new_env
hw_install_ddc 0 50 100
hw_mock_osd
hw_check_fails "a missing monitor is rejected" "$BRIGHTNESS_DDC"
for bad in "5" "up" "%" "5 %" "+%" "-%"; do
  hw_check_fails "a malformed DDC step '$bad' is rejected" "$BRIGHTNESS_DDC" DP-1 "$bad"
done
hw_check_fails "a trailing third argument is rejected" "$BRIGHTNESS_DDC" DP-1 50% extra
hw_not_called "setvcp" || hw_fail "a rejected DDC step must not touch the bus"

# A DDC setter failure must surface through the front-end too, with no OSD.
hw_new_env
hw_install_backlight 40
hw_install_ddc 0 50 100
hw_mock omarchy-hyprland-monitor-focused "printf 'DP-1\n'; exit 0"
hw_mock_fail omarchy-hyprland-monitor-focused-apple
hw_mock_osd
hw_mock omarchy-brightness-display-ddc "\"$BRIGHTNESS_DDC\" \"\${1}\" \"\${2:-}\"; exit \$?"
OMARCHY_TEST_SETVCP_FAILS=1
export OMARCHY_TEST_SETVCP_FAILS
hw_check_fails "a rejected DDC set is reported through the front-end" "$BRIGHTNESS" +5%
hw_not_called "OSD -i brightness" || hw_fail "a rejected DDC set must not raise a success OSD"
unset OMARCHY_TEST_SETVCP_FAILS

# A monitor with no DDC bus at all.
hw_new_env
hw_install_ddc 0 50 100
hw_mock_osd
OMARCHY_TEST_NO_BUS=1
export OMARCHY_TEST_NO_BUS
hw_check_fails "a monitor with no I2C bus is reported" "$BRIGHTNESS_DDC" DP-1
unset OMARCHY_TEST_NO_BUS

# A bus whose connector does not match the requested monitor.
hw_new_env
hw_install_ddc 0 50 100
hw_mock_osd
OMARCHY_TEST_CONNECTOR="card1-HDMI-A-1"
export OMARCHY_TEST_CONNECTOR
hw_check_fails "a bus on another connector is reported" "$BRIGHTNESS_DDC" DP-1
unset OMARCHY_TEST_CONNECTOR

# Private DDC cache, never /tmp.
hw_new_env
hw_install_ddc 0 50 100
hw_mock_osd
"$BRIGHTNESS_DDC" DP-1 >/dev/null 2>&1
[[ -f "$XDG_RUNTIME_DIR/omarchy-brightness-display-ddc/DP-1.bus" ]] \
  || hw_fail "the DDC bus cache must live in the private runtime directory"
[[ ! -e /tmp/omarchy-brightness-display-ddc ]] \
  || hw_fail "the DDC bus cache must never appear at a predictable /tmp path"

# A pre-poisoned /tmp cache must not be honoured: another user must not be able
# to pin a display as unavailable or redirect it to a bus of their choosing.
hw_new_env
hw_install_ddc 7 50 100
hw_mock_osd
mkdir -p /tmp/omarchy-brightness-display-ddc 2>/dev/null || true
printf 'unavailable %s\n' "$(( $(date +%s) + 3600 ))" \
  >/tmp/omarchy-brightness-display-ddc/DP-1.bus 2>/dev/null || true
hw_check_eq "a poisoned /tmp cache does not disable a working monitor" "50" \
  "$("$BRIGHTNESS_DDC" DP-1 2>/dev/null)"
rm -rf /tmp/omarchy-brightness-display-ddc 2>/dev/null || true

# With no runtime directory the helper still works, and still writes nothing to
# /tmp.
hw_new_env
hw_install_ddc 0 50 100
hw_mock_osd
hw_check_eq "a DDC read works with no XDG_RUNTIME_DIR" "50" \
  "$(env -u XDG_RUNTIME_DIR "$BRIGHTNESS_DDC" DP-1 2>/dev/null)"
[[ ! -e /tmp/omarchy-brightness-display-ddc/DP-1.bus ]] \
  || hw_fail "no XDG_RUNTIME_DIR must not produce a /tmp cache file"
[[ -f "$XDG_STATE_HOME/omarchy/omarchy-brightness-display-ddc/DP-1.bus" ]] \
  || hw_fail "the fallback DDC cache must live under the private state directory"

# Rapid repeated DDC steps stay inside the monitor's range, and the cached bus is
# reused so a burst of presses runs one detection.
hw_new_env
hw_install_ddc 0 50 100
hw_mock_osd "sleep 0.1; exit 0"
for _ in $(seq 1 6); do
  "$BRIGHTNESS_DDC" DP-1 +5% >/dev/null 2>&1 &
done
wait
hw_check_between "overlapping DDC steps keep the level in range" 1 100 "$(cat "$HW_TMP/ddc-current")"

hw_new_env
hw_install_ddc 0 50 100
hw_mock_osd
for _ in $(seq 1 8); do
  "$BRIGHTNESS_DDC" DP-1 +1% >/dev/null 2>&1
done
hw_check_eq "a burst of DDC presses detects the bus once" "1" \
  "$(hw_call_count 'ddcutil --skip-ddc-checks detect --brief')"

# ------------------------------------------------------------------- keyboard

hw_kbd_env() {
  local max="${1:-512}"
  local level="${2:-0}"

  hw_new_env
  mkdir -p "$OMARCHY_KEYBOARD_BACKLIGHT_PATH/dell::kbd_backlight"
  printf '%s\n' "$max" >"$OMARCHY_KEYBOARD_BACKLIGHT_PATH/dell::kbd_backlight/max_brightness"
  printf '%s\n' "$level" >"$OMARCHY_KEYBOARD_BACKLIGHT_PATH/dell::kbd_backlight/brightness"
  hw_mock omarchy-osd 'printf "OSD %s\n" "$*" >>"$OMARCHY_TEST_LOG"; exit 0'

  cat >"$HW_TMP/bin/brightnessctl" <<'MOCK'
#!/bin/bash
printf 'brightnessctl %s\n' "$*" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true

device=""
step=""
prev=""
subdev=0
hasset=0
for arg in "$@"; do
  case "$prev" in
    -d | -sd | -rd) device="$arg" ;;
    set) step="$arg"; hasset=1 ;;
  esac
  case "$arg" in
    -sd | -rd) subdev=1 ;;
  esac
  prev="$arg"
done

if [[ ${OMARCHY_TEST_SET_FAILS:-0} == 1 ]]; then
  echo "Error: failed" >&2
  exit 1
fi

if [[ $subdev == 1 ]]; then
  if [[ $hasset == 1 ]]; then
    printf '0\n' >"$OMARCHY_KEYBOARD_BACKLIGHT_PATH/$device/brightness"
  fi
  exit 0
fi

if [[ -n $step ]]; then
  printf '%s\n' "$step" >"$OMARCHY_KEYBOARD_BACKLIGHT_PATH/$device/brightness"
  exit 0
fi

case "$*" in
  *max*) cat "$OMARCHY_KEYBOARD_BACKLIGHT_PATH/$device/max_brightness"; exit 0 ;;
  *get*) cat "$OMARCHY_KEYBOARD_BACKLIGHT_PATH/$device/brightness"; exit 0 ;;
esac
exit 0
MOCK
  chmod +x "$HW_TMP/bin/brightnessctl"
}

hw_kbd_level() { cat "$OMARCHY_KEYBOARD_BACKLIGHT_PATH/dell::kbd_backlight/brightness"; }
hw_kbd_set() { printf '%s\n' "$1" >"$OMARCHY_KEYBOARD_BACKLIGHT_PATH/dell::kbd_backlight/brightness"; }

hw_kbd_env
hw_kbd_set 100
"$BRIGHTNESS_KBD" up >/dev/null 2>&1
hw_check_eq "keyboard up steps by a tenth of the range" "151" "$(hw_kbd_level)"

hw_kbd_env 5 1
"$BRIGHTNESS_KBD" up >/dev/null 2>&1
hw_check_eq "keyboard up uses a one-level step on a five-level keyboard" "2" "$(hw_kbd_level)"

hw_kbd_env
hw_kbd_set 0
"$BRIGHTNESS_KBD" down >/dev/null 2>&1
hw_check_eq "keyboard down at the bottom stays at zero" "0" "$(hw_kbd_level)"

hw_kbd_env
hw_kbd_set 50
"$BRIGHTNESS_KBD" down >/dev/null 2>&1
hw_check_eq "keyboard down steps by a tenth of the range" "0" "$(hw_kbd_level)"

hw_kbd_env
hw_kbd_set 50
"$BRIGHTNESS_KBD" cycle >/dev/null 2>&1
hw_check_eq "keyboard cycle steps up" "101" "$(hw_kbd_level)"

hw_kbd_env
hw_kbd_set 500
"$BRIGHTNESS_KBD" cycle >/dev/null 2>&1
hw_check_eq "keyboard cycle wraps past the maximum" "0" "$(hw_kbd_level)"

hw_kbd_env
hw_kbd_set 470
"$BRIGHTNESS_KBD" up >/dev/null 2>&1
hw_check_eq "keyboard up clamps at the maximum" "512" "$(hw_kbd_level)"
hw_check_eq "keyboard up raises an OSD at the maximum" "100" "$(hw_osd_last -p)"

hw_kbd_env
hw_kbd_set 205
"$BRIGHTNESS_KBD" up >/dev/null 2>&1
hw_check_eq "keyboard up raises an OSD progress relative to the maximum" "50" "$(hw_osd_last -p)"

# off and restore do not consult the range, and do not raise a brightness OSD.
hw_kbd_env
hw_kbd_set 200
hw_check "keyboard off succeeds" "$BRIGHTNESS_KBD" off
hw_called "brightnessctl -sd dell::kbd_backlight set 0" || hw_fail "keyboard off must set the level to zero"
hw_check_eq "keyboard off zeros the level" "0" "$(hw_kbd_level)"
hw_check_eq "keyboard off raises no OSD" "0" "$(hw_osd_count)"

hw_kbd_env
hw_check "keyboard restore succeeds" "$BRIGHTNESS_KBD" restore
hw_called "brightnessctl -rd dell::kbd_backlight" || hw_fail "keyboard restore must restore the level"
hw_check_eq "keyboard restore raises no OSD" "0" "$(hw_osd_count)"

# --no-osd changes the level but raises nothing.
hw_kbd_env
hw_kbd_set 100
hw_check "keyboard up succeeds with --no-osd" "$BRIGHTNESS_KBD" --no-osd up
hw_check_eq "--no-osd still applies the keyboard change" "151" "$(hw_kbd_level)"
hw_check_eq "--no-osd raises no OSD" "0" "$(hw_osd_count)"

# Invalid directions.
hw_kbd_env
hw_kbd_set 100
for bad in sideways UP Up "" "-" "up down" "on"; do
  hw_check_fails "an invalid keyboard direction '$bad' is rejected" "$BRIGHTNESS_KBD" "$bad"
done
hw_check_fails "a missing keyboard direction is rejected" "$BRIGHTNESS_KBD"
hw_check_fails "a trailing second direction is rejected" "$BRIGHTNESS_KBD" up down
hw_check_eq "a rejected keyboard direction leaves the level untouched" "100" "$(hw_kbd_level)"
hw_check_eq "a rejected keyboard direction raises no OSD" "0" "$(hw_osd_count)"

# A rejected direction used to fall through to the down branch, which reported
# success while darkening the keyboard.
hw_kbd_env
hw_kbd_set 200
hw_check_fails "an invalid direction does not quietly darken the keyboard" "$BRIGHTNESS_KBD" sideways
hw_check_eq "the keyboard keeps its level after an invalid direction" "200" "$(hw_kbd_level)"

# Setter failure.
hw_kbd_env
hw_kbd_set 100
OMARCHY_TEST_SET_FAILS=1
export OMARCHY_TEST_SET_FAILS
hw_check_fails "a failing keyboard setter is reported" "$BRIGHTNESS_KBD" up
hw_not_called "OSD -i keyboard" || hw_fail "a failed keyboard set must not raise a success OSD"
hw_check_fails "a failing keyboard off is reported" "$BRIGHTNESS_KBD" off
hw_check_fails "a failing keyboard restore is reported" "$BRIGHTNESS_KBD" restore
unset OMARCHY_TEST_SET_FAILS

# A failing OSD after a real keyboard change is still a failure.
hw_kbd_env
hw_kbd_set 100
hw_mock_fail omarchy-osd
hw_check_fails "a failing OSD after a real keyboard change is not reported as success" \
  "$BRIGHTNESS_KBD" up

# Unreadable range and level.
hw_kbd_env
hw_kbd_set 100
hw_mock_fail brightnessctl
hw_check_fails "an unreadable keyboard range is reported" "$BRIGHTNESS_KBD" up

hw_kbd_env
hw_kbd_set 100
printf 'nonsense\n' >"$OMARCHY_KEYBOARD_BACKLIGHT_PATH/dell::kbd_backlight/brightness"
hw_check_fails "an unreadable keyboard level is reported" "$BRIGHTNESS_KBD" up

hw_kbd_env
hw_kbd_set 100
printf '0\n' >"$OMARCHY_KEYBOARD_BACKLIGHT_PATH/dell::kbd_backlight/max_brightness"
hw_check_fails "a zero keyboard range is reported" "$BRIGHTNESS_KBD" up

# A level above the reported maximum must not be trusted either.
hw_kbd_env
hw_kbd_set 900
hw_check_fails "a keyboard level above the maximum is reported" "$BRIGHTNESS_KBD" up

# No device at all.
hw_new_env
hw_mock_osd
hw_check_fails "a machine with no keyboard backlight is reported" "$BRIGHTNESS_KBD" up
hw_check_eq "no keyboard device raises no OSD" "0" "$(hw_osd_count)"

# Rapid repeated presses.
hw_kbd_env
for _ in $(seq 1 12); do
  "$BRIGHTNESS_KBD" up >/dev/null 2>&1
done
hw_check_eq "twelve rapid keyboard presses clamp at the maximum" "512" "$(hw_kbd_level)"
hw_check_eq "twelve rapid keyboard presses raise twelve OSDs" "12" "$(hw_osd_count)"

hw_kbd_env
hw_kbd_set 512
for _ in $(seq 1 12); do
  "$BRIGHTNESS_KBD" down >/dev/null 2>&1
done
hw_check_eq "twelve rapid keyboard presses clamp at zero" "0" "$(hw_kbd_level)"

hw_kbd_env
hw_kbd_set 300
for _ in $(seq 1 12); do
  "$BRIGHTNESS_KBD" cycle >/dev/null 2>&1 &
done
wait
hw_check_between "overlapping keyboard cycles keep the level in range" 0 512 "$(hw_kbd_level)"

hw_summary
