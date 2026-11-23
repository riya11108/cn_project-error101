#!/bin/zsh
# Extension E — Controlled edge migration (DNS-based cutover), run on MAC 1 — Manpreet
#
# Story: app.team1.test starts on the ORIGINAL edge (Mac 2, 10.7.19.93). We migrate it to the
# STANDBY edge (Mac 3, 10.7.31.224) by changing the DNS record. An EXISTING client that already
# cached the old answer keeps connecting to Mac 2 until the 30 s TTL expires, while a NEW client
# (fresh lookup) goes straight to Mac 3. Both edges keep serving HTTPS during the cutover.
#
# "Existing client" = caching resolver on 127.0.0.1:5300 (forwards team1.test to the primary DNS).
# "New client"      = a fresh query straight to the primary DNS (no cache).
# Each client then opens HTTPS to the IP *its* DNS lookup returned (curl --resolve only hands curl
# that address — exactly what a browser does after DNS), and curl reports which edge IP answered.
#
# Also configures Mac 1 as a project DNS client: /etc/resolver/team1.test -> primary + backup
# (affects only *.team1.test names; normal internet DNS is untouched).

set -u
BASE="$(cd "$(dirname "$0")/.." && pwd)/evidence/phase2/E_edge_migration"
mkdir -p "$BASE"
STAMP=$(date +%Y%m%d_%H%M%S)
OUT="$BASE/E_migration_run_$STAMP.txt"
CLOG="$BASE/E_existing_client_cache_$STAMP.log"
CONF=/opt/homebrew/etc/dnsmasq.conf
DNSMASQ=/opt/homebrew/opt/dnsmasq/sbin/dnsmasq
PRIMARY=10.7.9.246
OLD=10.7.19.93      # Mac 2 — original edge
NEW=10.7.31.224     # Mac 3 — standby edge
NAME=app.team1.test

exec > >(tee -a "$OUT") 2>&1
ts() { date '+%H:%M:%S'; }
say() { echo; echo "[$(ts)] ========== $* =========="; }
edge_of() { [[ "$1" == "$OLD" ]] && echo "Mac 2 original edge" || { [[ "$1" == "$NEW" ]] && echo "Mac 3 standby edge" || echo "?"; }; }
https_via() {  # $1 = IP the client's DNS returned
  curl -s -o /dev/null --max-time 8 --resolve "$NAME:8443:$1" \
    -w "HTTPS %{http_code}, TLS verify=%{ssl_verify_result}, connected to %{remote_ip}:%{remote_port}" \
    "https://$NAME:8443/api/status?e=$RANDOM"
}
client() {  # $1 label, rest = dig args
  local label=$1; shift
  local ip=$(dig "$@" $NAME +short +time=2 +tries=1 | head -1)
  local ttl=$(dig +nocmd "$@" $NAME +noall +answer +time=2 +tries=1 | awk '{print $2}' | head -1)
  printf '[%s] %-16s DNS -> %-12s (TTL %2s)  => %s  [%s]\n' "$(ts)" "$label" "${ip:-none}" "${ttl:--}" "$(https_via "$ip")" "$(edge_of "$ip")"
}
set_primary() {
  sed -i '' -E "s|^address=/$NAME/.*|address=/$NAME/$1|" "$CONF"
  sudo launchctl kickstart -k system/sh.brew.dnsmasq
  for i in {1..20}; do [[ "$(dig @$PRIMARY $NAME +short +time=1 +tries=1)" == "$1" ]] && break; sleep 0.3; done
  echo "[$(ts)] ADMIN: primary DNS record changed -> $NAME = $1 ($(edge_of "$1")); primary now answers $(dig @$PRIMARY $NAME +short)"
}

echo "Extension E edge migration demo — $(date '+%Y-%m-%d %H:%M:%S %Z') — $(scutil --get ComputerName) ($(ipconfig getifaddr en0))"
echo "Evidence: $OUT"

say "SETUP (needs your Mac password once)"
sudo -v || { echo "sudo failed — stopping."; exit 1; }
cp "$CONF" "$CONF.bak-extE-$STAMP"; echo "[$(ts)] Backed up $CONF -> $CONF.bak-extE-$STAMP"
echo "[$(ts)] Before: primary $NAME -> $(dig @$PRIMARY $NAME +short), backup -> $(dig @$NEW $NAME +short)"
echo "[$(ts)] Both edges healthy?  Mac 2: $(https_via $OLD)   |   Mac 3: $(https_via $NEW)"

say "STEP 1 — Pre-migration state: $NAME served by the ORIGINAL edge (Mac 2)"
set_primary "$OLD"
pkill -f -- "--port=5300" 2>/dev/null; sleep 0.3
$DNSMASQ -C /dev/null --port=5300 --listen-address=127.0.0.1 --bind-interfaces --no-resolv --no-hosts \
  --server=/team1.test/$PRIMARY --cache-size=150 --pid-file= --log-queries --log-facility="$CLOG" 2>/dev/null
sleep 0.5; CPID=$(pgrep -f -- "--port=5300" | head -1)
client "EXISTING client" @127.0.0.1 -p 5300
echo "        ^ existing client resolved the name and cached it (TTL 30 s)"
sleep 3
client "EXISTING client" @127.0.0.1 -p 5300

say "STEP 2 — MIGRATION: DNS cutover of $NAME to the STANDBY edge (Mac 3)"
set_primary "$NEW"
T0=$(date +%s)

say "STEP 3 — During TTL window: existing client still hits OLD edge, new lookups go to NEW edge (E4/E5)"
while true; do
  client "NEW client"      @$PRIMARY
  line=$(client "EXISTING client" @127.0.0.1 -p 5300); echo "$line   [+$(( $(date +%s) - T0 ))s after cutover]"
  [[ "$line" == *"Mac 3 standby"* ]] && break
  (( $(date +%s) - T0 > 45 )) && { echo "Did not switch within 45 s — unexpected"; break; }
  sleep 5
done

say "STEP 4 — TTL expired: existing client re-resolved and now also reaches the standby edge"
client "EXISTING client" @127.0.0.1 -p 5300
client "NEW client"      @$PRIMARY

say "CLEANUP + Mac 1 as a project DNS client"
kill "$CPID" 2>/dev/null && echo "[$(ts)] Existing-client caching resolver stopped"
if [[ ! -f /etc/resolver/team1.test ]]; then
  sudo mkdir -p /etc/resolver
  printf 'nameserver %s\nnameserver %s\n' "$PRIMARY" "$NEW" | sudo tee /etc/resolver/team1.test >/dev/null
  echo "[$(ts)] Created /etc/resolver/team1.test (macOS per-domain resolver: primary $PRIMARY, backup $NEW)"
fi
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
sleep 1
echo "[$(ts)] Final: primary $NAME -> $(dig @$PRIMARY $NAME +short), backup -> $(dig @$NEW $NAME +short)"
echo "[$(ts)] macOS system resolver (scutil --dns, team1.test):"; scutil --dns | grep -A4 'domain   : team1.test' | head -5
echo "[$(ts)] System lookup: $(dscacheutil -q host -a name $NAME | grep ip_address)"
echo "[$(ts)] Plain curl (system DNS, no -k, no --resolve):"
curl -s -D - -o - --max-time 8 "https://$NAME:8443/api/status?final=$RANDOM" -w "\n  -> connected to %{remote_ip}, TLS verify=%{ssl_verify_result}\n" | grep -iE "^HTTP|x-backend|connected|backend"
echo
echo "Existing-client resolver log (forwarded = asked server, cached = answered from cache):"
grep -E "forwarded|reply|cached" "$CLOG"
echo
echo "DONE"
