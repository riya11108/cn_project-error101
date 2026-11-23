# Extension F — Faculty-Injected Fault: Diagnosis Checklist

**Rule:** go layer by layer, bottom-up along the request path, and **say out loud** what each result proves.
`DNS → IP reachability → TCP → TLS → nginx (HTTP/proxy) → backend`. Stop at the first failing layer.

**Fast path:** run `scripts/diagnose.sh` from Mac 1 (read-only). It prints PASS/FAIL per layer
and names the layer where the fault is. Then confirm manually with the commands below.

---

## Layer 1 — DNS (name → IP)
| Check (Mac 1) | Healthy result |
|---|---|
| `dig @10.7.9.246 app.team1.test` | `A 10.7.31.224` (or 10.7.19.93 if app is on Mac 2), TTL 30 |
| `dig @10.7.31.224 app.team1.test` | same answer as primary |
| `dscacheutil -q host -a name app.team1.test` | system resolver gives the same IP |
| `scutil --dns \| grep -A3 team1.test` | nameservers 10.7.9.246, 10.7.31.224 |

| Symptom | Likely fault | Fix |
|---|---|---|
| `NXDOMAIN` | record removed / typo in `address=` | fix `/opt/homebrew/etc/dnsmasq.conf`, `sudo brew services restart dnsmasq` |
| `connection timed out; no servers could be reached` | dnsmasq stopped, or firewall | `sudo brew services list`, start dnsmasq; check ALF allow rule |
| answers a **wrong IP** | record points elsewhere | correct `address=` line on **both** servers |
| primary and backup disagree | changed on one server only | make both identical |
| `dig @server` OK but browser/curl fails | client resolver config / stale cache | `/etc/resolver/team1.test`; `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder` |

**Say:** "DNS only gives the address. If DNS is right, the problem is further along the path."

## Layer 2 — IP reachability
`ping -c 3 <edge IP>`. Fails → wrong subnet/Wi-Fi, IP changed (DHCP!), machine asleep. Check `ipconfig getifaddr en0` on every Mac.
Note: ping can work while TCP is blocked (firewalls filter per port/app), so always continue to layer 3.

## Layer 3 — TCP (port)
`nc -vz -G 4 <edge IP> 8443`
| Result | Meaning |
|---|---|
| succeeded | something listens on 8443 |
| **Connection refused (instant)** | host up, **nothing listening** → nginx down / wrong port |
| **timeout (seconds)** | packets **silently dropped** → firewall (ALF/PF) or host unreachable |

On the edge Mac: `lsof -nP -iTCP:8443 -sTCP:LISTEN`, `sudo nginx -t`, start nginx.
Firewall: `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate --listapps`, `sudo pfctl -s info; sudo pfctl -sr`.

## Layer 4 — TLS
`openssl s_client -connect <edge IP>:8443 -servername app.team1.test </dev/null | grep -E "Verify return|Protocol"`
`curl -v https://app.team1.test:8443/api/status` (never `-k` in the demo)
| Symptom | Fault |
|---|---|
| `certificate verify failed` / `unable to get local issuer` | mkcert CA not trusted on this client, or wrong cert |
| `no alternative certificate subject name matches` | cert SAN does not include the hostname used |
| handshake failure / nginx won't start | wrong `ssl_certificate(_key)` path or key/cert mismatch (`sudo nginx -t`) |
| `wrong version number` | talking TLS to a plain-HTTP port (e.g. 8080) |

## Layer 5 — nginx reverse proxy (HTTP)
| Status | Meaning | Where to look |
|---|---|---|
| 200 + `X-Backend` | healthy | — |
| **502 Bad Gateway** | nginx up, **upstreams refused** (backends down / wrong port) | Mac 3 `lsof -iTCP:3001/3002`; nginx error.log `connect() failed (61: Connection refused)` |
| **504 / hang** | nginx can't reach upstreams in time (firewall drop, wrong IP) | error.log `upstream timed out (60)`; ALF/PF on Mac 3 |
| 404 | wrong path / location | nginx `location`, URL |
| 301 | used HTTP :8080 | expected redirect to HTTPS :8443 |
Logs: Mac 2 `/opt/homebrew/var/log/nginx/error.log`; Mac 3 standby `~/cn-project/standby-nginx/logs/error.log`.

## Layer 6 — Backend application
On Mac 3: `curl -s http://127.0.0.1:3001/api/status` and `:3002`; `lsof -nP -iTCP:3001 -iTCP:3002 -sTCP:LISTEN`.
From Mac 2: `curl -m 5 http://10.7.31.224:3001/api/status` (edge → backend path; PF Ext C allows only Mac 2).
Restart: `cd ~/cn-project/backend/backend-a && node server.js` (same for backend-b).
Only one backend in responses → the other is down or temporarily marked failed (`max_fails=1 fail_timeout=5s`).

---

## Real fault we diagnosed on 2026-11-23 (worked example)
Symptom: `https://app.team1.test:8443` completed TLS on Mac 2 but never returned HTTP.
1. DNS ✓ (both servers answered) 2. ping Mac 3 ✓ 3. TCP to Mac 3 :3001/:3002/:8443/:53 **timed out** (not refused)
4. Mac 2 error.log: `upstream timed out (60) while connecting to upstream` 5. On Mac 3 services were listening on `*:port` and
answered locally → **host firewall** (macOS Application Firewall ON, Homebrew node/nginx/dnsmasq not allowed).
Fix: allow the three binaries in ALF (firewall kept ON). Verified from Mac 1: all layers PASS.
Evidence: `evidence/audit_2026-11-23/*`, `evidence/phase2/F_troubleshooting/F2_after_fix_mac3_firewall.txt`, `docs/Phase2_Final_Report.md` §9.
