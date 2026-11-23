#!/bin/zsh
# Phase 1 evidence that needs sudo (run on MAC 1 — Manpreet):
#  (G) packet capture of one complete request: DNS -> TCP 3-way handshake -> TLS handshake -> encrypted data
#  (F2) "DNS record points to a wrong IP": test-only name wrong.team1.test -> Mac 1 (no web server on :8443)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTD="$ROOT/evidence/phase1/03_tcp_tls_packet_capture"; mkdir -p "$OUTD"
STAMP=$(date +%Y%m%d_%H%M%S)
LOG="$OUTD/phase1_capture_run_$STAMP.txt"
PCAP="$OUTD/TaskG_full_request_$STAMP.pcapng"
HOSTS=/opt/homebrew/etc/team1-ttl.hosts
TSHARK=/Applications/Wireshark.app/Contents/MacOS/tshark
exec > >(tee -a "$LOG") 2>&1
ts() { date '+%H:%M:%S'; }
primary_pid() { pgrep -f "dnsmasq --keep-in-foreground -C /opt/homebrew/etc/dnsmasq.conf" | head -1; }
flush() { sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; sleep 1; }

echo "Phase 1 capture run — $(date '+%Y-%m-%d %H:%M:%S %Z') — $(scutil --get ComputerName) ($(ipconfig getifaddr en0))"
sudo -v || exit 1

echo; echo "[$(ts)] ===== (G) Capturing one full client request on en0 + lo0 -> $PCAP"
flush
sudo tcpdump -i pktap,en0,lo0 -n -U -w "$PCAP" 'port 53 or port 8443' >/dev/null 2>&1 &
TPID=$!; sleep 2
echo "[$(ts)] client: system resolver lookup of app.team1.test (Mac 1 is configured to use 10.7.9.246, then 10.7.31.224)"
dscacheutil -q host -a name app.team1.test | grep ip_address
echo "[$(ts)] client: DNS query across the LAN to the backup server too (so DNS is also visible on en0)"
dig @10.7.31.224 app.team1.test +short
echo "[$(ts)] client: HTTPS request by name (no -k)"
curl -s -D - -o - "https://app.team1.test:8443/api/status?pcap=$RANDOM" -w "\n  -> local %{local_ip}:%{local_port}  ->  server %{remote_ip}:%{remote_port}, TLS verify=%{ssl_verify_result}\n" | grep -iE '^HTTP|x-backend|->|backend'
sleep 2; sudo kill -INT $TPID; sleep 1; wait $TPID 2>/dev/null
sudo chown "$(whoami)" "$PCAP"
echo "[$(ts)] capture saved: $(ls -l "$PCAP" | awk '{print $5}') bytes"

echo; echo "[$(ts)] ===== (G) Decoded with tshark (same view as Wireshark)"
echo "--- DNS (UDP 53): query + response"
$TSHARK -r "$PCAP" -Y 'dns.qry.name == "app.team1.test"' -T fields -e frame.time_relative -e ip.src -e udp.srcport -e ip.dst -e udp.dstport -e dns.flags.response -e dns.a 2>/dev/null | awk '{printf "  t=%.3fs  %s:%s -> %s:%s  %s %s\n",$1,$2,$3,$4,$5,($6=="True"||$6==1)?"RESPONSE":"QUERY",$7}'
echo "--- Full TCP + TLS exchange on 8443 (SYN, SYN-ACK, ACK, Client Hello, Server Hello, encrypted data, FIN)"
$TSHARK -r "$PCAP" -d tcp.port==8443,tls -Y 'tcp.port==8443' 2>/dev/null | sed 's/^/  /'

echo; echo "[$(ts)] ===== (F2) DNS record points to a WRONG IP"
cp "$HOSTS" "$HOSTS.bak-$STAMP"
echo "10.7.9.246 wrong.team1.test" >> "$HOSTS"; sudo kill -HUP "$(primary_pid)"; flush
echo "[$(ts)] DNS answer (lookup SUCCEEDS):"; dig @10.7.9.246 wrong.team1.test +noall +answer
echo "[$(ts)] but the client is sent to the wrong host (Mac 1 has no web server on 8443):"
curl -sS --max-time 5 "https://wrong.team1.test:8443/api/status"; echo "  curl exit=$?"
cp "$HOSTS.bak-$STAMP" "$HOSTS"; sudo kill -HUP "$(primary_pid)"; flush
echo "[$(ts)] test record removed -> $(dig @10.7.9.246 wrong.team1.test +noall +comments | grep -o 'status: [A-Z]*')"
echo; echo "DONE"
