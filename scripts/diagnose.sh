#!/bin/zsh
# Extension F — layered fault diagnosis (run from any client Mac; read-only, changes nothing).
# Usage: diagnose.sh [hostname] [port]      default: app.team1.test 8443
# Order follows the project rule: DNS -> IP reachability -> TCP -> TLS -> HTTP/proxy -> backend.
# It stops at the FIRST failing layer and tells you where to look next.

NAME=${1:-app.team1.test}; PORT=${2:-8443}
PRIMARY=10.7.9.246; BACKUP=10.7.31.224; MAC2=10.7.19.93; MAC3=10.7.31.224
ok()   { printf '  \e[32mPASS\e[0m  %s\n' "$*"; }
bad()  { printf '  \e[31mFAIL\e[0m  %s\n' "$*"; }
info() { printf '        %s\n' "$*"; }
hdr()  { printf '\n\e[1m[%s] %s\e[0m\n' "$1" "$2"; }
stop() { printf '\n\e[1;31m==> Fault isolated at layer: %s\e[0m\n%s\n' "$1" "$2"; exit 1; }

echo "Diagnosing https://$NAME:$PORT  from $(scutil --get ComputerName) ($(ipconfig getifaddr en0))  at $(date '+%H:%M:%S')"

hdr 1 "DNS — does the name resolve, and to the expected edge?"
p=$(dig @$PRIMARY $NAME +short +time=2 +tries=1 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
b=$(dig @$BACKUP  $NAME +short +time=2 +tries=1 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
s=$(dscacheutil -q host -a name $NAME 2>/dev/null | awk '/ip_address/{print $2; exit}')
[[ -n $p ]] && ok "primary DNS $PRIMARY -> $p" || bad "primary DNS $PRIMARY: no answer (dnsmasq down? firewall? wrong record?)"
[[ -n $b ]] && ok "backup  DNS $BACKUP -> $b" || bad "backup  DNS $BACKUP: no answer"
[[ -n $s ]] && ok "this Mac's system resolver -> $s" || bad "system resolver: no answer (check /etc/resolver/team1.test or System Settings DNS)"
[[ -n $p && -n $b && $p != $b ]] && info "WARNING: primary and backup disagree ($p vs $b) — record changed on one server only?"
IP=${s:-${p:-$b}}
[[ -z $IP ]] && stop "DNS" "Check: dnsmasq running on Mac 1/Mac 3 (sudo brew services list), address= lines, client DNS settings, typo in name."
[[ $IP != $MAC2 && $IP != $MAC3 ]] && info "WARNING: $IP is not a known edge (Mac 2 $MAC2 / Mac 3 $MAC3) — wrong record?"

hdr 2 "IP reachability — can we reach $IP at all?"
if ping -c 2 -t 3 $IP >/dev/null 2>&1; then ok "ping $IP"; else bad "ping $IP failed"; info "(ICMP can be filtered; continuing to TCP test)"; fi

hdr 3 "TCP — is anything accepting connections on $IP:$PORT?"
t0=$(perl -MTime::HiRes=time -e 'print time'); nc -z -G 4 $IP $PORT >/dev/null 2>&1; rc=$?
dt=$(perl -MTime::HiRes=time -e "printf '%.1f', time-$t0")
if (( rc == 0 )); then ok "TCP connect $IP:$PORT (${dt}s)"
else
  bad "TCP connect $IP:$PORT failed after ${dt}s"
  if (( ${dt%.*} >= 3 )); then stop "TCP (timeout = packets silently dropped)" "Likely a FIREWALL (macOS Application Firewall / PF) on $IP, or host asleep. Compare: ping works but TCP times out."
  else stop "TCP (refused = host up, nothing listening)" "nginx not running or listening on a different port on $IP. Check: lsof -nP -iTCP:$PORT -sTCP:LISTEN on that Mac; wrong port in URL?"; fi
fi

hdr 4 "TLS — handshake and certificate validation"
tls=$(echo | openssl s_client -connect $IP:$PORT -servername $NAME -verify_return_error 2>&1)
if echo "$tls" | grep -q "Verify return code: 0"; then
  ok "TLS handshake OK, certificate trusted ($(echo "$tls" | grep -m1 -oE 'Protocol *: *TLSv[0-9.]+' | tr -s ' '))"
else
  bad "TLS problem: $(echo "$tls" | grep -m1 -E 'Verify return code|verify error|alert|errno' )"
  stop "TLS" "Check: cert/key paths in nginx.conf, cert SAN covers $NAME (openssl x509 -noout -ext subjectAltName), mkcert root CA trusted on this client, cert expiry."
fi
san=$(echo "$tls" | openssl x509 -noout -ext subjectAltName 2>/dev/null | tail -1 | tr -d ' ')
info "certificate SAN: $san"

hdr 5 "HTTP / reverse proxy — does nginx return a good response?"
resp=$(curl -s -D - -o /tmp/diag_body.$$ --max-time 15 --resolve $NAME:$PORT:$IP "https://$NAME:$PORT/api/status?diag=$RANDOM" -w 'CODE=%{http_code} TIME=%{time_total}')
code=$(echo "$resp" | grep -oE 'CODE=[0-9]+' | cut -d= -f2); tt=$(echo "$resp" | grep -oE 'TIME=[0-9.]+' | cut -d= -f2)
be=$(echo "$resp" | awk -F': ' 'tolower($1)=="x-backend"{print $2}' | tr -d '\r')
case $code in
  200) ok "HTTP 200 in ${tt}s, served by Backend ${be:-?}  body: $(cat /tmp/diag_body.$$)";;
  502) bad "HTTP 502 Bad Gateway"; stop "Application/backend (nginx is fine, upstreams refused)" "Backends down. On Mac 3: lsof -nP -iTCP:3001 -iTCP:3002 -sTCP:LISTEN; restart node server.js. Check nginx error.log for 'connect() failed (61: Connection refused)'.";;
  504) bad "HTTP 504 Gateway Timeout"; stop "Edge -> backend path (timeout)" "nginx cannot reach backends in time: firewall on Mac 3 (ALF/PF) dropping edge traffic, or wrong upstream IP. nginx error.log shows 'upstream timed out'.";;
  000) bad "no HTTP response (${tt}s)"; stop "Proxy hang" "TLS OK but no reply: nginx waiting on upstreams (default proxy_connect_timeout 60 s). Check backends/firewall on Mac 3 and nginx error.log.";;
  *)   bad "HTTP $code"; stop "HTTP/proxy config" "Unexpected status — check nginx location/proxy_pass/server_name.";;
esac
rm -f /tmp/diag_body.$$
[[ $tt == <->.* && ${tt%.*} -ge 3 ]] && info "WARNING: slow (${tt}s) — a backend may be failing and nginx retrying (proxy_next_upstream)."

hdr 6 "Load balancing — both backends answering through the edge?"
seen=""; for i in 1 2 3 4; do seen+=$(curl -s -D - -o /dev/null --max-time 8 --resolve $NAME:$PORT:$IP "https://$NAME:$PORT/api/status?lb=$RANDOM$i" | awk -F': ' 'tolower($1)=="x-backend"{print $2}' | tr -d '\r'); done
[[ $seen == *A* && $seen == *B* ]] && ok "responses from A and B ($seen)" || { bad "only saw: ${seen:-nothing}"; info "One backend down or marked failed (max_fails=1 fail_timeout=5s). Check Mac 3 ports 3001/3002."; }

printf '\n\e[1;32m==> All layers healthy for %s via %s\e[0m\n' "$NAME" "$IP"
