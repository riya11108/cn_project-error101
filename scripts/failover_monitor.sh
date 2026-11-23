#!/bin/zsh
# Ext D + Phase 1 failures 3/4 monitor (run on MAC 1). Every 2 s sends one HTTPS request through EACH edge
# (Mac 2 main edge, Mac 3 standby edge) with a unique URL (bypasses the edge cache) and logs status + backend.
# Stops ~15 s after both backends are back following an outage, or after 8 minutes.
set -u
OUT="$(cd "$(dirname "$0")/.." && pwd)/evidence/phase2/D_backend_failover/D_failover_timeline_$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee -a "$OUT") 2>&1
probe() {  # $1 edge IP, $2 unique request id (NOT $RANDOM: it repeats inside $(...) subshells in zsh)
  curl -s -o /dev/null --max-time 6 --resolve "app.team1.test:8443:$1" -D - "https://app.team1.test:8443/api/status?mon=$2" \
   -w '%{http_code}' | awk 'BEGIN{b="-";x="-"} tolower($1)=="x-backend:"{b=$2} tolower($1)=="x-cache-status:"{x=$2} /^[0-9][0-9][0-9]$/{c=$1} END{gsub("\r","",b); gsub("\r","",x); printf "%s %s %s", c, b, x}'
}
echo "Failover monitor — $(date '+%Y-%m-%d %H:%M:%S %Z') — Mac 1 ($(ipconfig getifaddr en0)) — output: $OUT"
echo "time      | via Mac 2 edge (10.7.19.93)          | via Mac 3 edge (10.7.31.224)"
start=$(date +%s); outage=0; healthy_after=0; n=0; run=$(date +%H%M%S)
while (( $(date +%s) - start < 480 )); do
  (( n++ )); r2=($(probe 10.7.19.93 "$run-$n-m2")); r3=($(probe 10.7.31.224 "$run-$n-m3"))
  printf '%s  | HTTP %s  backend %-2s cache %-5s | HTTP %s  backend %-2s\n' "$(date +%H:%M:%S)" "${r2[1]:-000}" "${r2[2]:--}" "${r2[3]:--}" "${r3[1]:-000}" "${r3[2]:--}"
  seen="${r2[2]:-}${r3[2]:-}"
  if [[ "${r2[1]:-}" != 200 || "${r3[1]:-}" != 200 || "$seen" == "BB" ]]; then outage=1; healthy_after=0; fi
  [[ "$seen" == *A* && $outage == 1 ]] && (( healthy_after++ ))
  (( healthy_after >= 6 )) && { echo "Recovered: Backend A serving again after the outage."; break; }
  sleep 2
done
echo "Monitor finished $(date +%H:%M:%S)"
