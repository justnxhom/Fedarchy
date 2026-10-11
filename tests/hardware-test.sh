#!/bin/bash
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT/tests" || exit 1

failed=0

for suite in hardware-brightness-test.sh hardware-audio-test.sh; do
  printf '# %s\n' "$suite"
  if bash "$suite"; then
    :
  else
    failed=1
  fi
done

if ((failed)); then
  printf '# hardware suites FAILED\n' >&2
  exit 1
fi

printf '# all hardware suites passed\n'
