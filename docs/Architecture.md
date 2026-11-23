# Architecture Diagrams — Team Error-101 (3-Mac adaptation)

## 1. Network topology and roles (private LAN 10.7.0.0/19, gateway 10.7.0.1, Wi-Fi en0)

```mermaid
flowchart TB
    subgraph LAN["Private LAN 10.7.0.0/19 (Wi-Fi, en0)"]
        M1["<b>Mac 1 — Manpreet</b><br/>10.7.9.246<br/>Primary DNS (dnsmasq :53)<br/>Test client"]
        M2["<b>Mac 2 — Avneet</b><br/>10.7.19.93<br/>Main edge: nginx<br/>HTTPS :8443 · HTTP :8080 → 301<br/>TLS termination · LB · cache"]
        M3["<b>Mac 3 — Riya</b><br/>10.7.31.224<br/>Backend A :3001 · Backend B :3002<br/>Backup DNS (dnsmasq :53)<br/>Standby edge nginx :8443"]
    end
    M1 -- "DNS queries (UDP 53)" --> M1
    M1 -- "DNS failover (UDP 53)" --> M3
    M1 -- "HTTPS :8443" --> M2
    M1 -- "HTTPS :8443 (after migration)" --> M3
    M2 -- "HTTP :3001 / :3002 (only Mac 2 allowed — Ext C)" --> M3
```

| Machine | IP | MAC | Services | Cloud equivalent |
|---|---|---|---|---|
| Mac 1 | 10.7.9.246 | 36:b5:ac:b7:11:00 | dnsmasq (primary), client tools | Route 53 / managed DNS |
| Mac 2 | 10.7.19.93 | 2e:30:0b:a1:32:2a | nginx edge: TLS, round-robin LB, proxy cache | ALB / CDN edge |
| Mac 3 | 10.7.31.224 | 46:b2:52:34:a6:e0 | Node/Express A+B, dnsmasq (backup), standby nginx | EC2 app servers, secondary DNS, standby LB |

## 2. One request, layer by layer

```mermaid
sequenceDiagram
    participant C as Client (Mac 1)
    participant D as DNS (Mac 1 / Mac 3)
    participant E as Edge nginx (Mac 2 :8443)
    participant B as Backend A/B (Mac 3 :3001/:3002)
    C->>D: DNS query A app.team1.test (UDP 53, ephemeral src port)
    D-->>C: A 10.7.x.x, TTL 30
    C->>E: TCP SYN (ephemeral port → 8443)
    E-->>C: SYN-ACK
    C->>E: ACK
    C->>E: TLS ClientHello (SNI app.team1.test)
    E-->>C: ServerHello + encrypted Certificate/Finished (TLS 1.3)
    C->>E: Finished, then encrypted HTTP GET /api/status
    Note over E: cache lookup (MISS/HIT), pick upstream (round robin)
    E->>B: HTTP GET /api/status (plain HTTP on LAN)
    B-->>E: 200 {"backend":"A"} + X-Backend, Cache-Control, ETag
    E-->>C: encrypted HTTP 200 + X-Cache-Status
```

| Layer | Protocol | Ports in this project |
|---|---|---|
| Application | DNS, HTTP/1.1 (REST/JSON) | 53, 8080 (→301), 3001, 3002 |
| Session/presentation (TLS) | TLS 1.3 | 8443 |
| Transport | UDP (DNS), TCP (HTTP/TLS) | client ephemeral ports ↔ well-known/service ports |
| Network | IPv4 | 10.7.0.0/19 |
| Link | Wi-Fi 802.11 / Ethernet frames | en0 MAC addresses above |

## 3. Phase 2 resilience features

```mermaid
flowchart LR
    C[Client] -->|1. resolve| P[Primary DNS Mac 1]
    C -.->|1b. if primary down| S[Backup DNS Mac 3]
    C -->|2. HTTPS| E2[Edge Mac 2]
    C -.->|2b. after DNS cutover / TTL expiry| E3[Standby edge Mac 3]
    E2 -->|round robin, max_fails=1 fail_timeout=5s| A[Backend A :3001]
    E2 --> B[Backend B :3002]
    E3 --> A
    E3 --> B
    FW{{PF on Mac 3: only Mac 2 may reach :3001/:3002}} -.- A
```

## 4. Extension E — DNS-based cutover timeline (measured 2026-11-23)

```mermaid
sequenceDiagram
    participant Old as Existing client (cached)
    participant New as New client
    participant DNS as Primary DNS
    participant M2 as Mac 2 edge
    participant M3 as Mac 3 standby edge
    Old->>DNS: 23:02:57 lookup → 10.7.19.93 (TTL 30, cached)
    Old->>M2: HTTPS 200
    Note over DNS: 23:03:05 record changed → 10.7.31.224
    New->>DNS: lookup → 10.7.31.224
    New->>M3: HTTPS 200
    Old->>M2: +0…+21 s still HTTPS 200 via OLD edge (cached answer)
    Note over Old: 23:03:27 TTL expires
    Old->>DNS: 23:03:31 re-lookup → 10.7.31.224
    Old->>M3: HTTPS 200
```

## Remaining single points of failure
- **Mac 3** hosts both backends, the backup DNS and the standby edge → one machine failure takes out the application tier.
- The **edge** is still one IP per DNS record: switching edges relies on DNS + TTL (seconds to minutes), not instant.
  Removing it needs a floating/virtual IP (VRRP/keepalived), anycast, or a DNS health-checked failover (e.g. Route 53 failover records) in front of ≥2 active edges.
- Single Wi-Fi network / access point and DHCP-assigned IPs (IPs changed during the project).
