# Private Network Service Platform — Phase 2 Final Report
**Computer Networks course project · Team Error-101 · `team1.test`**
Manpreet Singh (Mac 1) · Avneet Singh (Mac 2) · Riya Yadav (Mac 3) · Evidence collected 23 November 2026

> Every result below is backed by a file under `evidence/`. Times are IST from the machines' clocks.
> **Verified** = observed in command output or a packet capture that is saved in this repository.

| Extension | Status | Evidence folder |
|---|---|---|
| A — Backup DNS resolver | ✅ Verified | `evidence/phase2/A_backup_dns/` |
| B — DNS TTL and controlled record change | ✅ Verified | `evidence/phase2/B_dns_ttl/` |
| C — Service isolation (backend firewall) | ✅ Verified | `evidence/phase2/C_firewall/` |
| D — High-availability backend failover | ✅ Verified | `evidence/phase2/D_backend_failover/` |
| E — Controlled edge migration (DNS cutover) | ✅ Verified | `evidence/phase2/E_edge_migration/` |

---

## 1. Introduction and Phase 2 objective
Phase 1 built a private service reachable by name: a client resolves `app.team1.test` through our own DNS (dnsmasq),
connects over HTTPS to an nginx edge that terminates TLS, load-balances across two REST backends and caches responses.
Phase 2 hardens the **same** infrastructure — backup DNS, controlled TTL behaviour, isolation of backend ports, backend
failover, a DNS-based migration to a standby edge — and prepares a systematic method to diagnose injected faults.

## 2. Updated three-Mac architecture
The reference design uses four Macs. We have three, so Mac 3 combines the backend tier with the backup DNS and the
standby edge ("teams of 2–3 may combine machine roles").

| Machine | Owner | IP (/19, gw 10.7.0.1, en0) | MAC | Services |
|---|---|---|---|---|
| Mac 1 | Manpreet | 10.7.9.246 | 36:b5:ac:b7:11:00 | **Primary DNS** dnsmasq :53, test client |
| Mac 2 | Avneet | 10.7.19.93 | 2e:30:0b:a1:32:2a | **Main edge** nginx 1.31.6: HTTPS :8443, HTTP :8080→301, TLS, round-robin LB, proxy cache |
| Mac 3 | Riya | 10.7.31.224 | 46:b2:52:34:a6:e0 | **Backend A** :3001, **Backend B** :3002 (Node 20/Express), **backup DNS** :53, **standby edge** nginx :8443 |

DNS (both servers, TTL 30 s): `app.team1.test → 10.7.31.224` (after Ext E) — kept on the standby edge for the final demo (team decision), `api.team1.test → 10.7.19.93`.
Diagrams: `docs/Architecture.md`. Configuration bundle: `configs/` (one folder per machine role).

### What changed from Phase 1
| Area | Phase 1 | Phase 2 |
|---|---|---|
| DNS | one dnsmasq (Mac 1) | + backup dnsmasq on Mac 3, identical records; `local-ttl=30` on both; Mac 1 client uses `/etc/resolver/team1.test` (primary, backup) |
| Edge | nginx on Mac 2 | + standby nginx on Mac 3 (same certificate, upstreams 127.0.0.1:3001/3002) |
| Upstream health | plain round robin | `max_fails=1 fail_timeout=5s`, `proxy_next_upstream error timeout http_502 http_503 http_504`, `proxy_next_upstream_tries 2` |
| Backend access | open to the LAN | PF anchor on Mac 3: only Mac 2 may reach :3001/:3002 (demonstrated, rolled back) |
| Test records | — | `ttl.team1.test` in `/opt/homebrew/etc/team1-ttl.hosts` (`addn-hosts`, reload with SIGHUP — no restart) |

## 3. Roles and responsibilities
- **Manpreet (Mac 1)** — primary DNS, records/TTL, client resolver, TTL + migration demos, monitoring, evidence, report.
- **Avneet (Mac 2)** — main nginx edge: TLS termination, load balancing, caching, upstream failover settings.
- **Riya (Mac 3)** — backends A/B, backup DNS, standby edge, PF firewall rules, backend failure and recovery.

---

## 4. Extension A — Backup DNS resolver ✅
**Objective.** Names keep resolving when the primary DNS server fails.
**Configuration.** dnsmasq on Mac 3 (`configs/mac3-backup-dns/dnsmasq.conf`): `listen-address=127.0.0.1,10.7.31.224`,
same `address=` records, `no-resolv`, upstreams 8.8.8.8/1.1.1.1. Client: `configs/mac1-primary-dns/resolver-team1.test`
installed as `/etc/resolver/team1.test` (nameserver 10.7.9.246, then 10.7.31.224).
**Fix found during Phase 2.** The backup answered with **TTL 0** (no `local-ttl`) and a stray `#` made the log file
`dnsmasq-backup.log#`. Fixed 22:50 (backup copy `dnsmasq.conf.bak-20261123` on Mac 3), dnsmasq restarted.
**Commands.** `dig @10.7.9.246 app.team1.test`, `dig @10.7.31.224 app.team1.test`, `scutil --dns`.
**Expected / observed.** Both servers return identical records with TTL 30 → observed (A1, A4).
**Failover test (23:21:13–23:21:20).** Primary dnsmasq stopped (`launchctl bootout system/sh.brew.dnsmasq`): `dig @10.7.9.246`
→ "connection timed out"; `dig @10.7.31.224` → 10.7.31.224. The client's **system** lookup still returned 10.7.31.224 — in **3.2 s**
(the OS first waits for the dead primary to time out, then asks the backup) — and `curl https://app.team1.test:8443` returned
HTTP 200 with TLS verified. Primary restored (`launchctl bootstrap`) after 6 s; both servers consistent again.
**Evidence.** `A1_backup_dns_records_both_servers.png`, `A2_A3_primary_stopped_backup_answers.png/.txt`, `A4_backup_dns_ttl_fixed.png/.txt`; script `scripts/backup_dns_failover_demo.sh`.
**Explanation.** DNS failure = names stop resolving although the service is up (curl by IP still works).
Application failure = name resolves, TCP may connect, but the service answers errors (502) or nothing.
**Learned.** Redundant servers must be *consistent* (our backup silently differed: TTL 0), and failover is not free —
each lookup pays the primary's timeout (~3 s) until the primary returns.

## 5. Extension B — DNS TTL and controlled record change ✅
**Objective.** Show caching for the TTL, the old answer persisting after a change until expiry, and a manual flush.
**Configuration.** `local-ttl=30`; test record `ttl.team1.test` in an `addn-hosts` file (record changes = edit + SIGHUP,
zero DNS downtime). Client cache: caching-only dnsmasq on 127.0.0.1:5300 forwarding `team1.test` to the primary.
Script: `scripts/ttl_demo.sh` (one sudo prompt, fully timed).

| Time | Event | Client answer |
|---|---|---|
| 22:55:40 | first lookup → `forwarded` to server | 10.7.19.93, TTL 30 |
| 22:55:44 / :48 | repeat → `cached` | TTL 26 / 22 |
| 22:55:49 | **record changed** to 10.7.31.224 (server answers new IP immediately) | — |
| 22:55:49 → 22:56:09 | client still gets the **old** IP | TTL 21 → 1 |
| 22:56:13 | TTL expired → re-query | **10.7.31.224**, TTL 30 |
| 22:56:14 | changed back; stale answer cached (TTL 29) → **manual flush** | changed answer **immediately** |

**Evidence.** `B1…B6*.png`, `B_ttl_demo_CLEAN_20261123_225504.txt`, `B_client_cache_queries_*.log`
(first attempt failed — primary hadn't loaded the file — kept as `FAILED_RUN_*`).
**Explanation.** TTL = how long a resolver may reuse an answer. Our earlier attempt "showed the new IP immediately" because
`dig @server` bypasses every cache. macOS OS-cache flush: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`.
**Production relevance.** Lower the TTL one old-TTL before a migration, cut over, drain, raise TTL again.
**Learned.** Short TTL = fast, even cutover but more DNS load; long TTL = cheap but slow and uneven.

## 6. Extension C — Service isolation (backend firewall) ✅
**Objective.** Only the edge (Mac 2) may reach backend ports 3001/3002; a client Mac may not; HTTPS keeps working;
rules are rolled back afterwards.
**Configuration** (`configs/mac3-firewall/pf-cn-project.conf`), loaded into its own PF anchor so the main ruleset is never
modified:
```
pass in quick on en0 inet proto tcp from 10.7.19.93 to 10.7.31.224 port { 3001, 3002 } flags S/SA keep state
block in quick on en0 inet proto tcp from any to 10.7.31.224 port { 3001, 3002 }
```
`sudo pfctl -a com.apple/250.CNProject -f pf-cn-project.conf; sudo pfctl -E` (token kept) → rollback
`sudo pfctl -a com.apple/250.CNProject -F all; sudo pfctl -X <token>`. Baseline saved before:
`configs/mac3-firewall/pf-rules-before-project.txt` (Apple default anchors only; PF disabled).
**Observed (PF on 23:13:27 → off 23:14:57):**
- Mac 1 → 10.7.31.224:3001/3002 direct: **BLOCKED** (timeouts — `block drop` silently discards SYNs).
- Through the Mac 2 edge: HTTP 200, `X-Cache-Status: MISS`, `X-Backend` alternating A/B → **nginx on Mac 2 reached both
  backends** while PF was on (MISS = fresh fetch from the backend, not cache).
- Through the standby edge on Mac 3: HTTP 200 — it uses 127.0.0.1 (lo0), which the `on en0` rules don't match.
- One **502 at 23:13:33** on the Mac 2 edge, at the instant PF was enabled. Probable cause: a Mac 2→backend connection
  that was already open had no PF state entry; the pass rule only creates state on a new SYN (`flags S/SA`), so its later
  packets hit the block rule. All following requests were 200. (Reported as observed.)
- Rollback: anchor flushed, PF disabled, main rules identical to the baseline file; access OPEN again from 23:14:57.
**Evidence.** `C1_pf_firewall_rules.png`, `C2_C3_C4_edge_allowed_client_blocked_https_ok.png`, `C5_pf_rollback_to_baseline.png`, `C6_mac2_backend_access_post_rollback.txt` (Mac 2 → backends 100/100 HTTP 200 after rollback),
`CD_monitor_mac1_20261123_231036.txt` (Mac 1), `CD_mac3_timeline_231150.txt` (Mac 3).
**Learned.** PF is first-match with `quick`; stateful `keep state` lets replies through; enabling a stateful firewall can
break connections that started before it; firewall *drops* look like timeouts, not refusals.

## 7. Extension D — High-availability backend failover ✅
**Objective.** nginx detects an unavailable backend and routes only to the healthy one; balancing resumes after recovery;
identify the remaining single point of failure.
**Configuration** (`configs/mac2-main-edge/nginx.conf`): `server … max_fails=1 fail_timeout=5s;` for both upstreams,
`proxy_next_upstream error timeout http_502 http_503 http_504; proxy_next_upstream_tries 2;`.
**Method.** Mac 1 sent one HTTPS request every ~1–2 s through each edge with a unique URL (bypasses the proxy cache;
`scripts/cd_monitor.sh`); Riya's session stopped/restarted backends with a timed script.
**Observed (run 2, through the main edge on Mac 2):**
| Time | Event (Mac 3) | Mac 2 edge result |
|---|---|---|
| ≤ 23:12:37 | both up | 200, A,B,A,B (MISS) |
| **23:12:38** | **Backend A stopped** (pid 43604) | **200 every request, all Backend B** — no client-visible error |
| **23:13:08** | **Backend A restarted** (pid 44213) | from 23:13:15: A,B,A,B again |
Run 1 (23:08–23:09, standby edge): A stopped → only B; **both stopped → 502 Bad Gateway** on both edges; restarted → A/B.
**Evidence.** `D1_D2_backend_A_stopped_B_serving.png`, `D3_D4_backend_A_restarted_lb_restored.png`,
`evidence/phase1/07_failure_demos/Fail3_Fail4_one_then_both_backends_stopped.png`, `D_run1_*.txt`, C/D monitor log.
**Lesson from a mistake.** Our first monitor reused one URL (zsh `$RANDOM` repeats inside `$(…)`), so Mac 2's proxy cache
(valid 60 s) kept answering — the cache *masked* the outage for up to 60 s. Fixed with counter-based unique URLs.
**Single point of failure.** The edge (and Mac 3, which hosts both backends, backup DNS and standby edge). Removing it
needs two *active* edges behind a floating IP (VRRP/keepalived), anycast, or health-checked DNS failover, plus backends on
separate machines.

## 8. Extension E — Controlled edge migration (DNS cutover) ✅
**Objective.** Move `app.team1.test` from the original edge (Mac 2) to the standby edge (Mac 3) using DNS; show cached
clients still reach the old edge until TTL expiry while new lookups reach the standby.
**Configuration.** Standby nginx `configs/mac3-standby-edge/nginx.conf` (same cert, upstreams 127.0.0.1:3001/3002).
`scripts/edge_migration_demo.sh` flips the primary record (`launchctl kickstart -k system/sh.brew.dnsmasq`), backup copy
`dnsmasq.conf.bak-extE-*`.
**Observed (23:02:19 run).** Both edges healthy (200, cert verified). 23:02:57 existing client caches `app → 10.7.19.93`.
**23:03:05 cutover** to 10.7.31.224. For 21 s every *new* lookup connected to **10.7.31.224 (Mac 3)** while the *existing*
client kept connecting to **10.7.19.93 (Mac 2)** — all HTTPS 200. At +26 s (TTL expiry) the existing client re-resolved and
moved to Mac 3. Cache log: only 2 real lookups, everything else `cached`. No request failed.
**Evidence.** `E1…E5*.png`, `E_migration_run_20261123_230219.txt`, `E_existing_client_cache_*.log`.
**Explanation.** Clients move individually when their cached answer expires, so the old edge must keep serving ≥ 1 TTL.
**Learned.** Zero-downtime cutover = identical edges + short TTL set in advance + keep the old edge until TTL has passed.

## 9. Extension F — Troubleshooting methodology ✅
`docs/Troubleshooting_Checklist.md` and `scripts/diagnose.sh` (read-only; DNS → IP → TCP → TLS → HTTP → LB; names the failing
layer, distinguishes *refused* vs *timeout*, 502 vs 504).
**Real incident diagnosed (23 Nov 22:17–22:41).** TLS to Mac 2 succeeded but no HTTP reply. DNS ✓ → ping Mac 3 ✓ → TCP to
Mac 3 :53/:3001/:3002/:8443 **timed out** from Mac 1 *and* Mac 2 → Mac 2 nginx log `upstream timed out (60) while connecting
to upstream` → on Mac 3 every service listened on `*:port` and worked locally → **macOS Application Firewall** dropping inbound
connections to unsigned Homebrew binaries. PF ruled out (Apple defaults only). Fix: allow `node`, `nginx`, `dnsmasq`
(firewall kept ON). Verified: all layers PASS.
**Evidence.** `evidence/audit_2026-11-23/*` (before), `F2_after_fix_mac3_firewall.txt` (after), `F3_diagnose_script_healthy_baseline.png`.

## 10. Phase 1 gap closure
| Requirement | Evidence (`evidence/phase1/`) |
|---|---|
| Task A: IP/MAC/gateway of every Mac + ping all pairs | `01_lan_interfaces_ping/` |
| Task B: private DNS; public DNS → NXDOMAIN; **all three Macs resolve via the team DNS** (primary + backup) | `02_dns/` (incl. `TaskB_mac1/2/3_client_*`) |
| Task E: HTTPS by name **without `-k` on all three Macs** (mkcert CA trusted) | `02_dns/TaskB_mac*_client_resolves_via_team_dns.png` |
| Task D: round-robin load balancing | `04_load_balancing/` |
| Task E: HTTP → HTTPS redirect | `05_https_redirect/` |
| Task F: Cache-Control, MISS → HIT → **304 Not Modified** | `06_http_caching/TaskF_cache_miss_hit_304.png` |
| Task G: saved capture DNS → TCP 3-way → TLS 1.3 → encrypted data | `03_tcp_tls_packet_capture/` (`.pcapng`, decoded text, screenshots) |
| Failure demos 1–5 | `07_failure_demos/` |

TLS 1.3 note: the capture shows ClientHello (SNI `app.team1.test`) → ServerHello + ChangeCipherSpec → "Application Data".
In TLS 1.3 the server Certificate and Finished are **encrypted**, so Wireshark cannot show the certificate in clear text.

## 11. Conclusion and learning outcomes
The platform now survives the loss of a DNS server, a backend, and (with a controlled DNS cutover) an edge, and the
backend tier can be isolated so only the edge reaches it. The most valuable lessons came from things that went wrong:
a firewall that turned a healthy service into silent timeouts, a backup DNS that quietly disagreed with the primary, and
a proxy cache that hid an outage from our own monitor. Each was found by testing one layer at a time and trusting
measurements over assumptions — DNS gives an address, TCP proves something listens, TLS proves identity, HTTP proves the
application, and caches and TTLs decide *when* clients notice a change.
