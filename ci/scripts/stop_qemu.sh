#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT_DIR="${REPORT_DIR:-$ROOT/ci-reports/qemu}"
PID_FILE="$REPORT_DIR/qemu.pid"

if [[ -f "$PID_FILE" ]]; then
  pid=$(cat "$PID_FILE")
  if kill -0 "$pid" 2>/dev/null; then
    echo "Stopping QEMU pid=$pid"
    kill "$pid" 2>/dev/null || true
    sleep 2
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi
# Не трогаем «чужой» qemu, если режим reuse — только pid из пайплайна
if [[ -f "$REPORT_DIR/mode.txt" ]] && grep -q fresh "$REPORT_DIR/mode.txt"; then
  pkill -f "qemu-system-arm.*romulus-bmc" 2>/dev/null || true
fi
echo "stop_qemu done"
