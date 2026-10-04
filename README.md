# Private Network Service Platform

## Computer Networks — Phase 1

A team-based private LAN networking project demonstrating how multiple machines communicate through a private DNS service, reverse proxy/load balancer, HTTPS/TLS, backend services, HTTP caching, and network-level packet analysis using Wireshark.

---

## 📌 Project Overview

This project implements a complete private-network service platform running entirely on a local LAN.

The system demonstrates the complete request flow:

```text
                         PRIVATE LAN
                              │
                              │
                    ┌─────────▼─────────┐
                    │      Mac 1        │
                    │ DNS + Client      │
                    │                   │
                    │ dnsmasq           │
                    │ 10.7.10.246       │
                    └─────────┬─────────┘
                              │
                     app.team1.test
                              │
                              ▼
                    ┌───────────────────┐
                    │      Mac 2        │
                    │ nginx Edge Server │
                    │                   │
                    │ HTTPS :8443       │
                    │ Load Balancer     │
                    │ HTTP Cache        │
                    │ 10.7.19.2         │
                    └─────────┬─────────┘
                              │
                    ┌─────────┴─────────┐
                    │                   │
                    ▼                   ▼
          ┌─────────────────┐  ┌─────────────────┐
          │    Backend A    │  │    Backend B    │
          │                 │  │                 │
          │ Express         │  │ Express         │
          │ Port 3001       │  │ Port 3002       │
          │ X-Backend: A    │  │ X-Backend: B    │
          └─────────────────┘  └─────────────────┘
```

The project is designed to demonstrate:

- Private LAN communication
- Private DNS resolution
- REST backend services
- nginx reverse proxy
- Load balancing
- HTTPS/TLS
- HTTP caching
- DNS/TCP/TLS packet analysis
- Failure demonstration and recovery

---

## 👥 Team Structure

This implementation uses a 3-machine architecture.

| Machine | Role | IP Address | Services |
|---|---|---|---|
| Mac 1 | DNS + Client | `10.7.10.246` | dnsmasq, testing |
| Mac 2 | Edge Server | `10.7.19.2` | nginx, HTTPS, load balancing, caching |
| Mac 3 | Backend Server | `10.7.17.41` | Backend A + Backend B |

### Team Responsibilities

#### Mac 1 — DNS + Client

Responsibilities:

- Configure private DNS using dnsmasq
- Resolve `app.team1.test`
- Resolve `api.team1.test`
- Perform client-side testing
- Capture DNS traffic using Wireshark

#### Mac 2 — nginx / Edge

Responsibilities:

- nginx reverse proxy
- HTTPS/TLS termination
- Load balancing
- HTTP caching
- SSL certificate configuration
- Verify requests from clients

#### Mac 3 — Backend

Responsibilities:

- Backend A on port `3001`
- Backend B on port `3002`
- Return JSON responses
- Provide identifying headers
- Demonstrate backend failure and recovery

---

## 🏗️ Architecture

The request flow is:

```text
Client
  │
  │ DNS Query
  ▼
dnsmasq
10.7.10.246:53
  │
  │ app.team1.test → 10.7.19.2
  ▼
nginx
10.7.19.2:8443
  │
  │ HTTPS / Reverse Proxy
  ▼
Load Balancer
  │
  ├───────────────┐
  ▼               ▼
Backend A       Backend B
:3001           :3002
```

The client never directly accesses the backend services during normal operation.

Instead:

```text
https://app.team1.test:8443/api/status
```

is received by nginx and proxied to one of the backend services.

---

## 🌐 Network Configuration

### IP Address Allocation

#### Mac 1

- **IP:** `10.7.10.246`
- **Role:** DNS + Client
- **Interface:** `en0`
- **DNS Service:** dnsmasq
- **Port:** `53`

#### Mac 2

- **IP:** `10.7.19.2`
- **Role:** nginx / Edge Server
- **Interface:** `en0`
- **HTTP:** `8080`
- **HTTPS:** `8443`

#### Mac 3

- **IP:** `10.7.17.41`
- **Role:** Backend Server
- **Interface:** `en0`
- **Backend A:** `3001`
- **Backend B:** `3002`

> **Note:** These IP addresses are specific to the LAN used during the project demonstration. They may change if DHCP assigns different addresses.

---

## 🔎 Private DNS

The project uses dnsmasq to provide private DNS resolution.

The private hostname:

```text
app.team1.test
```

resolves to:

```text
10.7.19.2
```

Similarly:

```text
api.team1.test
```

resolves to:

```text
10.7.19.2
```

### dnsmasq Configuration

Relevant configuration:

```conf
address=/app.team1.test/10.7.19.2
address=/api.team1.test/10.7.19.2

listen-address=0.0.0.0
interface=en0
```

### Explanation

#### `address=`

Creates the private DNS records.

#### `listen-address=0.0.0.0`

Allows dnsmasq to accept DNS requests from other machines on the LAN.

#### `interface=en0`

Binds the DNS service to the LAN interface.

---

## 🧪 DNS Testing

From a client machine:

```bash
dig app.team1.test
```

Expected result:

```text
;; ANSWER SECTION:

app.team1.test.    IN    A    10.7.19.2
```

The DNS server should be the private DNS server:

```text
SERVER: 10.7.10.246#53
```

### Verify the Private Domain Is Not Public

Run:

```bash
dig @8.8.8.8 app.team1.test
```

Expected result:

```text
status: NXDOMAIN
```

This demonstrates that `app.team1.test` is a private DNS record and is not publicly resolvable through Google's public DNS.

---

## 🚀 Backend Services

Two backend services are running on Mac 3.

### Backend A

Address:

```text
http://10.7.17.41:3001/api/status
```

Response:

```json
{
  "backend": "A",
  "status": "ok"
}
```

Headers include:

```text
X-Backend: A
Cache-Control: max-age=60
ETag: "backend-a-v1"
```

### Backend B

Address:

```text
http://10.7.17.41:3002/api/status
```

Response:

```json
{
  "backend": "B",
  "status": "ok"
}
```

Headers include:

```text
X-Backend: B
Cache-Control: max-age=60
ETag: "backend-b-v1"
```

---

## 🧩 Backend API

Both services expose:

```http
GET /api/status
```

Example Backend A response:

```json
{
  "backend": "A",
  "status": "ok"
}
```

Example Backend B response:

```json
{
  "backend": "B",
  "status": "ok"
}
```

The `X-Backend` header makes it possible to identify which backend served each request.

---

## ⚙️ nginx Configuration

nginx runs on Mac 2.

Configuration file:

```text
/opt/homebrew/etc/nginx/nginx.conf
```

The configuration contains:

```nginx
worker_processes 1;

events {
    worker_connections 1024;
}

http {

    include mime.types;

    default_type application/octet-stream;

    proxy_cache_path /opt/homebrew/var/nginx/cache
                     levels=1:2
                     keys_zone=api_cache:10m
                     max_size=100m
                     inactive=60s
                     use_temp_path=off;

    upstream backend_servers {
        server 10.7.17.41:3001;
        server 10.7.17.41:3002;
    }

    server {
        listen 8080;

        server_name app.team1.test;

        return 301 https://app.team1.test:8443$request_uri;
    }

    server {

        listen 8443 ssl;

        server_name app.team1.test;

        ssl_certificate /Users/avneet/cn-project/tls/app.team1.test.pem;

        ssl_certificate_key /Users/avneet/cn-project/tls/app.team1.test-key.pem;

        location / {

            proxy_cache api_cache;

            proxy_cache_valid 200 60s;

            add_header X-Cache-Status $upstream_cache_status;

            proxy_cache_revalidate on;

            proxy_pass http://backend_servers;

            proxy_set_header Host $host;

            proxy_set_header X-Real-IP $remote_addr;

            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
```

---

## 🔀 Load Balancing

The nginx upstream block contains both backend services:

```nginx
upstream backend_servers {
    server 10.7.17.41:3001;
    server 10.7.17.41:3002;
}
```

nginx distributes requests between these services.

The proxy forwards requests using:

```nginx
proxy_pass http://backend_servers;
```

### 🧪 Load Balancing Test

Run:

```bash
for i in {1..6}; do
    curl -s -D - "https://app.team1.test:8443/api/status?test=$i" -o -
    echo
done
```

Example output:

```text
X-Backend: A

{"backend":"A","status":"ok"}

X-Backend: B

{"backend":"B","status":"ok"}

X-Backend: A

{"backend":"A","status":"ok"}

X-Backend: B

{"backend":"B","status":"ok"}

X-Backend: A

{"backend":"A","status":"ok"}

X-Backend: B

{"backend":"B","status":"ok"}
```

The unique query parameters ensure that each request has a different cache key during the load-balancing test.

---

## 🔐 HTTPS / TLS

HTTPS is terminated by nginx.

The service is available at:

```text
https://app.team1.test:8443
```

The certificate was generated using mkcert.

Certificate:

```text
/Users/avneet/cn-project/tls/app.team1.test.pem
```

Private key:

```text
/Users/avneet/cn-project/tls/app.team1.test-key.pem
```

nginx configuration:

```nginx
listen 8443 ssl;

ssl_certificate /Users/avneet/cn-project/tls/app.team1.test.pem;

ssl_certificate_key /Users/avneet/cn-project/tls/app.team1.test-key.pem;
```

---

## 🔄 HTTP → HTTPS Redirect

HTTP runs on port `8080`.

Requests to HTTP are redirected to HTTPS:

```nginx
server {
    listen 8080;

    server_name app.team1.test;

    return 301 https://app.team1.test:8443$request_uri;
}
```

Test:

```bash
curl -v http://app.team1.test:8080/
```

Expected:

```text
HTTP/1.1 301 Moved Permanently
Location: https://app.team1.test:8443/
```

---

## 🔒 TLS Verification

Test HTTPS:

```bash
curl -v https://app.team1.test:8443/api/status
```

A successful connection shows:

```text
SSL connection using TLSv1.3
```

and:

```text
SSL certificate verify ok.
```

The certificate hostname matches:

```text
app.team1.test
```

---

## 🗃️ HTTP Caching

nginx uses its built-in proxy cache.

Configuration:

```nginx
proxy_cache_path /opt/homebrew/var/nginx/cache
                 levels=1:2
                 keys_zone=api_cache:10m
                 max_size=100m
                 inactive=60s
                 use_temp_path=off;
```

Caching is enabled using:

```nginx
proxy_cache api_cache;

proxy_cache_valid 200 60s;
```

The cache status is exposed through:

```nginx
add_header X-Cache-Status $upstream_cache_status;
```

---

## 🧾 Cache Headers

The backend returns:

```text
Cache-Control: max-age=60
```

This tells the client that the response can be treated as fresh for 60 seconds.

The backend also provides an ETag:

```text
ETag: "backend-a-v1"
```

or:

```text
ETag: "backend-b-v1"
```

---

## 🧪 Cache Testing

Run:

```bash
curl -sI https://app.team1.test:8443/api/status
```

Example:

```text
HTTP/1.1 200 OK
Server: nginx/1.31.6
Date: Sun, 04 Oct 2026 10:08:13 GMT
Content-Type: application/json; charset=utf-8
Content-Length: 29
Connection: keep-alive
X-Powered-By: Express
X-Backend: A
Cache-Control: max-age=60
ETag: "backend-a-v1"
X-Cache-Status: MISS
```

A subsequent request may show:

```text
X-Cache-Status: HIT
```

### Cache MISS

```text
X-Cache-Status: MISS
```

means nginx did not find a valid cached response and contacted the backend.

### Cache HIT

```text
X-Cache-Status: HIT
```

means nginx served the response from its cache without needing to obtain a fresh response from the backend.

---

## 🧠 ETag and 304 Not Modified

The backend sends an ETag such as:

```text
ETag: "backend-a-v1"
```

The client can later send:

```text
If-None-Match: "backend-a-v1"
```

If the resource has not changed, the server can respond:

```text
304 Not Modified
```

This tells the client that its cached copy is still valid, so the server does not need to send the complete response body again.

---

## 📡 Wireshark Analysis

Wireshark was used to observe the network-level communication.

The project captures:

- DNS resolution
- TCP 3-way handshake
- TLS handshake
- Encrypted application data

### 1. DNS Packet Capture

Wireshark filter:

```text
dns && dns.qry.name == "app.team1.test"
```

The capture demonstrates:

```text
Client
10.7.19.2
      ↓
DNS Server
10.7.10.246
```

The DNS response contains:

```text
app.team1.test → 10.7.19.2
```

This demonstrates private hostname resolution.

### 2. TCP 3-Way Handshake

Wireshark filter:

```text
tcp.flags.syn==1
```

Observed connection:

```text
Client:
10.7.10.246:52285

Server:
10.7.19.2:8443
```

Sequence:

```text
SYN
10.7.10.246:52285
        ↓
10.7.19.2:8443

SYN-ACK
10.7.19.2:8443
        ↓
10.7.10.246:52285

ACK
10.7.10.246:52285
        ↓
10.7.19.2:8443
```

The handshake establishes a reliable, ordered, connection-oriented TCP channel before TLS communication begins.

### 3. TLS Handshake

Wireshark filter:

```text
tls
```

The TLS connection uses:

```text
TLSv1.3
```

The client sends a:

```text
Client Hello
```

to:

```text
10.7.19.2:8443
```

The server responds with its TLS handshake and certificate.

After the handshake, packets appear as:

```text
Application Data
```

The HTTP request and response are encrypted inside TLS records.

Therefore, Wireshark can show:

- Source IP
- Destination IP
- TCP ports
- TLS version
- Packet lengths
- TLS record information

but the actual HTTP headers and response body are not visible as plaintext.

---

## 🛑 Failure Demonstration

### Option A — Backend Failure

The project demonstrates what happens when one backend becomes unavailable.

Architecture:

```text
                nginx
                  │
        ┌─────────┴─────────┐
        │                   │
   Backend A           Backend B
     :3001                 :3002
```

### Before Failure

Both backends are running.

Requests produce:

```text
X-Backend: A
X-Backend: B
X-Backend: A
X-Backend: B
```

This confirms that nginx is successfully distributing traffic.

### Failure Action

Backend A is stopped.

Backend A:

```text
10.7.17.41:3001
```

is no longer available.

Backend B remains active:

```text
10.7.17.41:3002
```

### After Failure

nginx continues to serve requests through Backend B.

Expected responses:

```text
X-Backend: B
X-Backend: B
X-Backend: B
X-Backend: B
```

This demonstrates that the remaining backend continues serving traffic when Backend A is unavailable.

### Restore

Backend A is started again.

Verify:

```bash
curl http://localhost:3001/api/status
```

Expected:

```json
{
  "backend": "A",
  "status": "ok"
}
```

The load-balanced system is then operational again.

---

## 🧪 Complete Testing Checklist

### DNS

```bash
dig app.team1.test
```

Expected:

```text
10.7.19.2
```

### Public DNS Isolation

```bash
dig @8.8.8.8 app.team1.test
```

Expected:

```text
NXDOMAIN
```

### Backend A

```bash
curl http://10.7.17.41:3001/api/status
```

Expected:

```json
{"backend":"A","status":"ok"}
```

### Backend B

```bash
curl http://10.7.17.41:3002/api/status
```

Expected:

```json
{"backend":"B","status":"ok"}
```

### HTTP Redirect

```bash
curl -v http://app.team1.test:8080/
```

Expected:

```text
301 Moved Permanently
```

### HTTPS

```bash
curl -v https://app.team1.test:8443/api/status
```

Expected:

```text
TLSv1.3
HTTP/1.1 200 OK
```

### Load Balancing

```bash
for i in {1..6}; do
    curl -s -D - "https://app.team1.test:8443/api/status?test=$i" -o -
    echo
done
```

Expected:

```text
X-Backend: A
X-Backend: B
```

### Cache

```bash
curl -sI https://app.team1.test:8443/api/status
```

Expected headers include:

```text
Cache-Control: max-age=60
ETag: "backend-a-v1"
X-Backend: A
X-Cache-Status: MISS
```

Repeat the request:

```bash
curl -sI https://app.team1.test:8443/api/status
```

Expected:

```text
X-Cache-Status: HIT
```

---

## 🔧 nginx Management Commands

### Test nginx Configuration

```bash
sudo nginx -t
```

Expected:

```text
syntax is ok
test is successful
```

### Reload nginx

```bash
sudo nginx -s reload
```

### Check nginx Process

```bash
ps aux | grep nginx
```

---

## 🔐 Certificate Management

The project uses mkcert for a local trusted development certificate.

Example:

```bash
mkcert app.team1.test
```

This generates a certificate and private key.

The certificate must match:

```text
app.team1.test
```

The private key must **never** be committed to GitHub.

---

## 📁 Suggested Project Structure

```text
CN-Project/
│
├── backend/
│   ├── backend-a/
│   │   ├── package.json
│   │   └── ...
│   │
│   └── backend-b/
│       ├── package.json
│       └── ...
│
├── nginx/
│   └── nginx.conf
│
├── dns/
│   └── dnsmasq.conf
│
├── tls/
│   └── README.md
│
├── wireshark/
│   ├── dns/
│   ├── tcp/
│   └── tls/
│
├── screenshots/
│   ├── dns-resolution.png
│   ├── tcp-handshake.png
│   ├── tls-handshake.png
│   ├── load-balancing.png
│   └── caching.png
│
└── README.md
```

Do not commit private keys, passwords, local CA private keys, or other secrets.

---

## 🔒 Security Considerations

The following files should not be committed:

```text
*.key
*.pem
rootCA-key.pem
.env
.env.local
```

Add sensitive files to `.gitignore`.

Example:

```gitignore
# TLS private keys
*.key
*-key.pem
rootCA-key.pem

# Environment variables
.env
.env.local

# OS files
.DS_Store

# Logs
*.log

# Node dependencies
node_modules/
```

The public certificate may be included if required for demonstration, but private keys should remain local.

---

## 🧰 Technologies Used

| Technology | Purpose |
|---|---|
| macOS | Host operating system |
| LAN / Wi-Fi | Private network |
| dnsmasq | Private DNS |
| nginx | Reverse proxy / edge server |
| Express.js | Backend REST services |
| Node.js | Backend runtime |
| mkcert | Local TLS certificates |
| HTTPS | Secure application communication |
| TLS 1.3 | Encryption |
| Wireshark | Network packet analysis |
| curl | Testing |
| dig | DNS testing |

---

## 📊 Phase 1 Demonstration Flow

The complete Phase 1 request flow is:

### 1. Client enters

```text
https://app.team1.test:8443/api/status
```

```text
             │
             ▼
```

### 2. DNS resolution

```text
app.team1.test
       ↓
10.7.19.2
```

```text
             │
             ▼
```

### 3. TCP connection

```text
SYN
SYN-ACK
ACK
```

```text
             │
             ▼
```

### 4. TLS 1.3 handshake

```text
ClientHello
ServerHello
Certificate
Encrypted Application Data
```

```text
             │
             ▼
```

### 5. nginx receives HTTPS request

```text
             │
             ▼
```

### 6. nginx checks cache

```text
       ┌───────────────┐
       │ Cache HIT?    │
       └───────┬───────┘
               │
        ┌──────┴──────┐
        │             │
       YES            NO
        │             │
        ▼             ▼
   Return cache    Forward request
                       │
                       ▼
                 Backend A/B
                       │
                       ▼
                 Store response
                       │
                       ▼
                  Return response
```

---

## 📌 Phase 1 Summary

This project demonstrates how a private LAN can provide a complete service platform using:

**Private DNS → TCP → TLS → nginx → Load Balancing → Express Backends → HTTP Caching → Wireshark Analysis**

The implementation also demonstrates backend failure, recovery, and the importance of keeping private cryptographic keys and environment secrets out of source control.
