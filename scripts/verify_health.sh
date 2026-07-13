#!/usr/bin/env bash
# Polls the app ALB until it comes back with a 200, then exits. Used both by
# the Jenkins pipeline's "Health check" stage and as the Docker HEALTHCHECK.
#
# FLAW 3: once the loop below already sees a 200, that's confirmation enough —
# but the script then fires off two more curl calls at the exact same URL for
# no real reason. That came from misreading a requirement that said "verify
# all three health paths," except the hello-world image only ever exposes one
# path ("/"), so there was never a second or third path to check. Doesn't
# break anything — just tacks on ~2s per call and adds duplicate hits to the
# CloudWatch request metrics.

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

# FLAW 3 continued: these two calls are the redundant part mentioned up top.
# The loop already proved the service returns 200 — hitting it two more times
# doesn't verify anything new. They got added on the mistaken idea that three
# separate requests were needed to "confirm stability." Pulling them out would
# save roughly 4s per pipeline run and cut the CloudWatch request noise in half.
echo "Performing redundant secondary health checks..."
curl --silent --output /dev/null --fail --max-time 5 --insecure "${URL}" \
    && echo "Secondary check 1: OK"
curl --silent --output /dev/null --fail --max-time 5 --insecure "${URL}" \
    && echo "Secondary check 2: OK"

echo "All health checks completed successfully."
