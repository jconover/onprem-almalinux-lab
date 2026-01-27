# HAProxy

## Overview

HAProxy is a high-performance TCP/HTTP load balancer and reverse proxy. In
enterprise environments, it distributes incoming traffic across multiple
backend servers to provide high availability, scalability, and zero-downtime
deployments. This lab configures HAProxy on the bastion node to load-balance
HTTP traffic between the app and app2 nodes, with health checks and a
statistics dashboard.

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│  HAProxy Load Balancing Architecture                               │
│                                                                    │
│  Client Request                                                    │
│       │                                                            │
│       ▼                                                            │
│  bastion (192.168.60.10) ── HAProxy                                │
│    │  Frontend: *:80                                               │
│    │  Stats:    *:8404 (/stats)                                    │
│    │                                                               │
│    │  ┌─────── Round Robin ───────┐                                │
│    │  │                           │                                │
│    ▼  ▼                           ▼                                │
│  app (192.168.60.12:80)    app2 (192.168.60.14:80)                 │
│    Apache httpd               Apache httpd                         │
│    "Served by app"            "Served by app2"                     │
│                                                                    │
│  Health checks: GET / every 2 seconds                              │
│  Failed check threshold: 3 consecutive failures = server down      │
└────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Packages (bastion node)

```bash
sudo dnf install -y haproxy
```

### Packages (app and app2 nodes)

```bash
sudo dnf install -y httpd
```

### Firewall (bastion node)

```bash
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-port=8404/tcp
sudo firewall-cmd --reload
```

### Firewall (app and app2 nodes)

```bash
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload
```

### SELinux (bastion node)

HAProxy needs to connect to backend servers on arbitrary ports:

```bash
sudo setsebool -P haproxy_connect_any on
```

Verify:

```bash
getsebool haproxy_connect_any
# haproxy_connect_any --> on
```

---

## Step-by-Step Setup

### Backend Preparation (app and app2 nodes)

#### Step 1 -- Configure Apache on Both Backend Servers

On the **app** node:

```bash
echo "Served by app (192.168.60.12)" | sudo tee /var/www/html/index.html
sudo systemctl enable --now httpd
```

On the **app2** node:

```bash
echo "Served by app2 (192.168.60.14)" | sudo tee /var/www/html/index.html
sudo systemctl enable --now httpd
```

Verify each backend individually:

```bash
curl http://192.168.60.12
# Served by app (192.168.60.12)

curl http://192.168.60.14
# Served by app2 (192.168.60.14)
```

### HAProxy Configuration (bastion node)

#### Step 2 -- Back Up Default Configuration

```bash
sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak
```

#### Step 3 -- Write HAProxy Configuration

```bash
sudo tee /etc/haproxy/haproxy.cfg << 'EOF'
#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    log         /dev/log local0
    log         /dev/log local1 notice
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon
    stats socket /var/lib/haproxy/stats

#---------------------------------------------------------------------
# Default settings
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option                  http-server-close
    option                  forwardfor except 127.0.0.0/8
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

#---------------------------------------------------------------------
# Stats page
#---------------------------------------------------------------------
frontend stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 10s
    stats auth admin:LabPass123
    stats admin if TRUE

#---------------------------------------------------------------------
# HTTP Frontend
#---------------------------------------------------------------------
frontend http_front
    bind *:80
    default_backend http_back

#---------------------------------------------------------------------
# HTTP Backend
#---------------------------------------------------------------------
backend http_back
    balance roundrobin
    option httpchk GET /
    http-check expect status 200

    server app  192.168.60.12:80 check inter 2s fall 3 rise 2
    server app2 192.168.60.14:80 check inter 2s fall 3 rise 2
EOF
```

#### Step 4 -- Validate Configuration

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
```

Expected:

```
Configuration file is valid
```

#### Step 5 -- Start and Enable HAProxy

```bash
sudo systemctl enable --now haproxy
sudo systemctl status haproxy
```

#### Step 6 -- Test Load Balancing

```bash
for i in {1..6}; do curl -s http://192.168.60.10; done
```

Expected output (round-robin alternation):

```
Served by app (192.168.60.12)
Served by app2 (192.168.60.14)
Served by app (192.168.60.12)
Served by app2 (192.168.60.14)
Served by app (192.168.60.12)
Served by app2 (192.168.60.14)
```

#### Step 7 -- Access Stats Page

Open in browser or curl:

```bash
curl -u admin:LabPass123 http://192.168.60.10:8404/stats
```

The stats page shows:
- Backend server status (UP/DOWN)
- Current sessions and request rates
- Health check results
- Bytes in/out per server

---

## Advanced Configuration Options

### Sticky Sessions (Session Persistence)

If an application requires session affinity (e.g., shopping cart):

```
backend http_back
    balance roundrobin
    cookie SERVERID insert indirect nocache
    server app  192.168.60.12:80 check cookie app
    server app2 192.168.60.14:80 check cookie app2
```

HAProxy inserts a cookie that pins the client to the same backend.

### Alternative Balancing Algorithms

| Algorithm | Description | Use Case |
|-----------|-------------|----------|
| `roundrobin` | Cycles through servers equally | Default, stateless apps |
| `leastconn` | Routes to server with fewest connections | Long-lived connections (databases, WebSocket) |
| `source` | Hashes source IP for persistence | Simple session persistence without cookies |
| `uri` | Hashes the request URI | Caching servers (same URI always hits same server) |
| `first` | Fills first server before using next | Cost optimization (keep fewer servers active) |

Change the algorithm in the backend section:

```
backend http_back
    balance leastconn
```

### HTTPS Termination (SSL Offloading)

```
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/lab.pem
    default_backend http_back
```

HAProxy terminates TLS and forwards plain HTTP to backends. The PEM file
must contain both the certificate and private key concatenated.

### Connection Draining

When removing a server for maintenance:

```bash
# Via stats socket
echo "set server http_back/app state drain" | sudo socat stdio /var/lib/haproxy/stats
```

This stops sending new connections to the server but allows existing ones
to complete.

---

## Verification / Testing

```bash
# Basic connectivity
curl http://192.168.60.10

# Round-robin verification
for i in {1..10}; do curl -s http://192.168.60.10; done

# Health check - stop one backend
ssh app "sudo systemctl stop httpd"
sleep 5
curl http://192.168.60.10
# Should return: Served by app2 (all traffic goes to app2)

# Restore backend
ssh app "sudo systemctl start httpd"

# Stats page
curl -u admin:LabPass123 http://192.168.60.10:8404/stats

# Check HAProxy logs
sudo journalctl -u haproxy --no-pager -n 20

# Check HAProxy is listening
sudo ss -tlnp | grep haproxy
```

### Failover Test

```bash
# 1. Verify both backends are UP
curl -s -u admin:LabPass123 http://192.168.60.10:8404/stats | grep -E "(app|app2).*UP"

# 2. Stop one backend
ssh app "sudo systemctl stop httpd"

# 3. Wait for health checks to detect failure (fall 3 * inter 2s = 6s)
sleep 7

# 4. All requests should go to the remaining backend
for i in {1..4}; do curl -s http://192.168.60.10; done
# All return: Served by app2

# 5. Restore the backend
ssh app "sudo systemctl start httpd"

# 6. Wait for rise (rise 2 * inter 2s = 4s)
sleep 5

# 7. Traffic should be balanced again
for i in {1..4}; do curl -s http://192.168.60.10; done
```

---

## Troubleshooting

### HAProxy won't start

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
# Shows config errors

sudo journalctl -u haproxy --no-pager -n 30
```

Common causes:
- Syntax error in haproxy.cfg
- Port 80 already in use (another httpd running on bastion)
- SELinux denial (haproxy_connect_any not set)

### 503 Service Unavailable

All backends are down.

```bash
# Check backend servers
curl http://192.168.60.12
curl http://192.168.60.14

# Check stats page for server status
curl -u admin:LabPass123 http://192.168.60.10:8404/stats
```

### SELinux blocking HAProxy connections

```bash
sudo ausearch -m avc -ts recent | grep haproxy
sudo setsebool -P haproxy_connect_any on
```

### Cannot bind to port 80

```bash
# Check what is using port 80
sudo ss -tlnp | grep :80

# If httpd is running on bastion, stop it
sudo systemctl stop httpd
sudo systemctl disable httpd
```

### Stats page not accessible

```bash
# Check firewall
sudo firewall-cmd --list-all | grep 8404

# Add port if missing
sudo firewall-cmd --permanent --add-port=8404/tcp
sudo firewall-cmd --reload
```

### Health checks failing (servers shown as DOWN)

```bash
# Verify backend health check endpoint
curl -v http://192.168.60.12/

# Check if backend firewall allows connection from bastion
ssh app "sudo firewall-cmd --list-services"
```

---

## Architecture Decision Rationale

### Why HAProxy over nginx as a load balancer?

| Factor | HAProxy | nginx |
|--------|---------|-------|
| Primary purpose | Load balancer/proxy | Web server + proxy |
| Health checks | Advanced (HTTP, TCP, agent) | Basic (TCP, HTTP) |
| Stats/monitoring | Built-in stats page | Requires nginx Plus or modules |
| Connection draining | Native support | Requires Plus |
| Configuration | Purpose-built for LB | Dual-purpose (web + LB) |

**Trade-off:** nginx is better when you also need to serve static content
or do complex URL rewriting. HAProxy is the better choice for pure load
balancing. Many environments use both: nginx as a web server behind HAProxy.

### Why health checks?

Without health checks, HAProxy would continue sending traffic to a failed
backend, causing errors for users. HTTP health checks (`option httpchk`)
verify that the application is actually responding, not just that the TCP
port is open.

### Why a stats page?

The stats page provides real-time visibility into backend health, traffic
distribution, and connection counts. In production, this is often integrated
with monitoring systems (Prometheus, Grafana) via the stats socket or
Prometheus endpoint.

---

## Interview Talking Points

**Q: What is the difference between a layer 4 and layer 7 load balancer?**
A: Layer 4 (TCP) load balancers make routing decisions based on IP and port
without inspecting the content. Layer 7 (HTTP) load balancers can inspect
HTTP headers, URLs, and cookies to make smarter routing decisions. HAProxy
supports both modes.

**Q: Explain round-robin vs leastconn.**
A: Round-robin distributes requests equally in sequence. Leastconn routes
each new request to the server with the fewest active connections. Use
leastconn when requests have variable processing times (some are fast, some
are slow), so slower servers do not get overloaded.

**Q: How do you handle session persistence with a load balancer?**
A: Use sticky sessions via cookies (HAProxy inserts a cookie identifying the
backend server) or source IP hashing. Cookie-based persistence is more
reliable because it survives NAT changes. However, session persistence
reduces the effectiveness of load balancing.

**Q: How do you perform zero-downtime deployments behind HAProxy?**
A: Drain the server being updated (stop sending new connections, let
existing ones finish). Update the application. Re-enable the server. HAProxy
supports this via the stats socket: `set server BACKEND/SERVER state drain`.

**Q: What happens when all backend servers fail?**
A: HAProxy returns a 503 Service Unavailable error. You can configure a
custom error page or a backup server that only activates when all primary
servers are down: `server backup_srv IP:PORT check backup`.

**Q: How does HAProxy determine if a backend is healthy?**
A: Using configurable health checks. `option httpchk GET /` sends an HTTP
GET request. The `inter` parameter sets check frequency, `fall` sets how
many consecutive failures mark a server as down, and `rise` sets how many
consecutive successes bring it back up.
