#!/bin/bash
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# Every test runs against a throwaway HOME, a throwaway XDG_RUNTIME_DIR and a
# throwaway PATH full of recording mocks. Nothing here touches a real backlight,
# a real DDC bus, PipeWire, WirePlumber or Hyprland.
HW_PASS=0
HW_FAIL=0

hw_ok() {
  HW_PASS=$((HW_PASS + 1))
  printf 'ok - %s\n' "$1"
}

hw_fail() {
  HW_FAIL=$((HW_FAIL + 1))
  printf 'not ok - %s\n' "$1" >&2
}

hw_summary() {
  printf '1..%d\n' "$((HW_PASS + HW_FAIL))"
  if ((HW_FAIL > 0)); then
    printf 'FAILED %d of %d checks\n' "$HW_FAIL" "$((HW_PASS + HW_FAIL))" >&2
    return 1
  fi
  printf 'passed %d checks\n' "$HW_PASS"
}

# hw_check <label> <command...> -- the command must succeed.
hw_check() {
  local label="$1"
  shift
  if "$@"; then
    hw_ok "$label"
  else
    hw_fail "$label"
  fi
}

# hw_check_fails <label> <command...> -- the command must fail.
hw_check_fails() {
  local label="$1"
  shift
  if "$@"; then
    hw_fail "$label"
  else
    hw_ok "$label"
  fi
}

# hw_check_eq <label> <expected> <actual>
hw_check_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"

  if [[ $expected == "$actual" ]]; then
    hw_ok "$label"
  else
    hw_fail "$label (expected '$expected', got '$actual')"
  fi
}

# hw_check_between <label> <low> <high> <value>
hw_check_between() {
  local label="$1"
  local low="$2"
  local high="$3"
  local value="$4"

  if [[ $value =~ ^-?[0-9]+$ ]] && ((value >= low && value <= high)); then
    hw_ok "$label"
  else
    hw_fail "$label ('$value' is outside [$low, $high])"
  fi
}

# hw_new_env -- creates an isolated sandbox and exports it.
# Mocks are named after the real commands the scripts call, so the scripts under
# test are invoked exactly as they are in production.
hw_new_env() {
  # A test file calls this per scenario, so drop the previous sandbox before
  # making the next one; the EXIT trap can only clean up the last.
  if [[ -n ${HW_TMP:-} && -d ${HW_TMP:-} && ${HW_KEEP_TMP:-0} != "1" ]]; then
    rm -rf -- "$HW_TMP"
  fi
  HW_TMP="$(mktemp -d)"
  # Every sandbox is throwaway: without this the suite leaks one temp tree per
  # run, which is how hundreds of them piled up in /tmp. Set HW_KEEP_TMP=1 to
  # leave the last one in place when a failure needs investigating.
  hw_cleanup_sandbox() {
    [[ -n ${HW_TMP:-} && -d ${HW_TMP:-} ]] || return 0
    if [[ ${HW_KEEP_TMP:-0} == "1" ]]; then
      printf 'hardware test sandbox kept at %s\n' "$HW_TMP" >&2
      return 0
    fi
    rm -rf -- "$HW_TMP"
  }
  trap hw_cleanup_sandbox EXIT
  export HOME="$HW_TMP/home"
  export XDG_RUNTIME_DIR="$HW_TMP/run"
  export XDG_STATE_HOME="$HW_TMP/state"
  export OMARCHY_BACKLIGHT_PATH="$HW_TMP/backlight"
  export OMARCHY_KEYBOARD_BACKLIGHT_PATH="$HW_TMP/leds"
  export OMARCHY_TEST_STATE="$HW_TMP"
  export OMARCHY_TEST_LOG="$HW_TMP/calls.log"

  mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$XDG_STATE_HOME" "$HW_TMP/bin"
  chmod 700 "$XDG_RUNTIME_DIR" "$XDG_STATE_HOME"
  : >"$OMARCHY_TEST_LOG"

  export PATH="$HW_TMP/bin:/usr/bin:/bin:$ROOT/bin"
}

hw_calls() {
  cat "$OMARCHY_TEST_LOG"
}

# hw_called <substring> -- the substring appeared in some invocation.
hw_called() {
  grep -qF -- "$1" "$OMARCHY_TEST_LOG"
}

# hw_not_called <substring> -- the substring appeared in no invocation.
hw_not_called() {
  ! grep -qF -- "$1" "$OMARCHY_TEST_LOG"
}

# hw_call_count <fixed-string> -- number of matching invocation lines.
hw_call_count() {
  grep -cF -- "$1" "$OMARCHY_TEST_LOG" || true
}

# hw_mock <name> <body>
# Installs a mock command. Every mock records its own name and full argument list
# in $OMARCHY_TEST_LOG before doing anything else, so a test can assert on
# exactly what the script under test asked the system to do.
hw_mock() {
  local name="$1"
  local body="$2"

  {
    printf '#!/bin/bash\n'
    printf 'printf "%%s" %q >>"$OMARCHY_TEST_LOG" 2>/dev/null || true\n' "$name"
    printf 'for hw_mock_arg in "$@"; do printf " %s" "$hw_mock_arg" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true; done\n'
    printf 'printf "\\n" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true\n'
    printf '%s\n' "$body"
  } >"$HW_TMP/bin/$name"
  chmod +x "$HW_TMP/bin/$name"
}

# hw_mock_fail <name> -- records the call, then fails.
hw_mock_fail() {
  hw_mock "$1" 'exit 1'
}

# hw_mock_output <name> <literal-output> -- records the call, prints fixed text.
hw_mock_output() {
  local name="$1"
  local output="$2"
  hw_mock "$1" "printf '%%s\\\\n' $(printf '%q' "$output"); exit 0"
}

# hw_mock_osd -- records every OSD the script under test raises.
hw_mock_osd() {
  hw_mock omarchy-osd 'printf "OSD %s\n" "$*" >>"$OMARCHY_TEST_LOG"; exit 0'
}

# hw_osd_count -- number of OSDs raised.
hw_osd_count() {
  hw_call_count "OSD "
}

# hw_osd_last <flag> -- the token following <flag> in the most recent OSD.
hw_osd_last() {
  awk -v flag="$1" '
    {
      for (i = 1; i < NF; i++)
        if ($i == flag) last = $(i + 1)
    }
    END { if (last != "") print last }
  ' "$OMARCHY_TEST_LOG"
}

# hw_osd_message -- the whole -m payload of the most recent OSD.
hw_osd_message() {
  sed -n -E 's/^OSD (-i [^ ]+ )?-m //p' "$OMARCHY_TEST_LOG" | tail -n1
}

# hw_install_backlight <current-percent>
# Mock brightnessctl + omarchy-hw-display for the internal-panel path.
# Reading (-m) prints the stored level; `set` accepts an absolute percentage or
# a signed percentage step and stores the resulting absolute level.
hw_install_backlight() {
  local current="$1"

  mkdir -p "$OMARCHY_BACKLIGHT_PATH"
  printf '%s\n' "$current" >"$HW_TMP/backlight-level"

  cat >"$HW_TMP/bin/brightnessctl" <<'MOCK'
#!/bin/bash
printf 'brightnessctl %s\n' "$*" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true

device=""
step=""
prev=""
for arg in "$@"; do
  case "$prev" in
    -d) device="$arg" ;;
    set) step="$arg" ;;
  esac
  prev="$arg"
done

if [[ -n $step ]]; then
  if [[ ${OMARCHY_TEST_SET_FAILS:-0} == 1 ]]; then
    echo "Error: Device or resource busy" >&2
    exit 1
  fi
  level="$(cat "$OMARCHY_TEST_STATE/backlight-level")"
  case "$step" in
    +*%) amount="${step#+}"; amount="${amount%%%}"; level=$((level + amount)) ;;
    *%-)  amount="${step%?}"; amount="${amount%?}";  level=$((level - amount)) ;;
    *%)   level="${step%%%}" ;;
    *)    level="$step" ;;
  esac
  if ((level < 1)); then level=1; fi
  if ((level > 100)); then level=100; fi
  printf '%s\n' "$level" >"$OMARCHY_TEST_STATE/backlight-level"
  exit 0
fi

printf 'Current brightness: %s%%\n' "$(cat "$OMARCHY_TEST_STATE/backlight-level")"
exit 0
MOCK
  chmod +x "$HW_TMP/bin/brightnessctl"
  hw_mock omarchy-hw-display "printf '%s\\n' intel_backlight; exit 0"
}

# hw_install_ddc <bus> <current> <max>
# Mock ddcutil for the DDC/CI path, emitting the same terse shapes the real tool
# prints: "   I2C bus: /dev/i2c-N" / "   DRM connector: cardN-NAME" for detect
# and "VCP 10 C <current> <max>" for getvcp.
hw_install_ddc() {
  local bus="$1"
  local current="$2"
  local maximum="$3"

  printf '%s\n' "$current" >"$HW_TMP/ddc-current"
  printf '%s\n' "$maximum" >"$HW_TMP/ddc-max"

  cat >"$HW_TMP/bin/ddcutil" <<'MOCK'
#!/bin/bash
printf 'ddcutil %s\n' "$*" >>"$OMARCHY_TEST_LOG" 2>/dev/null || true

case "$*" in
  *setvcp*)
    if [[ ${OMARCHY_TEST_SETVCP_FAILS:-0} == 1 ]]; then
      echo "Error: unable to set VCP feature" >&2
      exit 1
    fi
    ;;
  *)
    if [[ ${OMARCHY_TEST_SET_FAILS:-0} == 1 ]]; then
      echo "Error: ddcutil failed" >&2
      exit 1
    fi
    ;;
esac

case "$*" in
  *detect*)
    [[ -n ${OMARCHY_TEST_NO_BUS:-} ]] && exit 1
    printf '   I2C bus:          /dev/i2c-%s\n' "${OMARCHY_TEST_BUS:-0}"
    printf '   DRM connector:    %s\n' "${OMARCHY_TEST_CONNECTOR:-card1-DP-1}"
    ;;
  *getvcp*)
    printf 'VCP %d C %d %d\n' 10 \
      "$(cat "$OMARCHY_TEST_STATE/ddc-current")" \
      "$(cat "$OMARCHY_TEST_STATE/ddc-max")"
    ;;
  *setvcp*)
    target="${!#}"
    max="$(cat "$OMARCHY_TEST_STATE/ddc-max")"
    level=$(( (target * 100 + max / 2) / max ))
    if ((level < 1)); then level=1; fi
    if ((level > 100)); then level=100; fi
    printf '%s\n' "$level" >"$OMARCHY_TEST_STATE/ddc-current"
    ;;
esac
exit 0
MOCK
  chmod +x "$HW_TMP/bin/ddcutil"
}
