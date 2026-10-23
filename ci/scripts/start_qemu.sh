#!/usr/bin/env bash
# Запуск OpenBMC QEMU в фоне + ожидание Redfish. Отчёт → ci-reports/qemu/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

REPORT_DIR="${REPORT_DIR:-ci-reports/qemu}"
mkdir -p "$REPORT_DIR"

QEMU_BIN="${QEMU_BIN:-$ROOT/qemu-system-arm}"
MTD_IMAGE="${MTD_IMAGE:-$ROOT/obmc-phosphor-image-romulus.static.mtd}"
PID_FILE="$REPORT_DIR/qemu.pid"
LOG_FILE="$REPORT_DIR/qemu_console.log"

if [[ ! -x "$QEMU_BIN" ]]; then
  echo "QEMU binary not found/executable: $QEMU_BIN" | tee "$REPORT_DIR/error.txt"
  exit 1
fi
if [[ ! -f "$MTD_IMAGE" ]]; then
  echo "MTD image not found: $MTD_IMAGE" | tee "$REPORT_DIR/error.txt"
  exit 1
fi

# Если BMC уже отвечает — не поднимаем второй экземпляр
if curl -k -s --connect-timeout 2 -o /dev/null -w "%{http_code}" \
    -u root:0penBmc https://127.0.0.1:2443/redfish/v1/ | grep -q 200; then
  echo "OpenBMC already reachable on :2443 — reuse" | tee "$REPORT_DIR/reuse.txt"
  echo "reused" >"$REPORT_DIR/mode.txt"
  bash "$ROOT/ci/scripts/wait_bmc.sh"
  exit 0
fi

# Освобождаем порты от старого qemu
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "Stopping previous QEMU pid $(cat "$PID_FILE")" | tee -a "$REPORT_DIR/start.log"
  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  sleep 2
fi
pkill -f "qemu-system-arm.*romulus-bmc" 2>/dev/null || true
sleep 1

echo "Starting QEMU..." | tee "$REPORT_DIR/start.log"
echo "fresh" >"$REPORT_DIR/mode.txt"

# shellcheck disable=SC2086
"$QEMU_BIN" \
  -m 256 \
  -M romulus-bmc \
  -nographic \
  -drive "file=${MTD_IMAGE},format=raw,if=mtd" \
  -net nic \
  -net user,hostfwd=:127.0.0.1:2222-:22,hostfwd=:127.0.0.1:2443-:443,hostfwd=udp:127.0.0.1:2623-:623,hostname=qemu \
  >"$LOG_FILE" 2>&1 &

echo $! >"$PID_FILE"
echo "QEMU pid=$(cat "$PID_FILE")" | tee -a "$REPORT_DIR/start.log"

export REPORT_DIR
bash "$ROOT/ci/scripts/wait_bmc.sh"

{
  echo "QEMU started successfully"
  echo "pid=$(cat "$PID_FILE")"
  echo "log=$LOG_FILE"
  date -Is
} | tee "$REPORT_DIR/summary.txt"
