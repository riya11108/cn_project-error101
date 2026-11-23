# Private Network Service Platform

Computer Networks course project — Team Error-101
Manpreet Singh · Avneet Singh · Riya Yadav

A small web service that runs entirely on a private LAN of three MacBooks. A client opens
`https://app.team1.test:8443`; the name is resolved by our own DNS server, the HTTPS connection is terminated by an
nginx reverse proxy, and the request is load-balanced across two REST backends. The application itself is
deliberately trivial — the point of the project is the network path in between: DNS, TCP, TLS, HTTP, load balancing,
caching, and what happens when parts of that path fail.

The project was built in two phases. Phase 1 builds the service and observes every protocol with packet captures.
Phase 2 hardens it: a backup DNS server, controlled DNS TTLs, a firewall that isolates the backends, backend failover,
a DNS-based move to a standby edge server, and a layer-by-layer method for diagnosing faults.

---

## Network design

The reference design uses four Macs. With three, Mac 3 hosts both backends as well as the backup DNS server and the
standby edge.

| Machine | Member | IP address | Role |
|---|---|---|---|
| Mac 1 | Manpreet | 10.7.9.246 | Primary DNS server (dnsmasq), test client |
| Mac 2 | Avneet | 10.7.19.93 | Edge server: nginx reverse proxy, TLS termination, load balancer, HTTP cache |
| Mac 3 | Riya | 10.7.31.224 | Backend A (port 3001), Backend B (port 3002), backup DNS server, standby nginx edge |

All three machines are on the same Wi-Fi network (10.7.0.0/19, gateway 10.7.0.1, interface `en0`).
The private domain is `team1.test` — the `.test` top-level domain is reserved for testing, so it never resolves on the
public internet and does not clash with macOS multicast DNS the way `.local` would.

```text
                              Private LAN 10.7.0.0/19
        +----------------------+----------------------------+-----------------------------+
        |                      |                            |                             |
   Mac 1  10.7.9.246      Mac 2  10.7.19.93            Mac 3  10.7.31.224
   dnsmasq  :53           nginx  :8443 (HTTPS)         Backend A :3001   Backend B :3002
   (primary DNS)                 :8080 (-> HTTPS)      dnsmasq :53 (backup DNS)
   client                 load balancer + cache        nginx :8443 (standby edge)

   client --DNS--> Mac 1 (or Mac 3) --A record--> edge IP --HTTPS--> nginx --HTTP--> Backend A / B
```

| Name | Address | Served by |
|---|---|---|
| `app.team1.test` | 10.7.31.224 | standby edge on Mac 3 (the application was migrated there in Phase 2; the edge on Mac 2 keeps running) |
| `api.team1.test` | 10.7.19.93 | edge on Mac 2 |

Both DNS servers hold identical records with a TTL of 30 seconds. Diagrams of the topology and the per-layer request
flow are in [`docs/Architecture.md`](docs/Architecture.md).

---

## How a request travels

1. **DNS (UDP 53).** macOS sends queries for `*.team1.test` to the servers listed in `/etc/resolver/team1.test`
   (10.7.9.246, then 10.7.31.224). dnsmasq answers `app.team1.test` with the edge's IP address and a 30-second TTL,
   which the client caches.
2. **TCP.** The client opens a connection from an ephemeral port to port 8443 on the edge with the three-way handshake
   (SYN, SYN-ACK, ACK).
3. **TLS 1.3.** The client sends a ClientHello with SNI `app.team1.test`; the server answers with its certificate,
   created with mkcert. Every Mac trusts the mkcert root CA, so the certificate verifies without `curl -k`.
4. **Reverse proxy.** nginx decrypts the request, checks its proxy cache, and forwards it to one of the two backends
   using round robin.
5. **Backend.** A small Express application answers `GET /api/status` with
   `{"backend":"A","status":"ok"}` plus the headers `X-Backend`, `Cache-Control: max-age=60` and an `ETag`.
6. The response returns to the client over the same encrypted connection.

A plain-HTTP request to port 8080 on Mac 2 is answered with `301` to the HTTPS URL.

---

## Components

### DNS — dnsmasq (Mac 1 primary, Mac 3 backup)
Records are defined with `address=/app.team1.test/<ip>`. `local-ttl=30` makes answers cacheable for 30 seconds.
dnsmasq listens only on the loopback and LAN address (`listen-address`, `bind-interfaces`). Mac 1 also loads
`team1-ttl.hosts` through `addn-hosts`; records in that file can be changed with a SIGHUP instead of a restart, which
we used for the TTL experiments.
Config: [`configs/mac1-primary-dns/`](configs/mac1-primary-dns/), [`configs/mac3-backup-dns/`](configs/mac3-backup-dns/).

### Edge — nginx (Mac 2, standby on Mac 3)
- `listen 8443 ssl` with the mkcert certificate for `app.team1.test`; port 8080 redirects to HTTPS.
- `upstream backend_servers` with both backends; default round-robin balancing.
- `proxy_cache` with `proxy_cache_valid 200 60s` and an `X-Cache-Status` header, so cached responses show `HIT` and
  conditional requests (`If-None-Match`) get `304 Not Modified`.
- Failure handling: `max_fails=1 fail_timeout=5s` takes a failed backend out of rotation for five seconds, and
  `proxy_next_upstream error timeout http_502 http_503 http_504` retries the request on the other backend.
- The standby edge on Mac 3 uses the same certificate and failover settings, with upstreams on `127.0.0.1`.

Config: [`configs/mac2-main-edge/nginx.conf`](configs/mac2-main-edge/nginx.conf),
[`configs/mac3-standby-edge/nginx.conf`](configs/mac3-standby-edge/nginx.conf).

### Backends — Node.js / Express (Mac 3)
Two copies of the same minimal service, differing only in port and identity (A on 3001, B on 3002). Both listen on
`0.0.0.0` so the edge can reach them over the LAN. Source: [`backend/`](backend/).

### Backend isolation — PF firewall (Mac 3)
Two rules allow only the edge (10.7.19.93) to reach ports 3001/3002 and drop everyone else. They are loaded into a
separate PF anchor, `com.apple/250.CNProject`, so the system ruleset is never modified and rollback is a single flush.
Rules and the saved baseline: [`configs/mac3-firewall/`](configs/mac3-firewall/).

---

## Phase 2: resilience and recovery

**Backup DNS.** The client lists two nameservers. With dnsmasq on Mac 1 stopped, lookups fall back to Mac 3 after the
first server times out (about 3 seconds in our test) and the site stays reachable.

**DNS TTL.** A client that has cached a record keeps using the old address after the record changes, until the
30-second TTL expires; it then asks again and gets the new one. Flushing the cache makes the change visible immediately.
Querying a server directly with `dig @server` bypasses caching entirely, so the effect is only visible through a cache.

**Service isolation.** With the PF rules active, a client connecting directly to a backend port times out, while the
edge still reaches both backends and the site keeps working over HTTPS. The rules are removed afterwards and the
ruleset returns to its saved baseline.

**Backend failover.** When Backend A stops, every request is answered by Backend B without any error reaching the
client; when A comes back, round robin resumes. With both backends down, the edge returns `502 Bad Gateway` — DNS, TCP
and TLS still succeed, which shows exactly where the failure is.

**Edge migration.** `app.team1.test` was moved from the edge on Mac 2 to the standby edge on Mac 3 by changing the DNS
record. New lookups went to Mac 3 straight away; a client holding the cached answer kept using Mac 2 until its TTL
expired (26 seconds after the change). Because both edges kept serving, no request failed during the move.

**Troubleshooting.** Faults are isolated one layer at a time — DNS, IP reachability, TCP, TLS, HTTP/proxy, backend.
A refused connection means the host is up but nothing listens on that port; a timeout means packets are being dropped,
usually by a firewall. The procedure is in [`docs/Troubleshooting_Checklist.md`](docs/Troubleshooting_Checklist.md)
and automated in `scripts/diagnose.sh`. While preparing Phase 2 we used it on a real outage: the services on Mac 3 were
running but unreachable because the macOS Application Firewall was dropping inbound connections to the Homebrew
binaries.

The full write-up with configuration, commands and observed results for every part is the
[Phase 2 report (PDF)](docs/Phase2_Final_Report.pdf) ([Markdown source](docs/Phase2_Final_Report.md)).

---

## Setting it up

1. **Backends (Mac 3):** `cd backend && npm install`, then `npm run start:a` and `npm run start:b` in two terminals.
2. **DNS (Mac 1 and Mac 3):** copy the dnsmasq configuration from `configs/` to `/opt/homebrew/etc/dnsmasq.conf` and run
   `sudo brew services restart dnsmasq`.
3. **TLS certificate:** on the edge, `mkcert -install` and `mkcert app.team1.test`; install the mkcert root CA on every
   client. Private keys stay on the machines and are excluded from the repository.
4. **Edge (Mac 2, and Mac 3 for the standby):** install the nginx configuration from `configs/`, check it with
   `sudo nginx -t`, then start or reload nginx.
5. **Clients (all Macs):** copy `configs/mac1-primary-dns/resolver-team1.test` to `/etc/resolver/team1.test`.
6. **macOS firewall:** if it is enabled, allow incoming connections for `node`, `nginx` and `dnsmasq`.

More detail — TLS notes, PF commands, live file locations — is in [`configs/README.md`](configs/README.md); the
original per-machine Phase 1 guides are in [`docs/setup/`](docs/setup/).

## Checking it works

```bash
dscacheutil -q host -a name app.team1.test                       # name resolves through the team DNS
curl -v https://app.team1.test:8443/api/status                   # TLS verifies, HTTP 200, X-Backend: A or B
for i in 1 2 3 4; do curl -s -D - -o /dev/null "https://app.team1.test:8443/api/status?n=$i" | grep -i x-backend; done
scripts/diagnose.sh                                              # checks every layer in order
```

---

## Repository layout

```text
backend/     Backend A and B (Express)
configs/     dnsmasq, nginx, resolver and PF configuration for each machine, with TLS and setup notes
docs/        Phase 2 report (PDF + Markdown), architecture diagrams, troubleshooting procedure, Phase 1 guides
evidence/    Screenshots, logs and packet captures from both phases
scripts/     Test and demonstration scripts used to produce the evidence
```

| Script | Purpose |
|---|---|
| `diagnose.sh` | Checks DNS, reachability, TCP, TLS, HTTP and load balancing in order and reports the first failing layer |
| `backup_dns_failover_demo.sh` | Stops the primary DNS, resolves and connects through the backup, then restores it |
| `ttl_demo.sh` | Shows a cached answer outliving a record change until the TTL expires, and a manual flush |
| `edge_migration_demo.sh` | Moves `app.team1.test` between edges and compares a cached client with a new one |
| `cd_monitor.sh` / `failover_monitor.sh` | Sends requests through both edges and to the backend ports once a second during failure tests |
| `phase1_capture.sh` | Captures one complete request (DNS, TCP, TLS) to a `.pcapng` file and decodes it |
| `e2e_check.sh`, `ev.sh`, `shot.sh`, `trim.py` | Helpers for recording command output and screenshots |
| `build_report_pdf.py` | Builds the PDF report from the Markdown source and screenshots |

### About the evidence
`evidence/phase1/` and `evidence/phase2/` hold one folder per task. Screenshots were taken on Mac 1, which is the test
client in this design; output produced on Mac 2 and Mac 3 (firewall rules, backend restarts, client checks on those
machines) was recorded on those machines and is included as text logs, with screenshots of it marked as relayed.
`evidence/audit_2026-11-23/` contains the read-only checks of all three machines taken before the Phase 2 fixes.

TLS private keys, the mkcert CA key and environment files are excluded by `.gitignore`.
