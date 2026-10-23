#!/usr/bin/env bash
# Сборка и запуск Jenkins + ожидание готовности UI.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

echo "==> Building & starting Jenkins (docker compose)"
docker compose -f docker-compose.jenkins.yml up -d --build

echo "==> Waiting for Jenkins http://127.0.0.1:8080 ..."
for i in $(seq 1 90); do
  if curl -fsS -u admin:admin http://127.0.0.1:8080/api/json >/dev/null 2>&1; then
    echo "Jenkins is up (try $i)"
    curl -fsS -u admin:admin http://127.0.0.1:8080/api/json | head -c 300
    echo
    exit 0
  fi
  echo "  waiting ($i)..."
  sleep 5
done
echo "Jenkins did not become ready" >&2
docker compose -f docker-compose.jenkins.yml logs --tail=80
exit 1
