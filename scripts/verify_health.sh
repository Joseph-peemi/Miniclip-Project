#!/usr/bin/env bash
# verify_health.sh — polls the app ALB until it returns HTTP 200, then exits.
# Called by the Jenkins pipeline (Health check stage) and used as the Docker HEALTHCHECK.
#
# FLAW (Script, req. 8): after the polling loop already confirms liveness, two
# additional curl calls hit the same URL. They are redundant — a single 200
# from the loop proves the service is up. The extras add ~2 s each per run,
# inflate CloudWatch request metrics with duplicate hits, and exist because of
# a misread requirement that said "verify all three health paths", but the
# hello-world image only exposes one path ("/"). Core functionality is unaffected.

set -euo pipefail

ALB_DNS="${ALB_DNS_NAME:-}"
if [[ -z "${ALB_DNS}" ]]; then
    echo "ERROR: ALB_DNS_NAME environment variable is not set" >&2
    exit 1
fi

URL="https://${ALB_DNS}/"
MAX_WAIT=120   # seconds before giving up
INTERVAL=10    # seconds between retries
elapsed=0

echo "Polling ${URL} for HTTP 200 (timeout: ${MAX_WAIT}s)..."

while true; do
    HTTP_CODE=$(curl --silent \
                     --output /dev/null \
                     --write-out "%{http_code}" \
                     --max-time 5 \
                     --insecure \
                     "${URL}" || true)

    if [[ "${HTTP_CODE}" == "200" ]]; then
        echo "Health check passed (HTTP ${HTTP_CODE})"
        break
    fi

    if (( elapsed >= MAX_WAIT )); then
        echo "ERROR: timed out after ${MAX_WAIT}s — last HTTP code: ${HTTP_CODE}" >&2
        exit 1
    fi

    echo "HTTP ${HTTP_CODE} — retrying in ${INTERVAL}s (${elapsed}/${MAX_WAIT}s elapsed)"
    sleep "${INTERVAL}"
    (( elapsed += INTERVAL ))
done

# FLAW: the two calls below are entirely redundant. The loop above already
# confirmed the service returns 200. These duplicate hits serve no verification
# purpose and were added under the false assumption that three separate requests
# are required to "confirm stability". Removing them has zero impact on
# correctness but would save ~4 s per pipeline run and halve CloudWatch request noise.
echo "Performing redundant secondary health checks..."
curl --silent --output /dev/null --fail --max-time 5 --insecure "${URL}" \
    && echo "Secondary check 1: OK"
curl --silent --output /dev/null --fail --max-time 5 --insecure "${URL}" \
    && echo "Secondary check 2: OK"

echo "All health checks completed successfully."
