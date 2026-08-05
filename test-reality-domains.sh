#!/usr/bin/env bash

set -Eeuo pipefail

# 每个域名测试次数
TEST_COUNT=3

# 单次 TLS 连接最大等待时间，单位：秒
TIMEOUT_SECONDS=4

# Reality 候选域名
DOMAINS=(
"downloadmirror.intel.com"
"devblogs.microsoft.com"
"a.b.cdn.console.awsstatic.com"
"prod.pa.cdn.uis.awsstatic.com"
"d.impactradius-event.com"
"r.bing.com"
"configuration.ls.apple.com"
"ms-vscode.gallerycdn.vsassets.io"
"prod.log.shortbread.aws.dev"
"s0.awsstatic.com"
)

echo "=============================================="
echo "Reality candidate domain TLS speed test"
echo "Tests per domain: ${TEST_COUNT}"
echo "Timeout: ${TIMEOUT_SECONDS} seconds"
echo "=============================================="
echo

# 检查必要命令
for cmd in openssl timeout date sort awk; do
if ! command -v "${cmd}" >/dev/null 2>&1; then
echo "Error: required command not found: ${cmd}"
echo "On Debian/Ubuntu, run:"
echo "apt-get update && apt-get install -y openssl coreutils gawk"
exit 1
fi
done

RESULT_FILE="$(mktemp /tmp/reality-domain-test.XXXXXX)"

cleanup() {
rm -f "${RESULT_FILE}"
}

trap cleanup EXIT

current_milliseconds() {
local value

value="$(date +%s%3N 2>/dev/null || true)"

if [[ "${value}" =~ ^[0-9]+$ ]]; then
echo "${value}"
else
echo "$(($(date +%s) * 1000))"
fi
}

test_once() {
local domain="$1"
local start_time
local end_time
local elapsed

start_time="$(current_milliseconds)"

if timeout "${TIMEOUT_SECONDS}" \
openssl s_client \
-connect "${domain}:443" \
-servername "${domain}" \
-tls1_3 \
-brief \
</dev/null \
>/dev/null 2>&1
then
end_time="$(current_milliseconds)"
elapsed=$((end_time - start_time))
echo "${elapsed}"
return 0
fi

return 1
}

for domain in "${DOMAINS[@]}"; do
success_count=0
total_time=0
minimum_time=999999
maximum_time=0

printf "%-42s " "${domain}"

for ((i = 1; i <= TEST_COUNT; i++)); do
if elapsed="$(test_once "${domain}")"; then
success_count=$((success_count + 1))
total_time=$((total_time + elapsed))

if ((elapsed < minimum_time)); then
minimum_time="${elapsed}"
fi

if ((elapsed > maximum_time)); then
maximum_time="${elapsed}"
fi
fi
done

if ((success_count > 0)); then
average_time=$((total_time / success_count))

printf "average %4d ms | success %d/%d\n" \
"${average_time}" \
"${success_count}" \
"${TEST_COUNT}"

printf "%d|%s|%d|%d|%d\n" \
"${average_time}" \
"${domain}" \
"${minimum_time}" \
"${maximum_time}" \
"${success_count}" >> "${RESULT_FILE}"
else
printf "failed or timed out\n"

printf "999999|%s|0|0|0\n" \
"${domain}" >> "${RESULT_FILE}"
fi
done

echo
echo "=============================================="
echo "Results sorted by average TLS handshake time"
echo "=============================================="

rank=0

while IFS='|' read -r average domain minimum maximum successes; do
rank=$((rank + 1))

if [[ "${average}" -eq 999999 ]]; then
printf "%2d. %-42s failed\n" \
"${rank}" \
"${domain}"
else
printf "%2d. %-42s average %4d ms | min %4d ms | success %d/%d\n" \
"${rank}" \
"${domain}" \
"${average}" \
"${minimum}" \
"${successes}" \
"${TEST_COUNT}"
fi
done < <(sort -t '|' -k1,1n "${RESULT_FILE}")

echo
echo "Important:"
echo "A lower TLS handshake time is only an initial screening result."
echo "It does not guarantee that the domain is ideal for Reality."
