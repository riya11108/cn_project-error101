#!/bin/zsh
# Extension B — DNS TTL and controlled record change (run on MAC 1 — Manpreet)
#
# What it shows:
#   1. A client resolver caches an answer for the record's TTL (30 s): TTL counts down.
#   2. The DNS record is changed on the primary server: the server answers NEW immediately,
#      but the client keeps getting the OLD cached answer until the TTL expires.
#   3. After expiry the client re-queries and gets the NEW answer.
#   4. A manual cache flush makes a changed record visible immediately.
#
# "Client cache" = a temporary caching-only dnsmasq on 127.0.0.1:5300 that forwards
# team1.test to the primary DNS (10.7.9.246). It behaves like any caching resolver
# (OS stub cache, ISP/corporate resolver). Only the test name ttl.team1.test is changed;
# app.team1.test and api.team1.test are never touched.

set -u
BASE="$(cd "$(dirname "$0")/.." && pwd)/evidence/phase2/B_dns_ttl"
mkdir -p "$BASE"
STAMP=$(date +%Y%m%d_%H%M%S)
OUT="$BASE/B_ttl_demo_run_$STAMP.txt"
CLOG="$BASE/B_client_cache_queries_$STAMP.log"
HOSTS=/opt/homebrew/etc/team1-ttl.hosts
DNSMASQ=/opt/homebrew/opt/dnsmasq/sbin/dnsmasq
PRIMARY=10.7.9.246
NAME=ttl.team1.test
OLD=10.7.19.93      # Mac 2 (original edge)
NEW=10.7.31.224     # Mac 3 (standby edge)

exec > >(tee -a "$OUT") 2>&1

ts()   { date '+%H:%M:%S'; }
say()  { echo; echo "[$(ts)] ========== $* =========="; }
ans()  { local a; a=$(dig +nocmd "$@" $NAME +noall +answer +time=2 +tries=1 | tr -s '\t ' ' '); echo "${a:-(no answer)}"; }
q_primary() { echo "[$(ts)] PRIMARY DNS  @$PRIMARY:53      -> $(ans @$PRIMARY)"; }
q_cache()   { echo "[$(ts)] CLIENT CACHE @127.0.0.1:5300 -> $(ans @127.0.0.1 -p 5300)"; }
primary_pid() { pgrep -f "dnsmasq --keep-in-foreground -C /opt/homebrew/etc/dnsmasq.conf" | head -1; }
set_record() {
  printf '# Extension B test record (only ttl.team1.test; app/api are untouched)\n%s %s\n' "$1" "$NAME" > "$HOSTS"
  sudo kill -HUP "$(primary_pid)"
  sleep 0.5
  echo "[$(ts)] ADMIN: record changed on primary -> $NAME = $1 (edited $HOSTS, sent SIGHUP to primary dnsmasq)"
}

echo "Extension B TTL demo — $(date '+%Y-%m-%d %H:%M:%S %Z') — $(scutil --get ComputerName) ($(ipconfig getifaddr en0))"
echo "Evidence: $OUT"
echo "Client-cache query log: $CLOG"

say "SETUP (needs your Mac password once)"
sudo -v || { echo "sudo failed — stopping."; exit 1; }
printf '# Extension B test record\n%s %s\n' "$OLD" "$NAME" > "$HOSTS"
cur=$(dig @$PRIMARY $NAME +short +time=1 +tries=1)
echo "[$(ts)] Primary currently answers $NAME -> '${cur:-nothing}'"
if [[ "$cur" != "$OLD" ]]; then
  echo "[$(ts)] Restarting primary dnsmasq (launchd system/sh.brew.dnsmasq) once to load addn-hosts; backup DNS covers the ~2 s gap"
  sudo launchctl kickstart -k system/sh.brew.dnsmasq
  for i in {1..20}; do [[ "$(dig @$PRIMARY $NAME +short +time=1 +tries=1)" == "$OLD" ]] && break; sleep 0.5; done
fi
cur=$(dig @$PRIMARY $NAME +short +time=1 +tries=1)
if [[ "$cur" != "$OLD" ]]; then echo "STOP: primary still answers '${cur:-nothing}' for $NAME (expected $OLD). Nothing else was changed."; exit 1; fi
echo "[$(ts)] Primary serves $NAME -> $OLD (primary dnsmasq pid now $(primary_pid))"
pkill -f -- "--port=5300" 2>/dev/null; sleep 0.3
$DNSMASQ -C /dev/null --port=5300 --listen-address=127.0.0.1 --bind-interfaces \
  --no-resolv --no-hosts --server=/team1.test/$PRIMARY --cache-size=150 \
  --pid-file= --log-queries --log-facility="$CLOG" 2>/dev/null
sleep 0.5
CPID=$(pgrep -f -- "--port=5300" | head -1)
echo "[$(ts)] Client caching resolver started (pid $CPID), cache is empty"
q_primary

say "STEP 1 — Client resolves the name (B1: TTL = 30 s, then counting down = served from cache)"
q_cache
T0=$(date +%s)
sleep 4
q_cache
sleep 4
q_cache

say "STEP 2 — Controlled record change: $NAME $OLD -> $NEW (B2)"
set_record "$NEW"
q_primary

say "STEP 3 — Client still receives the OLD cached answer until the TTL expires (B3)"
while true; do
  line=$(q_cache)
  echo "$line   [$(( $(date +%s) - T0 ))s since client cached it]"
  [[ "$line" == *"$NEW"* ]] && break
  (( $(date +%s) - T0 > 45 )) && { echo "Did not change within 45 s — unexpected"; break; }
  sleep 4
done

say "STEP 4 — TTL expired: client re-queried the server and now gets the NEW answer (B4)"
q_cache

say "STEP 5 — Change the record back ($NEW -> $OLD). Client cache now holds the stale NEW answer"
set_record "$OLD"
q_primary
q_cache

say "STEP 6 — Manually flush the client cache (B5): SIGHUP clears the resolver cache"
kill -HUP "$CPID"
sleep 0.3
echo "[$(ts)] Client cache flushed (kill -HUP $CPID)"
q_cache
echo "        ^ changed answer visible IMMEDIATELY after flush, without waiting for the TTL"

say "CLEANUP"
kill "$CPID" 2>/dev/null && echo "[$(ts)] Client caching resolver stopped"
echo "[$(ts)] $NAME left at $OLD. app.team1.test / api.team1.test were never modified:"
echo "        $(dig @$PRIMARY app.team1.test +noall +answer | tr -s '\t ' ' ')"
echo "        $(dig @$PRIMARY api.team1.test +noall +answer | tr -s '\t ' ' ')"
echo
echo "Client cache log (forwarded = asked the server, cached = answered from cache):"
grep -E "forwarded|reply|cached|cleared" "$CLOG" | grep -v "cachesize"
echo
echo "DONE. Take the screenshots now (scroll as needed)."
