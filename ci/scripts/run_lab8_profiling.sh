#!/usr/bin/env bash
# Лабораторная 8: профилирование QEMU (perf + vmstat + nmon)
# Результаты → lab8_results/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

OUT="${OUT:-$ROOT/lab8_results}"
mkdir -p "$OUT"

PERF_BIN="${PERF_BIN:-/usr/lib/linux-tools-6.8.0-147/perf}"
if [[ ! -x "$PERF_BIN" ]]; then
  PERF_BIN="$(command -v perf || true)"
fi
NMON_BIN="${NMON_BIN:-$ROOT/lab8_tools/nmon}"
QEMU_BIN="${QEMU_BIN:-$ROOT/qemu-system-arm}"
MTD_IMAGE="${MTD_IMAGE:-$ROOT/obmc-phosphor-image-romulus.static.mtd}"

DURATION="${PROFILE_DURATION:-60}"   # секунд нагрузки
SAMPLE_BEFORE="${SAMPLE_BEFORE:-5}" # секунд baseline

QEMU_LOG="$OUT/qemu_console.log"
PERF_LOG="$OUT/perf_stat.txt"
VMSTAT_BEFORE="$OUT/vmstat_before.txt"
VMSTAT_DURING="$OUT/vmstat_during.txt"
NMON_FILE="$OUT/host.nmon"
SNAP_BEFORE="$OUT/snapshot_before.txt"
SNAP_DURING="$OUT/snapshot_during.txt"
SUMMARY="$OUT/summary.txt"

echo "==> Lab8 profiling OUT=$OUT DURATION=${DURATION}s"

# --- helpers ---
host_cpu_pct() {
  # average non-idle over 1s from /proc/stat
  python3 - <<'PY'
import time
def read():
    with open('/proc/stat') as f:
        parts=f.readline().split()
    vals=list(map(int, parts[1:]))
    idle=vals[3]+vals[4]
    total=sum(vals)
    return idle, total
i1,t1=read(); time.sleep(1.0); i2,t2=read()
idle,total=i2-i1,t2-t1
print(round(100.0*(1.0-idle/total),2) if total else 0.0)
PY
}

qemu_pid() {
  # ps -C не цепляет perf (у perf в cmdline тоже есть путь к qemu)
  ps -C qemu-system-arm -o pid= 2>/dev/null | awk 'NR==1{gsub(/ /,"",$0); print; exit}'
}

qemu_rss_mb() {
  local pid
  pid=$(qemu_pid)
  if [[ -z "${pid}" ]]; then
    echo "0"
    return
  fi
  awk '/VmRSS:/ {printf "%.1f", $2/1024}' "/proc/$pid/status" 2>/dev/null || echo "0"
}

sample_snapshot() {
  local label="$1" file="$2"
  {
    echo "=== $label $(date -Is) ==="
    echo "host_cpu_pct=$(host_cpu_pct)"
    echo "qemu_rss_mb=$(qemu_rss_mb)"
    echo "--- free -m ---"
    free -m
    echo "--- ps qemu ---"
    ps -C qemu-system-arm -o pid,rss,vsz,%cpu,%mem,etime,cmd 2>/dev/null || \
      pgrep -a qemu-system-arm || echo "no qemu"
    echo "--- top qemu (1 sample) ---"
    top -b -n 1 -p "$(pgrep -f 'qemu-system-arm.*romulus-bmc' | head -1 || echo 1)" 2>/dev/null | tail -5 || true
  } | tee "$file"
}

stop_old_qemu() {
  echo "==> Stopping previous QEMU (if any)"
  pkill -f 'qemu-system-arm.*romulus-bmc' 2>/dev/null || true
  sleep 2
  pkill -9 -f 'qemu-system-arm.*romulus-bmc' 2>/dev/null || true
  sleep 1
}

# --- 0. stop old qemu for clean baseline ---
stop_old_qemu

# --- 1. BEFORE (без QEMU) ---
echo "==> Baseline BEFORE (no QEMU), ${SAMPLE_BEFORE}s vmstat"
vmstat 1 "$SAMPLE_BEFORE" | tee "$VMSTAT_BEFORE"
sample_snapshot "BEFORE (no QEMU)" "$SNAP_BEFORE"
CPU_BEFORE=$(grep host_cpu_pct "$SNAP_BEFORE" | cut -d= -f2)
MEM_BEFORE=$(grep qemu_rss_mb "$SNAP_BEFORE" | cut -d= -f2)

# --- 2. Start QEMU under perf ---
echo "==> Starting QEMU under perf (monitor telnet :5555)"
# -serial mon:stdio перенаправляем в лог (фон); monitor — как в задании
: >"$QEMU_LOG"
# shellcheck disable=SC2086
set +e
"$PERF_BIN" stat -e cycles,instructions,cache-misses \
  -o "$PERF_LOG" -- \
  "$QEMU_BIN" \
    -m 256 \
    -M romulus-bmc \
    -monitor telnet:127.0.0.1:5555,server,nowait \
    -serial mon:stdio \
    -nographic \
    -drive "file=${MTD_IMAGE},format=raw,if=mtd" \
    -net nic \
    -net user,hostfwd=:127.0.0.1:2222-:22,hostfwd=:127.0.0.1:2443-:443,hostfwd=udp:127.0.0.1:2623-:623,hostname=qemu \
    >"$QEMU_LOG" 2>&1 &
PERF_PID=$!
set -e
echo "perf wrapper pid=$PERF_PID"
sleep 3
QEMU_PID=$(qemu_pid)
echo "qemu pid=${QEMU_PID:-unknown}"

# wait BMC (best-effort; profiling идёт даже если boot долгий)
echo "==> Waiting Redfish (up to 180s)"
for i in $(seq 1 36); do
  code=$(curl -k -s --connect-timeout 2 -o /dev/null -w "%{http_code}" -u root:0penBmc https://127.0.0.1:2443/redfish/v1/ || echo 000)
  echo "  try $i HTTP $code"
  if [[ "$code" == "200" ]]; then break; fi
  sleep 5
done

# --- 3. DURING: vmstat + nmon + load ---
echo "==> DURING: vmstat/nmon + Redfish load for ${DURATION}s"
sample_snapshot "DURING (start of load)" "$SNAP_DURING"
CPU_DURING_START=$(grep host_cpu_pct "$SNAP_DURING" | cut -d= -f2)
MEM_DURING=$(grep qemu_rss_mb "$SNAP_DURING" | cut -d= -f2)

# nmon background (CSV-like .nmon file)
if [[ -x "$NMON_BIN" ]]; then
  # -f file, -s seconds, -c count
  COUNT=$((DURATION + 5))
  ( cd "$OUT" && "$NMON_BIN" -f -s 1 -c "$COUNT" -m "$OUT" ) || true
  # nmon names file hostname_YYMMDD_HHMM.nmon — normalize
  sleep 1
  latest=$(ls -t "$OUT"/*.nmon 2>/dev/null | head -1 || true)
  if [[ -n "$latest" && "$latest" != "$NMON_FILE" ]]; then
    cp -f "$latest" "$NMON_FILE"
  fi
else
  echo "nmon not found — writing /proc/net/dev samples" | tee "$OUT/nmon_missing.txt"
  (
    echo "timestamp iface rx_bytes tx_bytes"
    for _ in $(seq 1 "$DURATION"); do
      ts=$(date -Is)
      awk -v ts="$ts" 'NR>2 {gsub(":","",$1); print ts,$1,$2,$10}' /proc/net/dev
      sleep 1
    done
  ) >"$OUT/net_samples.txt" &
  NET_PID=$!
fi

vmstat 1 "$DURATION" | tee "$VMSTAT_DURING" &
VMSTAT_PID=$!

# Redfish load
(
  end=$((SECONDS + DURATION))
  while (( SECONDS < end )); do
    curl -k -s -u root:0penBmc https://127.0.0.1:2443/redfish/v1/Systems/system >/dev/null || true
    curl -k -s -u root:0penBmc https://127.0.0.1:2443/redfish/v1/Managers/bmc >/dev/null || true
    sleep 0.2
  done
) &
LOAD_PID=$!

# mid-load memory sample
sleep $((DURATION / 2))
{
  echo "=== DURING (mid-load) $(date -Is) ==="
  echo "host_cpu_pct=$(host_cpu_pct)"
  echo "qemu_rss_mb=$(qemu_rss_mb)"
} | tee "$OUT/snapshot_during_mid.txt"
MEM_DURING_MID=$(grep qemu_rss_mb "$OUT/snapshot_during_mid.txt" | cut -d= -f2)
CPU_DURING_MID=$(grep host_cpu_pct "$OUT/snapshot_during_mid.txt" | cut -d= -f2)

wait "$VMSTAT_PID" || true
wait "$LOAD_PID" || true
[[ -n "${NET_PID:-}" ]] && wait "$NET_PID" || true
sleep 2
# capture final nmon name again
latest=$(ls -t "$OUT"/*.nmon 2>/dev/null | head -1 || true)
if [[ -n "$latest" ]]; then
  cp -f "$latest" "$NMON_FILE"
fi

# end-of-test snapshot
sample_snapshot "DURING (end of load)" "$OUT/snapshot_during_end.txt"
CPU_DURING_END=$(grep host_cpu_pct "$OUT/snapshot_during_end.txt" | cut -d= -f2)
MEM_DURING_END=$(grep qemu_rss_mb "$OUT/snapshot_during_end.txt" | cut -d= -f2)

# --- 4. stop QEMU so perf flushes stats ---
echo "==> Stopping QEMU to finalize perf stat"
QEMU_PID=$(qemu_pid)
if [[ -n "${QEMU_PID:-}" ]]; then
  kill -TERM "$QEMU_PID" 2>/dev/null || true
fi
# ждём, пока perf завершится и запишет -o файл
for _ in $(seq 1 30); do
  if ! kill -0 "$PERF_PID" 2>/dev/null; then break; fi
  sleep 1
done
if kill -0 "$PERF_PID" 2>/dev/null; then
  kill -INT "$PERF_PID" 2>/dev/null || true
  sleep 2
fi
pkill -f '/qemu-system-arm .*-M romulus-bmc' 2>/dev/null || true
wait "$PERF_PID" 2>/dev/null || true

avg_cpu_from_vmstat() {
  python3 - "$1" <<'PY'
import sys
rows=[]
path=sys.argv[1]
for line in open(path, errors="replace"):
    parts=line.split()
    # строка данных начинается с числа (r)
    if not parts or not parts[0].isdigit():
        continue
    # колонка id: в расширенном vmstat ... us sy id wa st gu
    try:
        id_ = int(parts[-3])  # id перед wa/st на типичном выводе
        # если последняя gu — id на -4
        if len(parts) >= 18:
            id_ = int(parts[-4])
        rows.append(max(0, min(100, 100 - id_)))
    except Exception:
        continue
print(round(sum(rows)/len(rows), 2) if rows else "n/a")
PY
}

CPU_VMSTAT_AVG=$(avg_cpu_from_vmstat "$VMSTAT_DURING")
CPU_BEFORE_VMSTAT=$(avg_cpu_from_vmstat "$VMSTAT_BEFORE")

{
  echo "Lab8 profiling summary"
  echo "date=$(date -Is)"
  echo
  echo "CPU host (%) BEFORE (snapshot 1s): $CPU_BEFORE"
  echo "CPU host (%) BEFORE (vmstat avg):  $CPU_BEFORE_VMSTAT"
  echo "CPU host (%) DURING start:         $CPU_DURING_START"
  echo "CPU host (%) DURING mid:           $CPU_DURING_MID"
  echo "CPU host (%) DURING end:           $CPU_DURING_END"
  echo "CPU host (%) DURING (vmstat avg):  $CPU_VMSTAT_AVG"
  echo
  echo "QEMU RSS (MB) BEFORE (no qemu):    $MEM_BEFORE"
  echo "QEMU RSS (MB) DURING start:        $MEM_DURING"
  echo "QEMU RSS (MB) DURING mid:          $MEM_DURING_MID"
  echo "QEMU RSS (MB) DURING end:          $MEM_DURING_END"
  echo
  echo "perf log: $PERF_LOG"
  echo "vmstat before/during: $VMSTAT_BEFORE / $VMSTAT_DURING"
  echo "nmon: $NMON_FILE"
} | tee "$SUMMARY"

echo "==> Done. See $SUMMARY"
cat "$PERF_LOG" || true
