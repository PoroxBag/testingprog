#!/usr/bin/env bash
# WebUI-тесты OpenBMC → ci-reports/webui/
# Smoke: Redfish backend WebUI. Selenium: при RUN_SELENIUM_WEBUI=1 и живом SPA.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

REPORT_DIR="${REPORT_DIR:-ci-reports/webui}"
mkdir -p "$REPORT_DIR"

export OPENBMC_WEBUI_URL="${OPENBMC_WEBUI_URL:-https://127.0.0.1:2443}"
export OPENBMC_USERNAME="${OPENBMC_USERNAME:-root}"
export OPENBMC_PASSWORD="${OPENBMC_PASSWORD:-0penBmc}"
export RUN_POWER_TEST="${RUN_POWER_TEST:-0}"
export RUN_LOCKOUT_TEST="${RUN_LOCKOUT_TEST:-0}"
export RUN_SELENIUM_WEBUI="${RUN_SELENIUM_WEBUI:-0}"

PYTHON="${PYTHON:-python3}"
if [[ -x "$ROOT/.venv/bin/python" ]] && "$ROOT/.venv/bin/python" -m pip --version >/dev/null 2>&1; then
  PYTHON="$ROOT/.venv/bin/python"
fi

"$PYTHON" -m pip install -q -r requirements.txt selenium || \
  "$PYTHON" -m pip install -q --break-system-packages -r requirements.txt selenium

{
  echo "OPENBMC_WEBUI_URL=$OPENBMC_WEBUI_URL"
  curl -k -s -D - -o "$REPORT_DIR/webui_root.body" "$OPENBMC_WEBUI_URL/" | head -20
} | tee "$REPORT_DIR/webui_curl.txt" || true

set +e
"$PYTHON" -m pytest -v test_webui_smoke.py \
  --junitxml="$REPORT_DIR/junit-smoke.xml" \
  2>&1 | tee "$REPORT_DIR/webui_smoke_console.txt"
smoke_rc=${PIPESTATUS[0]}
set -e

selenium_rc=0
if [[ "$RUN_SELENIUM_WEBUI" == "1" ]]; then
  set +e
  "$PYTHON" -m pytest -v openbmc_auth_tests.py \
    --junitxml="$REPORT_DIR/junit-selenium.xml" \
    2>&1 | tee "$REPORT_DIR/webui_console.txt"
  selenium_rc=${PIPESTATUS[0]}
  set -e
else
  cat >"$REPORT_DIR/webui_console.txt" <<EOF
Selenium suite skipped (RUN_SELENIUM_WEBUI=0).
На образе romulus статика WebUI на / часто отсутствует; CI проверяет
Redfish backend WebUI (test_webui_smoke.py). Для полного Selenium
поднимите webui-vue (например :8000) и задайте OPENBMC_WEBUI_URL + RUN_SELENIUM_WEBUI=1.
EOF
fi

cp -f "$REPORT_DIR/junit-smoke.xml" "$REPORT_DIR/junit.xml" 2>/dev/null || true

{
  echo "WebUI smoke exit_code=$smoke_rc"
  echo "WebUI selenium exit_code=$selenium_rc RUN_SELENIUM_WEBUI=$RUN_SELENIUM_WEBUI"
  echo "OPENBMC_WEBUI_URL=$OPENBMC_WEBUI_URL"
  date -Is
} | tee "$REPORT_DIR/summary.txt"

exit "$smoke_rc"
