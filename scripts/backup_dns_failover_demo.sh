#!/bin/zsh
# Extension A — stop the PRIMARY DNS (Mac 1) and show the client still resolves via the BACKUP (Mac 3); then restore.
# Run on MAC 1. One sudo prompt. Primary is down ~10 s.
set -u
OUT="$(cd "$(dirname "$0")/.." && pwd)/evidence/phase2/A_backup_dns/A2_A3_primary_stopped_backup_answers_$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee -a "$OUT") 2>&1
ts() { date +%H:%M:%S; }
flush() { sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; sleep 1; }
echo "Ext A backup DNS failover — $(date '+%Y-%m-%d %H:%M:%S %Z') — $(scutil --get ComputerName) ($(ipconfig getifaddr en0))"
sudo -v || exit 1
echo "[$(ts)] Client resolver order for team1.test:"; scutil --dns | grep -A3 'domain   : team1.test' | grep nameserver
echo "[$(ts)] BEFORE: primary -> $(dig @10.7.9.246 app.team1.test +short +time=1 +tries=1) | backup -> $(dig @10.7.31.224 app.team1.test +short +time=1 +tries=1)"
echo; echo "[$(ts)] ===== STOP primary DNS on Mac 1 (sudo launchctl bootout system/sh.brew.dnsmasq)"
sudo launchctl bootout system/sh.brew.dnsmasq 2>&1; sleep 1
echo "[$(ts)] primary port 53 listeners: $(sudo lsof -nP -iUDP:53 2>/dev/null | grep -c dnsmasq) dnsmasq socket(s)"
echo "[$(ts)] dig @10.7.9.246 (primary): $(dig @10.7.9.246 app.team1.test +short +time=1 +tries=1 2>&1 | tail -1)"
echo "[$(ts)] dig @10.7.31.224 (backup): $(dig @10.7.31.224 app.team1.test +short +time=1 +tries=1)"
flush
echo "[$(ts)] CLIENT system lookup (OS resolver tries primary, falls back to backup):"
t0=$(perl -MTime::HiRes=time -e 'print time'); r=$(dscacheutil -q host -a name app.team1.test | grep ip_address); t1=$(perl -MTime::HiRes=time -e "printf '%.1f', time-$t0")
echo "        $r   (took ${t1}s)"
echo "[$(ts)] CLIENT HTTPS by name while primary DNS is DOWN:"
curl -s -o /dev/null --max-time 15 -w "        HTTP %{http_code}, connected to %{remote_ip}:%{remote_port}, TLS verify=%{ssl_verify_result}, DNS lookup %{time_namelookup}s\n" "https://app.team1.test:8443/api/status?extA=$(date +%s)"
echo; echo "[$(ts)] ===== RESTORE primary DNS (sudo launchctl bootstrap system /Library/LaunchDaemons/sh.brew.dnsmasq.plist)"
sudo launchctl bootstrap system /Library/LaunchDaemons/sh.brew.dnsmasq.plist 2>&1
for i in {1..20}; do dig @10.7.9.246 app.team1.test +short +time=1 +tries=1 | grep -q . && break; sleep 0.5; done
echo "[$(ts)] AFTER: primary -> $(dig @10.7.9.246 app.team1.test +short +time=1 +tries=1) | backup -> $(dig @10.7.31.224 app.team1.test +short +time=1 +tries=1)"
flush
echo "DONE"
