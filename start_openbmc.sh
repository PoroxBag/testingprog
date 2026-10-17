#!/usr/bin/env bash
# Запуск OpenBMC (romulus) в QEMU с пробросом портов:
#   HTTPS/Redfish -> https://127.0.0.1:2443
#   SSH           -> 127.0.0.1:2222
#   IPMI          -> UDP 127.0.0.1:2623
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -x ./qemu-system-arm ]]; then
  echo "Нет ./qemu-system-arm" >&2
  exit 1
fi
if [[ ! -f ./obmc-phosphor-image-romulus.static.mtd ]]; then
  echo "Нет образа obmc-phosphor-image-romulus.static.mtd" >&2
  exit 1
fi

exec ./qemu-system-arm \
  -m 256 \
  -M romulus-bmc \
  -nographic \
  -drive file=./obmc-phosphor-image-romulus.static.mtd,format=raw,if=mtd \
  -net nic \
  -net user,hostfwd=:127.0.0.1:2222-:22,hostfwd=:127.0.0.1:2443-:443,hostfwd=udp:127.0.0.1:2623-:623,hostname=qemu
