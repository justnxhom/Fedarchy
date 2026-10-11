#!/bin/bash
set -euo pipefail

echo "=== Fedarchy Relocation Test ==="
echo ""

ORIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="/tmp/fedarchy-relocation-test-$$"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

cleanup() {
    rm -rf "${TEST_DIR}"
}
trap cleanup EXIT

echo "Original location: ${ORIG_DIR}"
echo "Test location:     ${TEST_DIR}"
echo ""

echo "[1/5] Copying project to test location..."
cp -a "${ORIG_DIR}" "${TEST_DIR}"
pass "Project copied"

echo ""
echo "[2/5] Verifying structure..."
for path in shell/shell.qml shell/Commons/Util.qml shell/services/AppLibrary.qml shell/plugins/menu/Menu.qml config/omarchy/shell.json default/omarchy/omarchy-menu.jsonc scripts/dev-run.sh scripts/test.sh scripts/install.sh scripts/fedarchy-shell; do
    [ -f "${TEST_DIR}/${path}" ] && pass "${path}" || fail "${path} missing"
done

echo ""
echo "[3/5] Checking for hardcoded paths..."
if grep -r "${ORIG_DIR}" "${TEST_DIR}/shell/" "${TEST_DIR}/scripts/" 2>/dev/null; then
    fail "Original path still referenced"
else
    pass "No original path references"
fi

echo ""
echo "[4/5] Verifying shell.json is valid..."
echo "${TEST_DIR}/config/omarchy/shell.json"
cat "${TEST_DIR}/config/omarchy/shell.json" | python3 -m json.tool > /dev/null 2>&1 && pass "Valid JSON" || fail "Invalid JSON"

echo ""
echo "[5/5] Running test suite from relocated copy..."
bash "${TEST_DIR}/scripts/test.sh" && pass "Tests pass from new location" || fail "Tests fail from new location"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ ${FAIL} -eq 0 ] && echo "Relocation test PASSED" || echo "Relocation test FAILED"
[ ${FAIL} -eq 0 ] && exit 0 || exit 1
