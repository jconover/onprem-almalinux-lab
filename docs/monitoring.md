# Monitoring and Observability

## 1. Overview

Monitoring is a universal interview topic for Senior Linux Admin roles. Interviewers
want to know that you can design a monitoring stack, write meaningful alerts, and
handle incident response. This document covers three monitoring approaches at
different depths:

1. **Prometheus + Grafana** -- Hands-on lab implementation with node_exporter
   already deployed to all lab nodes via Puppet/Ansible.
2. **Nagios / Zabbix** -- Conceptual depth for interview discussions about
   traditional monitoring tools.
3. **ELK Stack** -- Conceptual coverage of centralized log aggregation.

### The Three Pillars of Observability

| Pillar   | What It Is                        | Tool Examples                    |
|----------|-----------------------------------|----------------------------------|
| **Metrics** | Numeric time-series data (CPU, memory, request rate) | Prometheus, Zabbix, CloudWatch |
| **Logs**    | Structured/unstructured event records                | ELK, Loki, Splunk, journald    |
| **Traces**  | Request path through distributed systems             | Jaeger, Zipkin, AWS X-Ray      |

A complete observability strategy uses all three. This lab focuses on metrics
(Prometheus) with awareness of logs (ELK) and traditional monitoring (Nagios/Zabbix).

---

## 2. Architecture

### Lab Monitoring Stack

```
+------------------+     +------------------+     +------------------+
| alma10-bastion   |     | alma10-app       |     | alma10-db        |
| node_exporter    |     | node_exporter    |     | node_exporter    |
| :9100            |     | :9100            |     | :9100            |
+--------+---------+     +--------+---------+     +--------+---------+
         |                        |                        |
         +------------------------+------------------------+
                                  |
                        +-------------------+
                        | alma10-admin      |
                        | Prometheus :9090  |
                        | Grafana    :3000  |
                        | Alertmanager:9093 |
                        | node_exporter     |
                        +-------------------+
```

### node_exporter Deployment

The lab's Puppet `profile::monitoring` class deploys node_exporter to all nodes:
- Downloads the binary from GitHub releases
- Creates a `node_exporter` system user/group
- Installs a systemd unit file (EPP template)
- Opens port 9100/tcp in firewalld

See `/home/justin/labs/onprem-almalinux-lab/puppet/modules/profile/manifests/monitoring.pp`
for the implementation.

---

## 3. Prerequisites

### For Prometheus + Grafana Lab

```bash
# On alma10-admin (monitoring server)
sudo dnf install -y wget tar

# Prometheus (on admin node)
wget https://github.com/prometheus/prometheus/releases/download/v2.50.0/prometheus-2.50.0.linux-amd64.tar.gz
tar xzf prometheus-2.50.0.linux-amd64.tar.gz
sudo cp prometheus-2.50.0.linux-amd64/{prometheus,promtool} /usr/local/bin/

# Grafana (on admin node)
sudo dnf install -y https://dl.grafana.com/oss/release/grafana-10.4.0-1.x86_64.rpm

# Alertmanager (on admin node)
wget https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz
tar xzf alertmanager-0.27.0.linux-amd64.tar.gz
sudo cp alertmanager-0.27.0.linux-amd64/alertmanager /usr/local/bin/
```

### Firewall Rules

```bash
# On admin node
sudo firewall-cmd --permanent --add-port=9090/tcp   # Prometheus
sudo firewall-cmd --permanent --add-port=3000/tcp   # Grafana
sudo firewall-cmd --permanent --add-port=9093/tcp   # Alertmanager
sudo firewall-cmd --reload

# On all nodes (already done by Puppet)
sudo firewall-cmd --permanent --add-port=9100/tcp   # node_exporter
sudo firewall-cmd --reload
```

---

## 4. Step-by-Step Setup / Deep Dive

### 4.1 Prometheus Server Setup

#### prometheus.yml Configuration

```yaml
# /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s          # How often to scrape targets
  evaluation_interval: 15s      # How often to evaluate rules
  scrape_timeout: 10s           # Timeout per scrape

# Alert rules
rule_files:
  - "/etc/prometheus/rules/*.yml"

# Alertmanager integration
alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

# Scrape targets
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets:
          - 'alma10-bastion:9100'
          - 'alma10-admin:9100'
          - 'alma10-app:9100'
          - 'alma10-app2:9100'
          - 'alma10-db:9100'
        labels:
          cluster: 'alma10'
```

#### Systemd Unit File

```ini
# /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus Monitoring
After=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=30d \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.enable-lifecycle
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
# Create user and directories
sudo useradd -r -s /sbin/nologin prometheus
sudo mkdir -p /etc/prometheus/rules /var/lib/prometheus
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

# Start Prometheus
sudo systemctl daemon-reload
sudo systemctl enable --now prometheus

# Verify
curl http://localhost:9090/-/healthy
# Expected: Prometheus Server is Healthy.
```

### 4.2 PromQL Examples

#### CPU Usage

```promql
# CPU usage percentage per instance (averaged over 5 minutes)
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# CPU usage by mode
rate(node_cpu_seconds_total[5m]) * 100
```

#### Memory Usage

```promql
# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Memory available in GB
node_memory_MemAvailable_bytes / 1024 / 1024 / 1024
```

#### Disk Usage

```promql
# Disk usage percentage per mountpoint
(1 - (node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes{fstype!="tmpfs"})) * 100

# Disk space available per filesystem
node_filesystem_avail_bytes{fstype!="tmpfs"} / 1024 / 1024 / 1024
```

#### System Uptime

```promql
# Uptime in days
(time() - node_boot_time_seconds) / 86400

# Nodes up (1 = up, 0 = down)
up{job="node_exporter"}
```

#### Network

```promql
# Network bytes received per second
rate(node_network_receive_bytes_total{device!="lo"}[5m])

# Network errors
rate(node_network_receive_errs_total[5m])
```

### 4.3 Alert Rules

```yaml
# /etc/prometheus/rules/node-alerts.yml
groups:
  - name: node-alerts
    rules:
      # Node is down
      - alert: NodeDown
        expr: up{job="node_exporter"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Node {{ $labels.instance }} is down"
          description: "{{ $labels.instance }} has been unreachable for 2 minutes."

      # Disk usage > 80%
      - alert: DiskSpaceLow
        expr: |
          (1 - (node_filesystem_avail_bytes{fstype!="tmpfs"} /
                node_filesystem_size_bytes{fstype!="tmpfs"})) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk usage above 80% on {{ $labels.instance }}"
          description: "{{ $labels.mountpoint }} is {{ $value | printf \"%.1f\" }}% full."

      # CPU usage > 90%
      - alert: HighCPU
        expr: |
          100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High CPU on {{ $labels.instance }}"
          description: "CPU usage has been above 90% for 10 minutes."

      # Memory usage > 90%
      - alert: HighMemory
        expr: |
          (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory on {{ $labels.instance }}"
          description: "Memory usage is {{ $value | printf \"%.1f\" }}%."

      # System reboot detected
      - alert: NodeReboot
        expr: changes(node_boot_time_seconds[10m]) > 0
        labels:
          severity: info
        annotations:
          summary: "Node {{ $labels.instance }} rebooted"
```

### 4.4 Alertmanager Configuration

```yaml
# /etc/prometheus/alertmanager.yml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'default'

  routes:
    - match:
        severity: critical
      receiver: 'pager'
      repeat_interval: 1h

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://localhost:5001/webhook'

  - name: 'pager'
    webhook_configs:
      - url: 'http://localhost:5001/webhook'
    # In production, use PagerDuty:
    # pagerduty_configs:
    #   - service_key: '<YOUR_PD_KEY>'
    #     severity: '{{ .GroupLabels.severity }}'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['instance']
```

### 4.5 Grafana Setup

```bash
# Start Grafana
sudo systemctl enable --now grafana-server

# Access at http://alma10-admin:3000
# Default credentials: admin / admin (change on first login)
```

#### Add Prometheus Data Source

1. Navigate to Configuration -> Data Sources -> Add Data Source
2. Select Prometheus
3. URL: `http://localhost:9090`
4. Click "Save & Test"

#### Import Node Exporter Dashboard

1. Navigate to Dashboards -> Import
2. Enter ID: **1860** (Node Exporter Full)
3. Select the Prometheus data source
4. Click Import

This gives you comprehensive OS metrics including CPU, memory, disk, network,
and system information for all lab nodes.

### 4.6 Nagios (Conceptual Interview Depth)

Nagios is the granddaddy of infrastructure monitoring. Many enterprises still
run it.

**Architecture**:
```
Nagios Server (central)
  |
  +-- Active checks: Server reaches out to target (e.g., check_http)
  +-- NRPE checks: Server tells target to run a local plugin
  +-- Passive checks: Target sends results to server (NSCA)
```

**Key concepts**:
- **Plugins**: Executables that return exit codes (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)
- **NRPE** (Nagios Remote Plugin Executor): Agent on target nodes that runs plugins on demand
- **check_mk**: Extends Nagios with auto-discovery and agent-based bulk checks
- **Object definitions**: hosts, services, hostgroups, servicegroups, contacts, timeperiods
- **Flap detection**: Identifies services oscillating between OK and CRITICAL
- **Downtimes**: Scheduled maintenance windows that suppress alerts

**Common plugins**:
```bash
check_ping -H target -w 100,20% -c 500,60%    # Ping check
check_http -H target -p 80                      # HTTP check
check_disk -w 20% -c 10% -p /                  # Disk space
check_load -w 5,4,3 -c 10,8,6                  # Load average
check_procs -w 250 -c 400                       # Process count
```

### 4.7 Zabbix (Conceptual Interview Depth)

Zabbix is a more modern alternative to Nagios with auto-discovery and a web UI.

**Architecture**:
```
Zabbix Server + Database (PostgreSQL/MySQL)
  |
  +-- Zabbix Agent (on target nodes)
  |     Active mode: agent connects to server
  |     Passive mode: server connects to agent
  +-- SNMP polling (network devices)
  +-- JMX monitoring (Java applications)
  +-- Web scenarios (HTTP checks)
```

**Key concepts**:
- **Templates**: Predefined monitoring configurations for OS types, applications
- **Triggers**: Logical expressions that define problem conditions
- **Auto-discovery**: Network scanning to find new hosts automatically
- **Low-level discovery**: Dynamic discovery of filesystems, interfaces, etc.
- **Macros**: Variables for reusable templates (`{$DISK_WARN}`)
- **Maps**: Visual network topology representations

### 4.8 ELK Stack (Conceptual)

**Architecture**:
```
Log Sources                     Pipeline                    Storage + UI
===========                     ========                    ============

Applications --+
systemd/journal-+-> Filebeat --> Logstash --> Elasticsearch --> Kibana
rsyslog --------+                  |
audit.log ------+            (parse, filter,
                              transform, enrich)
```

**Components**:
- **Elasticsearch**: Distributed search and analytics engine (stores logs as JSON documents)
- **Logstash**: Data processing pipeline (parse, filter, transform, output)
- **Kibana**: Visualization UI (dashboards, discover, visualize)
- **Filebeat**: Lightweight log shipper (reads files, forwards to Logstash/Elasticsearch)

**Logstash pipeline example**:
```ruby
input {
  beats { port => 5044 }
}

filter {
  if [fileset][name] == "syslog" {
    grok {
      match => { "message" => "%{SYSLOGTIMESTAMP:syslog_timestamp} %{SYSLOGHOST:host} %{DATA:program}(?:\[%{POSINT:pid}\])?: %{GREEDYDATA:message}" }
    }
  }
}

output {
  elasticsearch {
    hosts => ["http://localhost:9200"]
    index => "syslog-%{+YYYY.MM.dd}"
  }
}
```

**Index Lifecycle Management (ILM)**:
- Hot phase: Active writes, fast storage
- Warm phase: Read-only, older data
- Cold phase: Compressed, infrequent access
- Delete phase: Automated removal after retention period

---

## 5. Verification / Testing

### Prometheus Verification

```bash
# Check Prometheus is running
curl -s http://localhost:9090/-/healthy

# Check targets are being scraped
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool

# Check specific metric
curl -s 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool

# Validate rules
promtool check rules /etc/prometheus/rules/node-alerts.yml

# Validate config
promtool check config /etc/prometheus/prometheus.yml
```

### node_exporter Verification

```bash
# Check node_exporter on each node
curl -s http://alma10-app:9100/metrics | head -20

# Check specific metric
curl -s http://alma10-app:9100/metrics | grep node_cpu_seconds_total | head -5
```

### Alertmanager Verification

```bash
# Check alertmanager is healthy
curl -s http://localhost:9093/-/healthy

# Check current alerts
curl -s http://localhost:9093/api/v2/alerts | python3 -m json.tool

# Send a test alert
curl -XPOST http://localhost:9093/api/v2/alerts -H 'Content-Type: application/json' -d '[
  {
    "labels": {"alertname": "TestAlert", "severity": "info", "instance": "test"},
    "annotations": {"summary": "This is a test alert"},
    "startsAt": "2024-01-01T00:00:00Z"
  }
]'
```

---

## 6. Troubleshooting

### Prometheus Issues

| Issue | Diagnostic | Fix |
|-------|-----------|-----|
| Target shows as DOWN | Check `curl <target>:9100/metrics` from Prometheus host | Verify node_exporter is running, firewall port 9100 is open |
| No data in Grafana | Check Prometheus data source, query in Explore tab | Verify datasource URL and Prometheus is scraping |
| Alerts not firing | `promtool check rules` | Check rule syntax, `for` duration, PromQL expression |
| High memory usage | Prometheus stores too many series | Reduce `scrape_interval`, add `metric_relabel_configs` to drop unused metrics |
| TSDB corruption | Prometheus crashed during compaction | Stop Prometheus, `promtool tsdb clean`, restart |

### Grafana Issues

```bash
# Check Grafana logs
journalctl -u grafana-server -f

# Reset admin password
grafana-cli admin reset-admin-password newpassword

# Check data source connectivity
curl -s http://localhost:9090/api/v1/query?query=up
```

### Monitoring Comparison Table

| Feature               | Prometheus         | Nagios             | Zabbix             | ELK               |
|-----------------------|--------------------|--------------------|--------------------|--------------------|
| **Type**              | Metrics (pull)     | Checks (push/pull) | Metrics + Checks   | Logs               |
| **Data Model**        | Time-series        | Status codes       | Time-series        | Documents          |
| **Query Language**    | PromQL             | None (plugins)     | Simple expressions | KQL / Lucene       |
| **Auto-discovery**    | Service discovery   | check_mk add-on    | Built-in           | N/A                |
| **Alerting**          | Alertmanager       | Built-in           | Built-in           | Watcher / Elastalert |
| **Visualization**     | Grafana (external) | Thruk / check_mk   | Built-in           | Kibana             |
| **Scalability**       | Federation, Thanos | Limited            | Proxies            | Cluster sharding   |
| **Best For**          | Cloud-native, K8s  | Legacy infra       | Enterprise hybrid  | Log analysis       |
| **License**           | Apache 2.0         | GPL (Core free)    | GPL (Core free)    | Elastic License    |
| **Learning Curve**    | Medium             | High               | Medium             | High               |

---

## 7. Architecture Decision Rationale

### Why Prometheus + Grafana for This Lab

**Decision**: Implement Prometheus with Grafana as the primary monitoring stack.

**Rationale**:
- Pull-based model integrates with service discovery (useful for cloud and K8s)
- node_exporter provides deep OS metrics without agent configuration
- PromQL is a powerful query language that is increasingly industry-standard
- Grafana is the de facto visualization tool across monitoring stacks
- Open source and cloud-neutral (works on-prem and in AWS)
- Prometheus is the CNCF graduated project for monitoring
- Interview signal: demonstrates modern monitoring skills alongside traditional

### Why node_exporter on All Nodes

**Decision**: Deploy node_exporter to every lab node via Puppet and Ansible.

**Rationale**:
- Provides consistent OS-level metrics across the entire fleet
- Lightweight (single static binary, ~10 MB RSS)
- No configuration needed on the target node
- Demonstrates automation of monitoring agent deployment
- Puppet class and Ansible role both deploy it, showing tool parity

### Why Cover Nagios and Zabbix Conceptually

**Decision**: Document Nagios and Zabbix for interview knowledge without lab implementation.

**Rationale**:
- Many enterprises still run Nagios or Zabbix
- Interview questions often ask "compare monitoring tools"
- Understanding plugin-based (Nagios) vs agent-based (Zabbix) vs pull-based (Prometheus) shows depth
- Lab resources are better spent on the Prometheus stack that also teaches cloud-native skills
- Candidates who can discuss tradeoffs across tools demonstrate senior-level thinking

---

## 8. Interview Talking Points

### "Describe your monitoring stack and why you chose it."

> "I use Prometheus with Grafana for metrics monitoring. Prometheus pulls metrics
> from node_exporter on every host every 15 seconds, giving us CPU, memory,
> disk, and network time-series data. Grafana provides dashboards for real-time
> visibility and historical analysis. Alertmanager handles alert routing --
> critical alerts page on-call via PagerDuty, warnings go to Slack. I chose
> Prometheus because it scales horizontally via federation, has a powerful query
> language (PromQL), and integrates natively with Kubernetes service discovery.
> For log aggregation I supplement with ELK or Loki depending on the environment."

### "How do you monitor a 1000-node fleet?"

> "At scale, I use Prometheus federation -- regional Prometheus instances scrape
> local targets, and a global Prometheus scrapes aggregated metrics from
> regions. For long-term storage, Thanos or Cortex provides a unified query
> layer over multiple Prometheus instances with S3-backed storage. node_exporter
> deployment is automated via Puppet or Ansible. Alert rules are version-controlled
> in Git and deployed via CI. For log aggregation, Filebeat on each node ships
> to a centralized Elasticsearch cluster with ILM policies for retention.
> Service discovery (Consul or Kubernetes) automatically registers new hosts."

### "What is the difference between metrics, logs, and traces?"

> "Metrics are numeric time-series data -- CPU at 85% at 10:30 AM. They are
> cheap to store, fast to query, and ideal for alerting and trending. Logs are
> event records -- 'user X failed login at 10:30 AM from IP Y.' They are rich
> in context but expensive to store and query at scale. Traces follow a single
> request through multiple services -- showing that a request hit the load
> balancer, then the app server, then the database, with latency at each hop.
> A complete observability strategy uses all three. Metrics tell you something
> is wrong, logs tell you what is wrong, and traces tell you where in the
> request path it went wrong."

### "How do you handle alert fatigue?"

> "Alert fatigue is when the team ignores alerts because there are too many
> low-value notifications. I address it with: First, every alert must be
> actionable -- if nobody needs to do anything, it is not an alert, it is a
> dashboard metric. Second, severity levels matter -- only critical alerts
> page on-call; warnings go to a channel reviewed during business hours.
> Third, alert inhibition -- if a node is down, suppress all service-level
> alerts for that node. Fourth, regular alert review meetings where we audit
> which alerts fired, which were actionable, and which should be tuned or
> removed. Fifth, runbooks linked to every alert so the on-call engineer
> knows exactly what to do."

### "Describe your incident response process."

> "When an alert fires: First, acknowledge it so the team knows someone is
> on it. Second, assess severity and impact -- how many users affected?
> Third, start a communication channel (Slack thread or bridge call).
> Fourth, investigate using metrics dashboards, logs, and the alert context.
> Fifth, mitigate -- get the service back up, even if that means rolling back.
> Sixth, communicate status to stakeholders. Seventh, after resolution, write
> a blameless post-mortem covering timeline, root cause, impact, and
> action items. We track action items as tickets and review them weekly."

### "When would you choose Zabbix over Prometheus?"

> "Zabbix is better when you have a heterogeneous environment with network
> devices (SNMP), legacy servers, and you want a single tool with built-in
> visualization, auto-discovery, and reporting. It also has better out-of-box
> support for Windows monitoring. Prometheus is better for cloud-native and
> container environments, Kubernetes monitoring, and when you need a powerful
> query language for complex alerting. In a mixed environment, I have seen
> teams run both -- Zabbix for legacy infrastructure and Prometheus for
> the cloud-native tier."
