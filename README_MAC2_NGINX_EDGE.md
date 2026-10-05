# Mac 2 — nginx + HTTPS + Load Balancer + Cache Commands

**Role:** Edge server / nginx / HTTPS / load balancing / caching  
**IP:** `10.7.19.2`  
**Interface:** `en0`  
**HTTP:** `8080`  
**HTTPS:** `8443`

---

## 1. Check Mac 2 IP

```bash
ipconfig getifaddr en0
```

Expected:

```text
10.7.19.2
```

---

## 2. Check nginx

```bash
brew services list | grep nginx
```

Check nginx process:

```bash
ps aux | grep nginx
```

---

## 3. nginx Configuration Location

```text
/opt/homebrew/etc/nginx/nginx.conf
```

Open:

```bash
nano /opt/homebrew/etc/nginx/nginx.conf
```

---

## 4. Required nginx Upstream

```nginx
upstream backend_servers {
    server 10.7.17.41:3001;
    server 10.7.17.41:3002;
}
```

---

## 5. HTTPS Server

```nginx
server {
    listen 8443 ssl;
    server_name app.team1.test;

    ssl_certificate /Users/avneet/cn-project/tls/app.team1.test.pem;
    ssl_certificate_key /Users/avneet/cn-project/tls/app.team1.test-key.pem;

    location / {
        proxy_pass http://backend_servers;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

## 6. HTTP → HTTPS Redirect

```nginx
server {
    listen 8080;
    server_name app.team1.test;

    return 301 https://app.team1.test:8443$request_uri;
}
```

---

## 7. Cache Configuration

```nginx
proxy_cache_path /opt/homebrew/var/nginx/cache
                 levels=1:2
                 keys_zone=api_cache:10m
                 max_size=100m
                 inactive=60s
                 use_temp_path=off;
```

Inside the HTTPS location:

```nginx
proxy_cache api_cache;
proxy_cache_valid 200 60s;
add_header X-Cache-Status $upstream_cache_status;
proxy_cache_revalidate on;
```

---

## 8. Test nginx Configuration

```bash
sudo nginx -t
```

Expected:

```text
syntax is ok
test is successful
```

---

## 9. Reload nginx

After configuration changes:

```bash
sudo nginx -s reload
```

---

## 10. Test HTTP Redirect

```bash
curl -v http://app.team1.test:8080/
```

Expected:

```text
HTTP/1.1 301 Moved Permanently
Location: https://app.team1.test:8443/
```

---

## 11. Test HTTPS

```bash
curl -v https://app.team1.test:8443/api/status
```

Expected:

```text
SSL connection using TLSv1.3
SSL certificate verify ok.
HTTP/1.1 200 OK
```

---

## 12. Test Load Balancing

Use unique query parameters so each request has a different cache key:

```bash
for i in {1..6}; do
  curl -s -D - "https://app.team1.test:8443/api/status?test=$i" -o -
  echo
done
```

Expected to see both:

```text
X-Backend: A
X-Backend: B
```

Example:

```text
X-Backend: A
X-Backend: B
X-Backend: A
X-Backend: B
X-Backend: A
X-Backend: B
```

---

## 13. Test Cache Headers

```bash
curl -sI https://app.team1.test:8443/api/status
```

Expected:

```text
Cache-Control: max-age=60
ETag: "backend-a-v1"
X-Backend: A
X-Cache-Status: MISS
```

Run again:

```bash
curl -sI https://app.team1.test:8443/api/status
```

Expected:

```text
X-Cache-Status: HIT
```

---

## 14. Test Both Backends Directly

Backend A:

```bash
curl -v --max-time 5 http://10.7.17.41:3001/api/status
```

Backend B:

```bash
curl -v --max-time 5 http://10.7.17.41:3002/api/status
```

Expected:

```json
{"backend":"A","status":"ok"}
```

and:

```json
{"backend":"B","status":"ok"}
```

---

# D3 — Failure Demonstration

## BEFORE — Both Backends

```bash
for i in {1..6}; do
  curl -s -D - "https://app.team1.test:8443/api/status?before=$i" -o -
  echo
done
```

Show:

```text
X-Backend: A
X-Backend: B
```

---

## AFTER — Backend B Stopped

On Mac 3, stop Backend B.

Then run on Mac 2:

```bash
for i in {1..6}; do
  curl -s -D - "https://app.team1.test:8443/api/status?after=$i" -o -
  echo
done
```

Expected:

```text
X-Backend: A
X-Backend: A
X-Backend: A
X-Backend: A
X-Backend: A
X-Backend: A
```

This demonstrates that nginx continues serving traffic through Backend A.

---

## Restore Test

After restarting Backend B on Mac 3:

```bash
for i in {1..6}; do
  curl -s -D - "https://app.team1.test:8443/api/status?restored=$i" -o -
  echo
done
```

Both `X-Backend: A` and `X-Backend: B` should appear again.

---



