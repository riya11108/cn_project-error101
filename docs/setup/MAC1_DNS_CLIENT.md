# Mac 1 — DNS Server + Client Commands

**Role:** Private DNS server + client testing  
**IP:** `10.7.10.246`  
**Interface:** `en0`  
**DNS:** `dnsmasq` on UDP/TCP 53

---

## 1. Check Mac 1 IP

```bash
ipconfig getifaddr en0
```

Expected:

```text
10.7.10.246
```

---

## 2. Check dnsmasq

```bash
sudo brew services list | grep dnsmasq
```

If it is not running:

```bash
sudo brew services start dnsmasq
```

Check that port 53 is listening:

```bash
sudo lsof -nP -iUDP:53
```

---

## 3. dnsmasq Configuration

Relevant configuration:

```conf
address=/app.team1.test/10.7.19.2
address=/api.team1.test/10.7.19.2
listen-address=0.0.0.0
interface=en0
```

Homebrew configuration:

```text
/opt/homebrew/etc/dnsmasq.conf
```

Edit:

```bash
sudo nano /opt/homebrew/etc/dnsmasq.conf
```

Restart after changes:

```bash
sudo brew services restart dnsmasq
```

---

## 4. Test DNS Locally

```bash
dig @127.0.0.1 app.team1.test
```

Expected answer:

```text
app.team1.test.    IN    A    10.7.19.2
```

---

## 5. Test DNS Through Mac 1 From Mac 2

Run this on Mac 2:

```bash
dig @10.7.10.246 app.team1.test
```

Expected:

```text
ANSWER SECTION:
app.team1.test.    IN    A    10.7.19.2
```

Server should be:

```text
SERVER: 10.7.10.246#53
```

---

## 6. Verify the Domain Is Private

Run:

```bash
dig @8.8.8.8 app.team1.test
```

Expected:

```text
status: NXDOMAIN
```

This proves the private hostname is not publicly resolvable.

---

## 7. Wireshark — DNS Evidence

Start Wireshark on:

```text
en0
```

Use:

```text
dns && dns.qry.name == "app.team1.test"
```

Generate traffic from Mac 2:

```bash
dig @10.7.10.246 app.team1.test
```

Expected packet flow:

```text
10.7.19.2 → 10.7.10.246
DNS query: A app.team1.test

10.7.10.246 → 10.7.19.2
DNS response: app.team1.test → 10.7.19.2
```

---

## 8. Wireshark — TCP/TLS Evidence

Keep Wireshark capturing on `en0`.

From Mac 1, test the nginx server:

```bash
curl --noproxy '*' -v https://app.team1.test:8443/api/status?wireshark=1
```

TCP filter:

```text
tcp.port == 8443 && ip.addr == 10.7.19.2
```

TLS filter:

```text
tls
```

Expected TCP flow:

```text
10.7.10.246:EPHEMERAL → 10.7.19.2:8443  SYN
10.7.19.2:8443 → 10.7.10.246:EPHEMERAL  SYN-ACK
10.7.10.246:EPHEMERAL → 10.7.19.2:8443  ACK
```

Then TLS traffic begins.

---

## 9. Basic Network Tests

Test nginx:

```bash
ping -c 4 10.7.19.2
```

Test Backend Mac:

```bash
ping -c 4 10.7.17.41
```

---

## 10. Final Client Test

```bash
curl -v https://app.team1.test:8443/api/status
```

Expected:

```text
SSL connection using TLSv1.3
SSL certificate verify ok.
HTTP/1.1 200 OK
```

And:

```text
X-Backend: A
```

or:

```text
X-Backend: B
```

---

## 11. Useful Evidence Commands

DNS:

```bash
dig app.team1.test
```

Public DNS:

```bash
dig @8.8.8.8 app.team1.test
```

HTTPS:

```bash
curl -v https://app.team1.test:8443/api/status
```

HTTP redirect:

```bash
curl -v http://app.team1.test:8080/
```

Cache headers:

```bash
curl -sI https://app.team1.test:8443/api/status
```

---


