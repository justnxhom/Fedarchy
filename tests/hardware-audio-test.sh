#!/bin/bash
set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hardware-mock-lib.sh"

SET_DEFAULT="$ROOT/bin/omarchy-audio-output-set-default"
SWITCH="$ROOT/bin/omarchy-audio-output-switch"
VOLUME="$ROOT/bin/omarchy-audio-output-volume"
INPUT_MUTE="$ROOT/bin/omarchy-audio-input-mute"

HW_SPK="alsa_output.pci-0000_00_1f.3.analog-stereo"
HW_HDMI="alsa_output.pci-0000_00_1f.4.hdmi-stereo"

# hw_install_pactl <volume> <muted> [sink-json-override]
# Mock pactl with a small in-memory model: one physical speaker sink and one
# HDMI sink, both driven from files the test can inspect and change.
hw_install_pactl() {
  local volume="${1:-50}"
  local muted="${2:-no}"
  local sinks_json="${3:-}"

  mkdir -p "$OMARCHY_TEST_STATE/audio"
  printf '%s\n' "$volume" >"$OMARCHY_TEST_STATE/audio/volume"
  printf '%s\n' "$muted" >"$OMARCHY_TEST_STATE/audio/muted"
  printf '%s\n' "$HW_SPK" >"$OMARCHY_TEST_STATE/audio/default"
  if [[ -z $sinks_json ]]; then
    sinks_json="$(jq -nc --arg spk "$HW_SPK" --arg hdmi "$HW_HDMI" '[
      {index: 41, name: $spk, description: "Speakers", ports: []},
      {index: 42, name: $hdmi, description: "HDMI", ports: []}
    ]')"
  fi
  printf '%s\n' "$sinks_json" >"$OMARCHY_TEST_STATE/audio/sinks.json"

  cat >"$HW_TMP/bin/pactl" <<'MOCK'
#!/bin/bash
printf 'pactl %s\n' "$*" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true

state="$OMARCHY_TEST_STATE/audio"
command_name=""
args=()
for arg in "$@"; do
  [[ -z $command_name && $arg == -* ]] && continue
  [[ -z $command_name ]] && { command_name="$arg"; continue; }
  args+=("$arg")
done

if [[ ${OMARCHY_TEST_FAIL_LIST:-0} == 1 ]]; then
  echo "Connection refused" >&2
  exit 1
fi

case "$*" in
  *list\ sinks)
    cat "$state/sinks.json"
    exit 0
    ;;
esac

case "$command_name" in
  get-default-sink)
    [[ ${OMARCHY_TEST_FAIL_DEFAULT:-0} == 1 ]] && { echo "No such entity" >&2; exit 1; }
    cat "$state/default"
    exit 0
    ;;
  set-default-sink)
    printf '%s\n' "${args[0]}" >"$state/default"
    exit 0
    ;;
  get-sink-volume)
    [[ ${OMARCHY_TEST_FAIL_VOLUME:-0} == 1 ]] && { echo "No such entity" >&2; exit 1; }
    printf 'Volume: front-left: %s%% / %s%%,   front-right: %s%% / %s%%\n' \
      "$(cat "$state/volume")" 100 "$(cat "$state/volume")" 100
    exit 0
    ;;
  set-sink-volume)
    value="${args[1]%%%}"
    [[ $value =~ ^[0-9]+$ ]] || exit 1
    printf '%s\n' "$value" >"$state/volume"
    exit 0
    ;;
  get-sink-mute)
    printf 'Mute: %s\n' "$(cat "$state/muted")"
    exit 0
    ;;
  set-sink-mute)
    case "${args[1]}" in
      toggle)
        if [[ $(cat "$state/muted") == yes ]]; then
          printf 'no\n' >"$state/muted"
        else
          printf 'yes\n' >"$state/muted"
        fi
        ;;
      0) printf 'no\n' >"$state/muted" ;;
      1) printf 'yes\n' >"$state/muted" ;;
      *) printf '%s\n' "${args[1]}" >"$state/muted" ;;
    esac
    exit 0
    ;;
  list)
    printf 'Sink Input #0\n\tSink: %s\n\tapplication.name = "Firefox"\n' "$(cat "$state/default")"
    printf 'Sink Input #1\n\tSink: %s\n\tapplication.name = "EasyEffects"\n' "$(cat "$state/default")"
    exit 0
    ;;
  move-sink-input)
    [[ ${OMARCHY_TEST_FAIL_MOVE:-0} == 1 ]] && exit 1
    exit 0
    ;;
  get-source-mute)
    printf 'Mute: %s\n' "$(cat "$state/muted")"
    exit 0
    ;;
  set-source-mute)
    printf '%s\n' "${args[1]}" >"$state/muted"
    exit 0
    ;;
esac
exit 0
MOCK
  chmod +x "$HW_TMP/bin/pactl"

  cat >"$HW_TMP/bin/wpctl" <<'MOCK'
#!/bin/bash
printf 'wpctl %s\n' "$*" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true
state="$OMARCHY_TEST_STATE/audio"
case "$1" in
  set-default) printf '%s\n' "$2" >"$state/default"; exit 0 ;;
  set-mute)
    [[ $(cat "$state/muted") == yes ]] && printf 'no\n' >"$state/muted" || printf 'yes\n' >"$state/muted"
    exit 0
    ;;
  get-volume)
    if [[ $(cat "$state/muted") == yes ]]; then
      printf 'Volume: 1.00\n\tMUTED\n'
    else
      printf 'Volume: 1.00\n'
    fi
    exit 0
    ;;
esac
exit 0
MOCK
  chmod +x "$HW_TMP/bin/wpctl"
}

hw_audio_env() {
  hw_new_env
  hw_install_pactl "$@"
  hw_mock omarchy-audio-output-sink "printf '%s\\n' \"\${1:-\$(pactl get-default-sink 2>/dev/null)}\"; exit 0"
  hw_mock omarchy-audio-tuning "exit 0"
  hw_mock omarchy-osd 'printf "OSD %s\n" "$*" >>"$OMARCHY_TEST_LOG"; exit 0'
  hw_mock omarchy-brightness-keyboard-mute \
    "printf 'LED %s\\n' \"\$*\" >>\"\$OMARCHY_TEST_LOG\"; exit 0"
}

hw_volume() { cat "$OMARCHY_TEST_STATE/audio/volume"; }
hw_muted() { cat "$OMARCHY_TEST_STATE/audio/muted"; }
hw_default() { cat "$OMARCHY_TEST_STATE/audio/default"; }

# ------------------------------------------------ set-default: argument handling

hw_audio_env 50 no
hw_check "set-default succeeds with a valid node and sink" "$SET_DEFAULT" 41 "$HW_SPK"
hw_called "wpctl set-default 41" || hw_fail "set-default must set the WirePlumber default"
hw_called "pactl set-default-sink $HW_SPK" || hw_fail "set-default must set the PulseAudio default"
hw_check_eq "set-default leaves the resolved default in place" "$HW_SPK" "$(hw_default)"

hw_check_fails "set-default rejects a missing node id" "$SET_DEFAULT" "" "$HW_SPK"
hw_check_fails "set-default rejects a missing sink name" "$SET_DEFAULT" 41 ""
hw_check_fails "set-default rejects a non-numeric node id" "$SET_DEFAULT" "abc" "$HW_SPK"
hw_check_fails "set-default rejects a signed node id" "$SET_DEFAULT" "-1" "$HW_SPK"
hw_check_fails "set-default rejects an option-shaped sink name" "$SET_DEFAULT" 41 "--system"
hw_check_fails "set-default rejects a sink name with a space" "$SET_DEFAULT" 41 "my sink"
hw_check_fails "set-default rejects a trailing third argument" "$SET_DEFAULT" 41 "$HW_SPK" extra
hw_not_called "wpctl set-default abc" || hw_fail "a rejected node id must not reach wpctl"
hw_not_called "pactl set-default-sink --system" \
  || hw_fail "a rejected sink name must not reach pactl"

# Stream moves: application streams move, the DSP chain's own stream does not.
hw_audio_env 50 no
hw_check "set-default with active streams succeeds" "$SET_DEFAULT" 42 "$HW_HDMI"
hw_called "pactl move-sink-input 0 $HW_HDMI" || hw_fail "an application stream must be moved"
hw_not_called "pactl move-sink-input 1" || hw_fail "the EasyEffects stream must not be moved"
hw_not_called "pactl move-sink-input 2" || hw_fail "no stream past the listed ones may be moved"

# Failure propagation.
hw_audio_env 50 no
cat >"$HW_TMP/bin/wpctl" <<'MOCK'
#!/bin/bash
printf 'wpctl %s\n' "$*" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true
[[ ${OMARCHY_TEST_WPCTL_FAILS:-0} == 1 ]] && exit 1
exit 0
MOCK
chmod +x "$HW_TMP/bin/wpctl"
OMARCHY_TEST_WPCTL_FAILS=1
export OMARCHY_TEST_WPCTL_FAILS
hw_check_fails "a rejected WirePlumber default is reported" "$SET_DEFAULT" 42 "$HW_HDMI"
hw_not_called "pactl set-default-sink" \
  || hw_fail "a rejected WirePlumber default must not half-switch the sink"
unset OMARCHY_TEST_WPCTL_FAILS

hw_audio_env 50 no
cat >"$HW_TMP/bin/pactl" <<'MOCK'
#!/bin/bash
printf 'pactl %s\n' "$*" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true
[[ $1 == set-default-sink ]] && exit 1
exit 0
MOCK
chmod +x "$HW_TMP/bin/pactl"
hw_check_fails "a rejected PulseAudio default sink is reported" "$SET_DEFAULT" 42 "$HW_HDMI"
hw_called "wpctl set-default 42" \
  || hw_fail "a rejected PulseAudio default must still show the WirePlumber half applied"

# A stream that cannot be moved is reported, but the default switch still counts
# as applied -- the switcher depends on that, and the stream may simply have died.
hw_audio_env 50 no
OMARCHY_TEST_FAIL_MOVE=1
export OMARCHY_TEST_FAIL_MOVE
hw_check "a stream that cannot be moved does not fail the default switch" \
  "$SET_DEFAULT" 42 "$HW_HDMI"
hw_check_eq "a stream that cannot be moved still switches the default" "$HW_HDMI" \
  "$(hw_default)"
unset OMARCHY_TEST_FAIL_MOVE

# --------------------------------------------------------------- volume control

hw_audio_env 50 no
hw_check "volume raise succeeds" "$VOLUME" raise
hw_check_eq "volume raise adds five percent" "55" "$(hw_volume)"
hw_check_eq "volume raise raises one OSD" "1" "$(hw_osd_count)"
hw_check_eq "the volume OSD reports the new level" "55" "$(hw_osd_last -p)"

hw_audio_env 50 no
hw_check "volume lower succeeds" "$VOLUME" lower
hw_check_eq "volume lower subtracts five percent" "45" "$(hw_volume)"

hw_audio_env 50 no
"$VOLUME" +1 >/dev/null 2>&1
hw_check_eq "a precise one-percent raise adds one percent" "51" "$(hw_volume)"

hw_audio_env 50 no
"$VOLUME" -1 >/dev/null 2>&1
hw_check_eq "a precise one-percent lower subtracts one percent" "49" "$(hw_volume)"

hw_audio_env 98 no
"$VOLUME" raise >/dev/null 2>&1
hw_check_eq "a raise past maximum clamps at 100" "100" "$(hw_volume)"
hw_check_eq "a clamped raise raises the high icon" "volume-high" "$(hw_osd_last -i)"

hw_audio_env 2 no
"$VOLUME" lower >/dev/null 2>&1
hw_check_eq "a lower past the bottom clamps at 0" "0" "$(hw_volume)"
hw_check_eq "a clamped lower raises the muted icon" "volume-muted" "$(hw_osd_last -i)"

hw_audio_env 33 no
"$VOLUME" raise >/dev/null 2>&1
hw_check_eq "a raise out of the low band raises the medium icon" "volume-medium" \
  "$(hw_osd_last -i)"

hw_audio_env 65 no
"$VOLUME" raise >/dev/null 2>&1
hw_check_eq "a raise out of the medium band raises the high icon" "volume-high" \
  "$(hw_osd_last -i)"

hw_audio_env 50 no
hw_check "volume mute-toggle succeeds" "$VOLUME" mute-toggle
hw_check_eq "volume mute-toggle mutes the sink" "yes" "$(hw_muted)"
hw_check_eq "volume mute-toggle raises the muted icon" "volume-muted" "$(hw_osd_last -i)"

# The second press has to land outside the debounce window to count.
printf '0\n' >"$XDG_RUNTIME_DIR/omarchy-audio-output-volume-mute-toggle.last"
"$VOLUME" mute-toggle >/dev/null 2>&1
hw_check_eq "a mute-toggle outside the debounce window unmutes the sink" "no" "$(hw_muted)"
hw_check_eq "an unmuted sink raises a level icon" "volume-medium" "$(hw_osd_last -i)"

# A garbage stamp must not suppress every future toggle.
printf 'not-a-timestamp\n' >"$XDG_RUNTIME_DIR/omarchy-audio-output-volume-mute-toggle.last"
hw_check "a garbage debounce stamp does not suppress the next toggle" "$VOLUME" mute-toggle
hw_check_eq "a garbage debounce stamp leaves the sink muted" "yes" "$(hw_muted)"

# A stamp from the future must not lock the key out forever.
printf '%s\n' "$(( $(date +%s) * 1000 + 600000 ))" \
  >"$XDG_RUNTIME_DIR/omarchy-audio-output-volume-mute-toggle.last"
hw_check "a future debounce stamp does not lock the key out" "$VOLUME" mute-toggle
hw_check_eq "a future debounce stamp leaves the sink unmuted" "no" "$(hw_muted)"

# Muted but non-zero must still read as muted, not as a level.
hw_audio_env 50 yes
hw_check "a volume change on a muted sink succeeds" "$VOLUME" +1
hw_check_eq "a volume change on a muted sink unmutes it" "no" "$(hw_muted)"
hw_check_eq "a volume change on a muted sink reports the new level" "51" "$(hw_volume)"
hw_check_eq "an unmuted non-zero level raises the level icon" "volume-medium" \
  "$(hw_osd_last -i)"

# Argument rejection.
hw_audio_env 50 no
for bad in "" "sideways" "+" "-" "+0" "-0" "+abc" "mute" "toggle"; do
  hw_check_fails "an invalid volume action '$bad' is rejected" "$VOLUME" "$bad"
done
hw_check_fails "a trailing second volume action is rejected" "$VOLUME" raise lower
hw_check_eq "a rejected volume action leaves the level untouched" "50" "$(hw_volume)"
hw_check_eq "a rejected volume action raises no OSD" "0" "$(hw_osd_count)"

# Failure propagation.
hw_audio_env 50 no
cat >"$HW_TMP/bin/pactl" <<'MOCK'
#!/bin/bash
printf 'pactl %s\n' "$*" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true
[[ ${OMARCHY_TEST_PACTL_FAILS:-0} == 1 ]] && { echo "Connection refused" >&2; exit 1; }
exit 0
MOCK
chmod +x "$HW_TMP/bin/pactl"
OMARCHY_TEST_PACTL_FAILS=1
export OMARCHY_TEST_PACTL_FAILS
hw_check_fails "a rejected volume set is reported" "$VOLUME" raise
hw_check_eq "a rejected volume set raises no OSD" "0" "$(hw_osd_count)"
hw_check_fails "a rejected mute toggle is reported" "$VOLUME" mute-toggle
hw_check_eq "a rejected mute toggle raises no OSD" "0" "$(hw_osd_count)"
unset OMARCHY_TEST_PACTL_FAILS

# An unresolvable sink is a failure, not a silent no-op.
hw_new_env
hw_install_pactl 50 no
hw_mock omarchy-audio-output-sink "exit 1"
hw_mock_osd
hw_check_fails "an unresolvable output sink is reported" "$VOLUME" raise
hw_check_eq "an unresolvable output sink raises no OSD" "0" "$(hw_osd_count)"

# A failing OSD after a real volume change is still a failure.
hw_audio_env 50 no
hw_mock_fail omarchy-osd
hw_check_fails "a failing OSD after a real volume change is not reported as success" \
  "$VOLUME" raise
hw_check_eq "a failing OSD does not undo the volume change" "55" "$(hw_volume)"

# ------------------------------------------- mute toggle debounce: private state

hw_audio_env 50 no
"$VOLUME" mute-toggle >/dev/null 2>&1
hw_check_eq "the first mute toggle mutes" "yes" "$(hw_muted)"
[[ -f "$XDG_RUNTIME_DIR/omarchy-audio-output-volume-mute-toggle.last" ]] \
  || hw_fail "the mute debounce stamp must live in the private runtime directory"
[[ ! -e /tmp/omarchy-audio-output-volume-mute-toggle.last ]] \
  || hw_fail "the mute debounce stamp must never appear at a predictable /tmp path"

hw_audio_env 50 no
: >/tmp/omarchy-audio-output-volume-mute-toggle.last 2>/dev/null || true
"$VOLUME" mute-toggle >/dev/null 2>&1
hw_check_eq "a pre-created /tmp debounce stamp does not suppress the toggle" "yes" \
  "$(hw_muted)"
rm -f /tmp/omarchy-audio-output-volume-mute-toggle.last 2>/dev/null || true

hw_audio_env 50 no
env -u XDG_RUNTIME_DIR "$VOLUME" mute-toggle >/dev/null 2>&1
hw_check_eq "mute-toggle works with no XDG_RUNTIME_DIR" "yes" "$(hw_muted)"
[[ ! -e /tmp/omarchy-audio-output-volume-mute-toggle.last ]] \
  || hw_fail "no XDG_RUNTIME_DIR must not produce a /tmp debounce stamp"
[[ -f "$XDG_STATE_HOME/omarchy/omarchy-audio-output-volume-mute-toggle.last" ]] \
  || hw_fail "the fallback debounce stamp must live under the private state directory"
[[ $(stat -c '%a' "$XDG_STATE_HOME/omarchy") == "700" ]] \
  || hw_fail "the fallback state directory must not be world-readable"

# A key repeat inside the debounce window is dropped: one press, one decision.
# The window is 250ms of wall clock, and ten sequential script invocations cost
# roughly 500ms on a loaded machine, so racing them against the real clock made
# this check fail whenever the machine was busy. `date` is mocked to a fixed
# timestamp for the burst instead, which is what a key repeat actually looks
# like, and restored immediately afterwards.
hw_audio_env 50 no
hw_mock date 'printf "%s\n" "${HW_FROZEN_NOW:-1000000000000}"'
for _ in $(seq 1 10); do
  "$VOLUME" mute-toggle >/dev/null 2>&1
done
rm -f "$HW_TMP/bin/date"
hw_check_eq "ten rapid mute toggles collapse to a single decision" "yes" "$(hw_muted)"
hw_check_eq "a dropped repeat raises no OSD" "1" "$(hw_osd_count)"

# Once the window has passed, the next press is a new decision rather than a
# repeat, which is what makes the burst above collapse instead of freezing.
hw_audio_env 50 no
hw_mock date 'n=$(cat "$OMARCHY_TEST_STATE/date-n" 2>/dev/null || echo 0); n=$((n + 1)); printf "%s" "$n" >"$OMARCHY_TEST_STATE/date-n"; printf "%s\n" "$((1000000000000 + n * 400))"'
"$VOLUME" mute-toggle >/dev/null 2>&1
"$VOLUME" mute-toggle >/dev/null 2>&1
rm -f "$HW_TMP/bin/date"
hw_check_eq "a press after the debounce window toggles again" "no" "$(hw_muted)"
hw_check_eq "both presses past the window raise an OSD" "2" "$(hw_osd_count)"

# ------------------------------------------------------------- output switching

hw_audio_env 50 no
hw_check "switching outputs succeeds" "$SWITCH"
hw_check_eq "switching moves to the next sink" "$HW_HDMI" "$(hw_default)"
hw_check_eq "switching raises exactly one OSD" "1" "$(hw_osd_count)"
hw_check_eq "the switch OSD names the new output" "HDMI" "$(hw_osd_message)"

hw_audio_env 50 no
hw_check "switching wraps back around to the first sink" "$SWITCH" 2>/dev/null || true
"$SWITCH" >/dev/null 2>&1
hw_check_eq "switching twice returns to the first sink" "$HW_SPK" "$(hw_default)"

# With only one candidate sink, switching is a no-op that still names it.
hw_audio_env 50 no
printf '%s\n' "$(jq -nc --arg spk "$HW_SPK" '[{index: 41, name: $spk, description: "Speakers", ports: []}]')" \
  >"$OMARCHY_TEST_STATE/audio/sinks.json"
hw_check "switching with a single candidate succeeds" "$SWITCH"
hw_check_eq "switching with a single candidate keeps the sink" "$HW_SPK" "$(hw_default)"
hw_check_eq "switching with a single candidate still names it" "Speakers" "$(hw_osd_message)"

# An empty candidate list is a genuine "no devices" and gets the OSD it promises.
hw_audio_env 50 no
printf '[]\n' >"$OMARCHY_TEST_STATE/audio/sinks.json"
hw_check_fails "switching with no candidate sinks is reported" "$SWITCH"
hw_check_eq "switching with no candidate sinks says so in the OSD" "No audio devices found" \
  "$(hw_osd_message)"

# A PipeWire that cannot be listed is not a machine with no hardware, and must
# not claim there is none.
hw_audio_env 50 no
OMARCHY_TEST_FAIL_LIST=1
export OMARCHY_TEST_FAIL_LIST
hw_check_fails "a failed sink listing is reported" "$SWITCH"
unset OMARCHY_TEST_FAIL_LIST
hw_not_called "OSD -m No audio devices found" \
  || hw_fail "a failed sink listing must not claim there are no devices"
hw_check_eq "a failed sink listing raises no OSD" "0" "$(hw_osd_count)"

hw_audio_env 50 no
OMARCHY_TEST_FAIL_DEFAULT=1
export OMARCHY_TEST_FAIL_DEFAULT
hw_check_fails "an unreadable current sink is reported" "$SWITCH"
unset OMARCHY_TEST_FAIL_DEFAULT
hw_check_eq "an unreadable current sink raises no OSD" "0" "$(hw_osd_count)"

# An unresolved effective sink would claim a level nothing is playing at.
hw_audio_env 50 no
hw_mock omarchy-audio-output-sink "exit 1"
hw_check_fails "an unresolvable effective sink is reported" "$SWITCH"
hw_check_eq "an unresolvable effective sink raises no OSD" "0" "$(hw_osd_count)"

# A default switch that does not take must not produce a success OSD.
hw_audio_env 50 no
cat >"$HW_TMP/bin/omarchy-audio-output-set-default" <<'MOCK'
#!/bin/bash
printf 'set-default %s\n' "$*" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true
exit 1
MOCK
chmod +x "$HW_TMP/bin/omarchy-audio-output-set-default"
hw_check_fails "a failed default switch is reported" "$SWITCH"
hw_not_called "OSD -i volume" || hw_fail "a failed default switch must not raise a success OSD"

# A failing OSD after a successful switch is still a failure.
hw_audio_env 50 no
hw_mock_fail omarchy-osd
hw_check_fails "a failing OSD after a real switch is not reported as success" "$SWITCH"
hw_check_eq "a failing OSD does not undo the switch" "$HW_HDMI" "$(hw_default)"

# A sink whose level cannot be read at all.
hw_audio_env 50 no
OMARCHY_TEST_FAIL_VOLUME=1
export OMARCHY_TEST_FAIL_VOLUME
printf '%s\n' "$(jq -nc --arg hdmi "$HW_HDMI" '[{index: 42, name: $hdmi, description: "HDMI", ports: []}]')" \
  >"$OMARCHY_TEST_STATE/audio/sinks.json"
hw_check_fails "an unreadable sink level is reported" "$SWITCH"
unset OMARCHY_TEST_FAIL_VOLUME
hw_check_eq "an unreadable sink level raises no OSD" "0" "$(hw_osd_count)"

# Rapid repeated switches must each land on a real sink, never on a half-written
# one, and every OSD must name a sink that exists.
hw_audio_env 50 no
for _ in $(seq 1 8); do
  "$SWITCH" >/dev/null 2>&1 &
done
wait
current="$(hw_default)"
if [[ $current == "$HW_SPK" || $current == "$HW_HDMI" ]]; then
  hw_ok "overlapping switches leave a real default sink"
else
  hw_fail "overlapping switches left a partial default sink ('$current')"
fi
hw_check "every switch OSD names a real sink" bash -c \
  "! grep '^OSD -i volume' \"$OMARCHY_TEST_LOG\" | grep -qv 'Speakers\|HDMI'"

# ---------------------------------------------------------------- input muting

hw_audio_env 50 no
hw_check "input mute toggles successfully" "$INPUT_MUTE"
hw_check_eq "input mute mutes the source" "yes" "$(hw_muted)"
hw_check_eq "input mute lights the mic-mute LED" "1" "$(hw_call_count 'LED on')"
hw_check_eq "input mute raises the muted OSD" "Microphone muted" "$(hw_osd_message)"

hw_audio_env 50 yes
hw_check "a second input mute toggles successfully" "$INPUT_MUTE"
hw_check_eq "a second input mute unmutes the source" "no" "$(hw_muted)"
hw_check_eq "a second input mute clears the mic-mute LED" "1" "$(hw_call_count 'LED off')"
hw_check_eq "a second input mute raises the live OSD" "Microphone on" "$(hw_osd_message)"

# A toggle that never landed must not claim the microphone is muted, and must not
# light the LED.
hw_audio_env 50 no
cat >"$HW_TMP/bin/wpctl" <<'MOCK'
#!/bin/bash
printf 'wpctl %s\n' "$*" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true
[[ $1 == set-mute ]] && exit 1
exit 0
MOCK
chmod +x "$HW_TMP/bin/wpctl"
hw_check_fails "a rejected mic-mute toggle is reported" "$INPUT_MUTE"
hw_check_eq "a rejected mic-mute toggle raises no OSD" "0" "$(hw_osd_count)"
hw_not_called "LED on" || hw_fail "a rejected mic-mute toggle must not light the LED"
hw_not_called "LED off" || hw_fail "a rejected mic-mute toggle must not clear the LED"
hw_check_eq "a rejected mic-mute toggle leaves the source state alone" "no" "$(hw_muted)"

# A toggle that landed but cannot be read back must not raise a state OSD.
hw_audio_env 50 no
cat >"$HW_TMP/bin/wpctl" <<'MOCK'
#!/bin/bash
printf 'wpctl %s\n' "$*" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true
[[ $1 == get-volume ]] && exit 1
exit 0
MOCK
chmod +x "$HW_TMP/bin/wpctl"
cat >"$HW_TMP/bin/pactl" <<'MOCK'
#!/bin/bash
printf 'pactl %s\n' "$*" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true
[[ $1 == get-source-mute ]] && exit 1
exit 0
MOCK
chmod +x "$HW_TMP/bin/pactl"
hw_check_fails "an unreadable mic state after a toggle is reported" "$INPUT_MUTE"
hw_check_eq "an unreadable mic state raises no OSD" "0" "$(hw_osd_count)"
hw_not_called "LED on" || hw_fail "an unreadable mic state must not light the LED"
hw_not_called "LED off" || hw_fail "an unreadable mic state must not clear the LED"

# A wpctl that cannot report the state still gets a second, independent read.
hw_audio_env 50 no
cat >"$HW_TMP/bin/wpctl" <<'MOCK'
#!/bin/bash
printf 'wpctl %s\n' "$*" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true
[[ $1 == get-volume ]] && exit 1
[[ $1 == set-mute ]] && { [[ $(cat "$OMARCHY_TEST_STATE/audio/muted") == yes ]] && printf 'no\n' >"$OMARCHY_TEST_STATE/audio/muted" || printf 'yes\n' >"$OMARCHY_TEST_STATE/audio/muted"; }
exit 0
MOCK
chmod +x "$HW_TMP/bin/wpctl"
hw_check "input mute falls back to a second read of the state" "$INPUT_MUTE"
hw_called "pactl get-source-mute" || hw_fail "an unreadable wpctl state must fall back"
hw_check_eq "the fallback read still reports the real state" "Microphone muted" \
  "$(hw_osd_message)"

# A failing OSD after a real toggle is still a failure.
hw_audio_env 50 no
hw_mock_fail omarchy-osd
hw_check_fails "a failing OSD after a real mic toggle is not reported as success" "$INPUT_MUTE"
hw_check_eq "a failing OSD does not undo the mic toggle" "yes" "$(hw_muted)"

# A trailing argument is a second, unrequested toggle.
hw_audio_env 50 no
hw_check_fails "a trailing argument to input mute is rejected" "$INPUT_MUTE" toggle
hw_check_eq "a rejected input mute leaves the source alone" "no" "$(hw_muted)"

# Rapid repeated presses each toggle once, and every OSD matches the state the
# mock is actually in.
hw_audio_env 50 no
for _ in $(seq 1 6); do
  "$INPUT_MUTE" >/dev/null 2>&1
done
hw_check_eq "six sequential mic toggles end in an even state" "no" "$(hw_muted)"
hw_check_eq "six sequential mic toggles raise six OSDs" "6" "$(hw_osd_count)"
hw_check "every mic OSD matches the toggle parity" bash -c '
  muted_osds=$(grep -c "^OSD -i microphone-muted" "$OMARCHY_TEST_LOG")
  live_osds=$(grep -c "^OSD -i microphone " "$OMARCHY_TEST_LOG")
  [[ $muted_osds -eq $live_osds ]]'

hw_summary
