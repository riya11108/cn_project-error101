#!/bin/zsh
# End-to-end layered health check, run from Mac 1.
# Usage: e2e_check.sh <output-file relative to evidence/>
# Checks, in diagnostic order: DNS (primary + backup) -> TCP ports -> TLS -> HTTP via both edges.
EV="$(dirname "$0")/ev.sh"
OUT="$1"
M2=10.7.19.93; M3=10.7.31.224; M1=10.7.9.246

$EV "$OUT" "echo '[1] DNS'; dig @$M1 app.team1.test +noall +answer +time=2 +tries=1; dig @$M3 app.team1.test +noall +answer +time=2 +tries=1"
$EV "$OUT" "echo '[2] TCP'; for t in '$M2 8443' '$M3 8443' '$M3 3001' '$M3 3002' '$M3 53'; do nc -z -G3 \${=t} 2>/dev/null && echo \"\$t OPEN\" || echo \"\$t TIMEOUT/CLOSED\"; done"
$EV "$OUT" "echo '[3+4] TLS + HTTP via each edge'; for ip in $M2 $M3; do curl -s -o /dev/null --max-time 8 --resolve app.team1.test:8443:\$ip -w \"edge \$ip -> HTTP %{http_code}, tls_verify=%{ssl_verify_result}, %{time_total}s\n\" \"https://app.team1.test:8443/api/status?e2e=\$RANDOM\"; done"
$EV "$OUT" "echo '[5] Load balancing via Mac 2 edge'; for i in 1 2 3 4; do curl -s --max-time 8 --resolve app.team1.test:8443:$M2 -D - -o /dev/null \"https://app.team1.test:8443/api/status?lb=\$RANDOM\" | grep -iE '^x-backend'; done"
