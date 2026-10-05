# Mac 3 — Backend A + Backend B Commands

**Role:** Backend server  
**IP:** `10.7.17.41`  
**Interface:** `en0`

**Backend A:** `3001`  
**Backend B:** `3002`

---

# 1. Check Mac 3 IP

```bash
ipconfig getifaddr en0
```

Expected:

```text
10.7.17.41
```

---

# 2. Check Node.js and npm

```bash
node -v
npm -v
```

---

# 3. Start Backend A

Backend A must listen on:

```text
10.7.17.41:3001
```

From the Backend A project directory, run the project's normal start command.

If the project uses npm:

```bash
npm start
```

Expected API:

```text
http://10.7.17.41:3001/api/status
```

---

# 4. Start Backend B

Backend B must listen on:

```text
10.7.17.41:3002
```

From the Backend B project directory, run:

```bash
npm start
```

Expected API:

```text
http://10.7.17.41:3002/api/status
```

> If Backend A and Backend B are separate projects, run each in its own terminal. Do not run both in the same terminal if the first process blocks the shell.

---

# 5. Test Backend A

```bash
curl -v --max-time 5 http://10.7.17.41:3001/api/status
```

Expected:

```text
HTTP/1.1 200 OK
X-Backend: A
Cache-Control: max-age=60
ETag: "backend-a-v1"
```

Response:

```json
{"backend":"A","status":"ok"}
```

---

# 6. Test Backend B

```bash
curl -v --max-time 5 http://10.7.17.41:3002/api/status
```

Expected:

```text
HTTP/1.1 200 OK
X-Backend: B
Cache-Control: max-age=60
ETag: "backend-b-v1"
```

Response:

```json
{"backend":"B","status":"ok"}
```

---

# 7. Check Listening Ports

```bash
lsof -nP -iTCP:3001 -sTCP:LISTEN
```

and:

```bash
lsof -nP -iTCP:3002 -sTCP:LISTEN
```

Both ports should have a listening process.

---

# 8. Test From Mac 2

From Mac 2:

```bash
curl http://10.7.17.41:3001/api/status
```

and:

```bash
curl http://10.7.17.41:3002/api/status
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

# 9. Backend Headers

Backend A should return:

```text
X-Backend: A
Cache-Control: max-age=60
ETag: "backend-a-v1"
```

Backend B should return:

```text
X-Backend: B
Cache-Control: max-age=60
ETag: "backend-b-v1"
```

These headers allow nginx and the client to demonstrate backend identity and HTTP caching behavior.

---

# 10. D3 Failure Demonstration — Stop Backend B

## BEFORE

Before stopping anything, verify both:

```bash
curl http://localhost:3001/api/status
```

and:

```bash
curl http://localhost:3002/api/status
```

Both should return HTTP 200.

---

## STOP BACKEND B

Stop only the process running on port `3002`.

If Backend B is running in the current terminal:

```text
Ctrl + C
```

Do NOT stop Backend A.

---

# 11. Verify Backend B Is Down

```bash
curl --max-time 5 http://localhost:3002/api/status
```

Expected:

```text
curl: (7) Failed to connect to localhost port 3002
```

or another connection-failure message.

---

# 12. Verify Backend A Is Still Working

```bash
curl http://localhost:3001/api/status
```

Expected:

```json
{"backend":"A","status":"ok"}
```

---

# 13. Test nginx After Backend B Failure

Go to Mac 2 and run:

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

This proves that Backend A continues serving requests after Backend B is stopped.

---

# 14. RESTORE BACKEND B

Return to the Backend B project directory.

Start it again using the normal project command:

```bash
npm start
```

---

# 15. Verify Backend B Has Returned

```bash
curl http://localhost:3002/api/status
```

Expected:

```json
{"backend":"B","status":"ok"}
```

---

# 16. Final Verification

From Mac 2:

```bash
for i in {1..6}; do
  curl -s -D - "https://app.team1.test:8443/api/status?restored=$i" -o -
  echo
done
```

You should again see both:

```text
X-Backend: A
X-Backend: B
```

---

# 17. Backend Troubleshooting

Check port 3001:

```bash
lsof -nP -iTCP:3001 -sTCP:LISTEN
```

Check port 3002:

```bash
lsof -nP -iTCP:3002 -sTCP:LISTEN
```

Check local API A:

```bash
curl http://localhost:3001/api/status
```

Check local API B:

```bash
curl http://localhost:3002/api/status
```

Check Mac 2 connectivity:

```bash
ping -c 4 10.7.19.2
```

---

# 18. Important Demo Rule

During the normal Phase 1 demonstration:

```text
Backend A = RUNNING
Backend B = RUNNING
```

Only stop Backend B during the dedicated D3 failure demonstration.

After the demonstration:

```text
Backend A = RUNNING
Backend B = RUNNING
```
