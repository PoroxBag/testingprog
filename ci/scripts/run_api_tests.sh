#!/usr/bin/env bash
# Автотесты Redfish (Lab5) → ci-reports/api/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

REPORT_DIR="${REPORT_DIR:-ci-reports/api}"
mkdir -p "$REPORT_DIR"

export BMC_URL="${BMC_URL:-https://127.0.0.1:2443}"
export BMC_USER="${BMC_USER:-root}"
export BMC_PASSWORD="${BMC_PASSWORD:-0penBmc}"
export RUN_POWER_TEST="${RUN_POWER_TEST:-1}"

PYTHON="${PYTHON:-python3}"
if [[ -x "$ROOT/.venv/bin/python" ]] && "$ROOT/.venv/bin/python" -m pip --version >/dev/null 2>&1; then
  PYTHON="$ROOT/.venv/bin/python"
fi

"$PYTHON" -m pip install -q -r requirements.txt || \
  "$PYTHON" -m pip install -q --break-system-packages -r requirements.txt

set +e
"$PYTHON" -m pytest -v test_redfish.py \
  --junitxml="$REPORT_DIR/junit.xml" \
  2>&1 | tee "$REPORT_DIR/pytest_console.txt"
rc=${PIPESTATUS[0]}
set -e

cp -f pytest_results.txt "$REPORT_DIR/pytest_results.txt" 2>/dev/null || true
{
  echo "API tests exit_code=$rc"
  echo "BMC_URL=$BMC_URL"
  date -Is
} | tee "$REPORT_DIR/summary.txt"

exit "$rc"
