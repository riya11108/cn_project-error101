# Configuration Bundle (state at the end of Phase 2, 23 Nov 2026)

| Folder | Machine | Live path on that Mac | Apply / reload |
|---|---|---|---|
| `mac1-primary-dns/dnsmasq.conf` | Mac 1 (10.7.9.246) | `/opt/homebrew/etc/dnsmasq.conf` | `sudo brew services restart dnsmasq` |
| `mac1-primary-dns/team1-ttl.hosts` | Mac 1 | `/opt/homebrew/etc/team1-ttl.hosts` (`addn-hosts`) | edit + `sudo kill -HUP <dnsmasq pid>` (no restart) |
| `mac1-primary-dns/resolver-team1.test` | Mac 1 as client | `/etc/resolver/team1.test` | `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder` |
| `mac2-main-edge/nginx.conf` | Mac 2 (10.7.19.93) | `/opt/homebrew/etc/nginx/nginx.conf` | `sudo nginx -t && sudo nginx -s reload` |
| `mac3-backup-dns/dnsmasq.conf` | Mac 3 (10.7.31.224) | `/opt/homebrew/etc/dnsmasq.conf` | `sudo brew services restart dnsmasq` |
| `mac3-standby-edge/nginx.conf` | Mac 3 | `~/cn-project/standby-nginx/nginx.conf` | `nginx -p ~/cn-project/standby-nginx/ -c nginx.conf [-s reload]` |
| `mac3-firewall/pf-cn-project.conf` | Mac 3 | loaded into PF anchor `com.apple/250.CNProject` | see *PF commands* below |
| `mac3-firewall/pf-rules-before-project.txt` | Mac 3 | `~/pf-rules-before-project.txt` | rollback reference (= macOS defaults) |

## DNS records (identical on both servers, TTL 30 s)
| Name | Address | Meaning |
|---|---|---|
| `app.team1.test` | 10.7.31.224 | standby edge on Mac 3 (after Ext E migration). **Kept here for the demo (team decision 23 Nov).** Set to 10.7.19.93 to serve from the main edge |
| `api.team1.test` | 10.7.19.93 | main edge on Mac 2 (note: not in the certificate SAN) |
| `ttl.team1.test` | 10.7.19.93 | Ext B test record (primary only) |

## TLS certificate setup notes
- Created with **mkcert** on Mac 2: `mkcert -install` (creates and trusts a local CA) then `mkcert app.team1.test`
  → `app.team1.test.pem` (certificate) + `app.team1.test-key.pem` (private key). SAN: `DNS:app.team1.test`, valid to 2029-01-02.
- nginx (Mac 2): `ssl_certificate /Users/avneet/cn-project/tls/app.team1.test.pem; ssl_certificate_key …-key.pem;`
- The same cert/key pair was copied to Mac 3 (`~/cn-project/tls/`) for the standby edge.
- Each **client** must trust the mkcert root CA (`rootCA.pem` from `mkcert -CAROOT` on Mac 2, imported into the client's
  System keychain as trusted) — that is why `curl https://app.team1.test:8443` works **without `-k`**.
- **Private keys and the CA key are never committed** (`.gitignore`: `*-key.pem`, `*.key`, `rootCA-key.pem`).
- To also serve `api.team1.test` over HTTPS: `mkcert app.team1.test api.team1.test` and add it to `server_name`.

## PF commands (Mac 3, Extension C)
```bash
sudo pfctl -a com.apple/250.CNProject -f configs/mac3-firewall/pf-cn-project.conf   # load rules into our own anchor
sudo pfctl -E                                   # enable PF, note the Token it prints
sudo pfctl -a com.apple/250.CNProject -sr       # show active rules
# rollback
sudo pfctl -a com.apple/250.CNProject -F all    # flush our anchor only
sudo pfctl -X <token>                           # release our enable reference (or: sudo pfctl -d)
sudo pfctl -sr                                  # must equal mac3-firewall/pf-rules-before-project.txt
```

## Backend launch (Mac 3)
`cd backend && npm install` once, then `npm run start:a` (port 3001) and `npm run start:b` (port 3002) in two terminals.
Both bind `0.0.0.0`. macOS Application Firewall must allow the `node` binary (`socketfilterfw --add/--unblockapp <realpath of node>`).
