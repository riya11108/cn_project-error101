#!/bin/zsh
# Combined monitor for Ext D rerun + Ext C (run on MAC 1). Every 2 s:
#   - HTTPS through Mac 2 edge and Mac 3 edge (unique URL each time -> never an edge-cache hit)
#   - DIRECT TCP from Mac 1 (a client) to the backend ports 10.7.31.224:3001/3002 (should be BLOCKED while PF is on)
set -u
OUT="$(cd "$(dirname "$0")/.." && pwd)/evidence/phase2/C_firewall/CD_monitor_mac1_$(date +%Y%m%d_%H%M%S).txt"
mkdir -p "$(dirname "$OUT")"
exec > >(tee -a "$OUT") 2>&1
probe() {
  curl -s -o /dev/null --max-time 6 --resolve "app.team1.test:8443:$1" -D - "https://app.team1.test:8443/api/status?mon=$2" \
   -w '%{http_code}' | awk 'BEGIN{b="-";x="-"} tolower($1)=="x-backend:"{b=$2} tolower($1)=="x-cache-status:"{x=$2} /^[0-9][0-9][0-9]$/{c=$1} END{gsub("\r","",b); gsub("\r","",x); printf "%s %s %s", c, b, x}'
}
direct() { nc -z -G 2 10.7.31.224 $1 >/dev/null 2>&1 && echo "OPEN" || echo "BLOCKED"; }
echo "C+D monitor — $(date '+%Y-%m-%d %H:%M:%S %Z') — Mac 1 client ($(ipconfig getifaddr en0)) — output: $OUT"
echo "time     | via Mac 2 edge                 | via Mac 3 edge   | Mac1 -> backend :3001  :3002 (direct)"
n=0; run=$(date +%H%M%S); start=$(date +%s)
while (( $(date +%s) - start < ${1:-420} )); do
  (( n++ ))
  r2=($(probe 10.7.19.93 "$run-$n-m2")); r3=($(probe 10.7.31.224 "$run-$n-m3"))
  printf '%s | HTTP %s backend %-2s cache %-5s | HTTP %s backend %-2s | %-7s %-7s\n' "$(date +%H:%M:%S)" \
    "${r2[1]:-000}" "${r2[2]:--}" "${r2[3]:--}" "${r3[1]:-000}" "${r3[2]:--}" "$(direct 3001)" "$(direct 3002)"
  sleep 1
done
echo "Monitor finished $(date +%H:%M:%S)"
