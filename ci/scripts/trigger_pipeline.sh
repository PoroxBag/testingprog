#!/usr/bin/env bash
# Триггер job openbmc-cicd и ожидание завершения (с CSRF crumb).
set -euo pipefail

JENKINS_URL="${JENKINS_URL:-http://127.0.0.1:8080}"
USER="${JENKINS_USER:-admin}"
PASS="${JENKINS_PASS:-admin}"
JOB="${JENKINS_JOB:-openbmc-cicd}"
COOKIE_JAR=$(mktemp)

cleanup() { rm -f "$COOKIE_JAR"; }
trap cleanup EXIT

crumb_json=$(curl -fsS -c "$COOKIE_JAR" -u "${USER}:${PASS}" \
  "$JENKINS_URL/crumbIssuer/api/json")
CRUMB=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['crumb'])" "$crumb_json")

echo "Triggering job $JOB ..."
curl -fsS -o /dev/null -b "$COOKIE_JAR" -c "$COOKIE_JAR" -u "${USER}:${PASS}" \
  -H "Jenkins-Crumb: ${CRUMB}" -X POST "$JENKINS_URL/job/${JOB}/build"
sleep 5

echo "Waiting for build to finish..."
for i in $(seq 1 120); do
  last=$(curl -fsS -u "${USER}:${PASS}" "$JENKINS_URL/job/${JOB}/lastBuild/api/json")
  building=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('building'))" "$last")
  number=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('number'))" "$last")
  result=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('result'))" "$last")
  echo "  build #$number building=$building result=$result"
  if [[ "$building" == "False" ]]; then
    echo "DONE result=$result"
    mkdir -p lab7_results
    curl -fsS -u "${USER}:${PASS}" \
      "$JENKINS_URL/job/${JOB}/${number}/artifact/*zip*/artifacts.zip" \
      -o lab7_results/artifacts.zip || true
    exit 0
  fi
  sleep 10
done
echo "Timeout waiting for build" >&2
exit 1
