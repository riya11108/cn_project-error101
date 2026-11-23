# Private Network Service Platform — Team Error-101 (`team1.test`)

B.Tech Computer Networks course project: a private service on a local LAN built from three MacBooks —
**private DNS → TCP → TLS → nginx edge (load balancing + caching) → two REST backends** — then hardened in Phase 2 with a
backup DNS server, TTL-controlled cutovers, backend isolation, failover and a systematic troubleshooting method.

> *The application stays simple — the network is the project.*

| Member | Machine | IP | Role |
|---|---|---|---|
| Manpreet Singh | Mac 1 (MacBook Pro) | 10.7.9.246 | Primary DNS (dnsmasq) · test client |
| Avneet Singh | Mac 2 (MacBook Air) | 10.7.19.93 | Main edge: nginx — TLS, load balancing, caching |
| Riya Yadav | Mac 3 (MacBook Pro) | 10.7.31.224 | Backend A :3001 · Backend B :3002 · backup DNS · standby edge |

LAN 10.7.0.0/19 (gateway 10.7.0.1, Wi-Fi `en0`). The 4-Mac reference design is adapted to 3 Macs: Mac 3 combines roles.

```text
                         PRIVATE LAN 10.7.0.0/19
      ┌───────────────────────┬──────────────────────────┬──────────────────────────────┐
   Mac 1 10.7.9.246        Mac 2 10.7.19.93            Mac 3 10.7.31.224
   Primary DNS :53         nginx edge                  Backend A :3001   Backend B :3002
   client                  HTTPS :8443, HTTP :8080→301  Backup DNS :53
                           LB + proxy cache             Standby nginx edge :8443
   app.team1.test ──DNS──▶ (A record, TTL 30) ──HTTPS──▶ edge ──HTTP──▶ Backend A / B
```
Full diagrams (topology, per-layer request flow, Phase 2 resilience, migration timeline): [`docs/Architecture.md`](docs/Architecture.md)

### Current state (end of Phase 2, 23 Nov 2026)
| DNS record (primary **and** backup, TTL 30 s) | Points to | Note |
|---|---|---|
| `app.team1.test` | 10.7.31.224 — **standby edge on Mac 3** | migrated there in Ext E and kept for the final demo; the main edge on Mac 2 keeps running with the same certificate |
| `api.team1.test` | 10.7.19.93 — main edge on Mac 2 | certificate SAN covers only `app.team1.test` |

All three Macs resolve `*.team1.test` through `/etc/resolver/team1.test` → `nameserver 10.7.9.246` (primary), `nameserver 10.7.31.224` (backup).
Features only on the main edge (Mac 2): proxy cache (`X-Cache-Status`, 304) and the `:8080` → HTTPS redirect.

## Status — every requirement with its evidence
### Phase 1 — Build & Observe
| Task | Status | Evidence |
|---|---|---|
| A — Private LAN, IP/MAC/gateway, ping matrix | ✅ | [`evidence/phase1/01_lan_interfaces_ping/`](evidence/phase1/01_lan_interfaces_ping/) |
| B — Private DNS (dnsmasq); **all 3 Macs resolve via team DNS** (primary + backup); public DNS → NXDOMAIN | ✅ | [`evidence/phase1/02_dns/`](evidence/phase1/02_dns/) |
| C — Two REST backends with `X-Backend` | ✅ | [`backend/`](backend/) |
| D — nginx reverse proxy, round-robin LB | ✅ | [`evidence/phase1/04_load_balancing/`](evidence/phase1/04_load_balancing/) |
| E — HTTPS/TLS (mkcert, no `-k` on all 3 Macs), HTTP→HTTPS redirect | ✅ | [`evidence/phase1/02_dns/`](evidence/phase1/02_dns/) (`TaskB_mac*_client_*`), [`evidence/phase1/05_https_redirect/`](evidence/phase1/05_https_redirect/) |
| F — Cache-Control, ETag, MISS → HIT → **304** | ✅ | [`evidence/phase1/06_http_caching/`](evidence/phase1/06_http_caching/) |
| G — Packet capture DNS → TCP 3-way → TLS 1.3 (saved `.pcapng`) | ✅ | [`evidence/phase1/03_tcp_tls_packet_capture/`](evidence/phase1/03_tcp_tls_packet_capture/) |
| 6.3 — Failure demos (wrong DNS server, wrong IP, one/both backends down → 502, wrong port) | ✅ | [`evidence/phase1/07_failure_demos/`](evidence/phase1/07_failure_demos/) |

### Phase 2 — Harden & Recover
| Extension | Status | Evidence |
|---|---|---|
| A — Backup DNS resolver | ✅ | [`evidence/phase2/A_backup_dns/`](evidence/phase2/A_backup_dns/) |
| B — DNS TTL: cached old answer → expiry → new answer → manual flush | ✅ | [`evidence/phase2/B_dns_ttl/`](evidence/phase2/B_dns_ttl/) |
| C — Backend isolation with PF (only the edge reaches :3001/:3002), rolled back | ✅ | [`evidence/phase2/C_firewall/`](evidence/phase2/C_firewall/) |
| D — Backend failover (A down → B serves; both down → 502; recovery) | ✅ | [`evidence/phase2/D_backend_failover/`](evidence/phase2/D_backend_failover/) |
| E — DNS-based edge migration: cached client on old edge, new clients on standby | ✅ | [`evidence/phase2/E_edge_migration/`](evidence/phase2/E_edge_migration/) |
| F — Troubleshooting method + tool; real firewall fault diagnosed | ✅ ready | [`evidence/phase2/F_troubleshooting/`](evidence/phase2/F_troubleshooting/), [`docs/Troubleshooting_Checklist.md`](docs/Troubleshooting_Checklist.md) |

**Phase 2 report:** [PDF with screenshots](docs/Phase2_Final_Report.pdf) · [Markdown source](docs/Phase2_Final_Report.md) · **Architecture:** [`docs/Architecture.md`](docs/Architecture.md) ·
**Troubleshooting:** [`docs/Troubleshooting_Checklist.md`](docs/Troubleshooting_Checklist.md)

## Where the evidence was captured
- **Screenshots** were taken on **Mac 1** (each header shows machine, IP and time). Most show Mac 1 acting as the **client**
  (DNS, HTTPS, load balancing, caching, packet capture, TTL, migration, failover and firewall monitoring) — the brief's test-client role.
- **Server-side output from Mac 2 and Mac 3** (PF rules and rollback, backend stop/restart, client checks on those Macs, Task A
  ping/interface data) was produced **on those machines** by their owners' sessions and saved there
  (e.g. Mac 3 `~/cn-project/evidences/CD_mac3_timeline_231150.txt`); copies are in this repo as `.txt`, and screenshots of them are
  labelled *"output relayed from Mac 2/Mac 3"*.

## Repository layout
```text
README.md                    ← you are here (status + evidence index)
backend/                     Backend A (:3001) and B (:3002) — Express; `npm run start:a` / `npm run start:b`
configs/                     Configuration bundle, one folder per machine role (+ TLS setup notes)
  mac1-primary-dns/          dnsmasq.conf, team1-ttl.hosts, resolver-team1.test
  mac2-main-edge/            nginx.conf (TLS, upstreams, cache, failover)
  mac3-backup-dns/           dnsmasq.conf
  mac3-standby-edge/         nginx.conf
  mac3-firewall/             pf-cn-project.conf, pf-rules-before-project.txt (rollback baseline)
docs/
  Phase2_Final_Report.pdf    Phase 2 report for submission (13 pages, screenshots inline)
  Phase2_Final_Report.md     its Markdown source (objective, config, commands, expected vs observed, evidence, learning)
  Architecture.md            Diagrams (Mermaid) + IP/service inventory + SPOF analysis
  Troubleshooting_Checklist.md  Ext F layer-by-layer method
  Phase1_Overview.md         Original Phase 1 write-up (IPs updated)
  setup/                     Per-machine Phase 1 setup guides (Mac 1/2/3)
evidence/
  phase1/01…07_*/            Screenshots, .pcapng capture, decoded output, video
  phase2/A…F_*/              Screenshots + raw timestamped logs per extension
  audit_2026-11-23/          Read-only audit outputs of all three Macs (before the Phase 2 fixes)
scripts/                     Reproducible demos and tools (all run on Mac 1 unless noted)
```

## Scripts (`scripts/`)
| Script | Purpose |
|---|---|
| `diagnose.sh [name] [port]` | **Ext F:** read-only layered diagnosis DNS → IP → TCP → TLS → HTTP → LB; names the failing layer |
| `ttl_demo.sh` | **Ext B:** full TTL demonstration (~1 min, one sudo prompt) |
| `edge_migration_demo.sh` | **Ext E:** DNS cutover with cached vs new client (~1.5 min) |
| `cd_monitor.sh [seconds]` | **Ext C/D:** per-second HTTPS through both edges (unique URLs) + direct backend reachability |
| `backup_dns_failover_demo.sh` | **Ext A:** stop primary DNS, resolve + HTTPS via backup, restore (~20 s) |
| `phase1_capture.sh` | **Task G + failure 2:** packet capture of one full request, decoded with tshark |
| `e2e_check.sh <file>` | quick end-to-end health check, saved as evidence |
| `shot.sh <png> '<cmd>' [label]` | evidence screenshot: runs the command in a fresh Terminal window and captures only that window |
| `ev.sh <file> '<cmd>'` | run a command and append timestamped output to an evidence file |
| `failover_monitor.sh` | first Ext D monitor (run 1); superseded by `cd_monitor.sh` — see the cache-masking lesson in the report §7 |
| `trim.py` | helper for `shot.sh`: trims empty terminal space from screenshots |
| `build_report_pdf.py` | rebuilds `docs/Phase2_Final_Report.pdf` from the Markdown + screenshots (needs `reportlab`, `pillow`) |

## How to bring the platform up
1. **Mac 3 — backends:** `cd backend && npm install`, then `npm run start:a` and `npm run start:b` (two terminals). Both bind `0.0.0.0`.
2. **Mac 1 / Mac 3 — DNS:** install `configs/mac1-primary-dns/dnsmasq.conf` (+ `team1-ttl.hosts`) on Mac 1 and
   `configs/mac3-backup-dns/dnsmasq.conf` on Mac 3 at `/opt/homebrew/etc/`, then `sudo brew services restart dnsmasq`.
3. **Mac 2 / Mac 3 — edges:** mkcert certificate for `app.team1.test`; `configs/mac2-main-edge/nginx.conf` on Mac 2,
   `configs/mac3-standby-edge/nginx.conf` on Mac 3 (`nginx -p ~/cn-project/standby-nginx/ -c nginx.conf`); `sudo nginx -t` first.
4. **Every client Mac:** copy `configs/mac1-primary-dns/resolver-team1.test` to `/etc/resolver/team1.test` and trust the mkcert root CA.
5. **macOS Application Firewall** (if on): allow the real paths of `node`, `nginx`, `dnsmasq` — otherwise inbound connections are
   silently dropped (the outage diagnosed in Ext F).

Details, TLS notes and PF commands: [`configs/README.md`](configs/README.md); per-machine walkthroughs: [`docs/setup/`](docs/setup/).

## Quick verification (from any Mac)
```bash
dscacheutil -q host -a name app.team1.test               # → 10.7.31.224 (system resolver → team DNS)
curl -v https://app.team1.test:8443/api/status             # TLS verified, HTTP 200, X-Backend: A|B
scripts/diagnose.sh                                        # all layers PASS
```

## Security
Private keys, the mkcert CA key and `.env` files are excluded by `.gitignore` and were never read or committed.
