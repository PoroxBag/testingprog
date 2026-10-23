#!/usr/bin/env bash
# Нагрузочное тестирование Locust (Lab6) → ci-reports/locust/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

REPORT_DIR="${REPORT_DIR:-ci-reports/locust}"
mkdir -p "$REPORT_DIR"

export BMC_URL="${BMC_URL:-https://127.0.0.1:2443}"
export BMC_USER="${BMC_USER:-root}"
export BMC_PASSWORD="${BMC_PASSWORD:-0penBmc}"

USERS="${LOCUST_USERS:-5}"
SPAWN="${LOCUST_SPAWN_RATE:-1}"
RUNTIME="${LOCUST_RUNTIME:-30s}"

PYTHON="${PYTHON:-python3}"
if [[ -x "$ROOT/.venv/bin/python" ]] && "$ROOT/.venv/bin/python" -m pip --version >/dev/null 2>&1; then
  PYTHON="$ROOT/.venv/bin/python"
fi
LOCUST=("$PYTHON" -m locust)
if [[ -x "$ROOT/.venv/bin/locust" ]] && "$ROOT/.venv/bin/python" -m pip --version >/dev/null 2>&1; then
  LOCUST=("$ROOT/.venv/bin/locust")
fi

"$PYTHON" -m pip install -q -r requirements.txt || \
  "$PYTHON" -m pip install -q --break-system-packages -r requirements.txt

# Только OpenBMC-нагрузка в CI (публичные API опциональны через LOCUST_TAGS)
# Запускаем оба класса; при офлайне public API возможны ошибки — короткий прогон.
set +e
"${LOCUST[@]}" -f locustfile.py --headless \
  -u "$USERS" -r "$SPAWN" -t "$RUNTIME" \
  --html "$REPORT_DIR/locust_report.html" \
  --csv "$REPORT_DIR/locust" \
  --only-summary \
  2>&1 | tee "$REPORT_DIR/locust_console.txt"
rc=${PIPESTATUS[0]}
set -e

{
  echo "Locust exit_code=$rc"
  echo "users=$USERS spawn=$SPAWN runtime=$RUNTIME"
  echo "BMC_URL=$BMC_URL"
  date -Is
} | tee "$REPORT_DIR/summary.txt"

exit "$rc"
