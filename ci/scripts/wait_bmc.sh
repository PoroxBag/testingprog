#!/usr/bin/env bash
# Ждём готовности Redfish API.
set -euo pipefail

BMC_URL="${BMC_URL:-https://127.0.0.1:2443}"
BMC_USER="${BMC_USER:-root}"
BMC_PASSWORD="${BMC_PASSWORD:-0penBmc}"
TIMEOUT="${BMC_WAIT_TIMEOUT:-240}"
REPORT_DIR="${REPORT_DIR:-ci-reports/qemu}"
mkdir -p "$REPORT_DIR"

LOG="$REPORT_DIR/wait_bmc.log"
: >"$LOG"

echo "Waiting for $BMC_URL/redfish/v1/ (timeout ${TIMEOUT}s)" | tee -a "$LOG"
deadline=$((SECONDS + TIMEOUT))
while (( SECONDS < deadline )); do
  code=$(curl -k -s -o /tmp/bmc_root.json -w "%{http_code}" \
    -u "${BMC_USER}:${BMC_PASSWORD}" \
    --connect-timeout 3 \
    "${BMC_URL}/redfish/v1/" || echo 000)
  echo "$(date -Is) HTTP $code" | tee -a "$LOG"
  if [[ "$code" == "200" ]]; then
    head -c 800 /tmp/bmc_root.json | tee -a "$REPORT_DIR/service_root.json"
    echo | tee -a "$REPORT_DIR/service_root.json"
    echo "BMC is ready" | tee -a "$LOG"
    exit 0
  fi
  sleep 5
done

echo "BMC did not become ready in ${TIMEOUT}s" | tee -a "$LOG"
exit 1
