# Ansible Role: monitoring

Installs and configures Prometheus Node Exporter for system metrics collection on RHEL/AlmaLinux systems.

## Description

This role deploys Prometheus Node Exporter, which exposes hardware and OS metrics for consumption by Prometheus monitoring systems. It handles binary installation, systemd service configuration, user/group creation, and firewall rules.

## Requirements

- **Operating System:** RHEL 8/9, AlmaLinux 8/9, Rocky Linux 8/9, or compatible EL distributions
- **Ansible Version:** 2.9 or higher
- **Privileges:** Root access required
- **Network:** Outbound HTTPS access to GitHub for binary download
- **Firewall:** Role configures firewalld; ensure firewalld is installed and running

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `node_exporter_version` | `1.7.0` | Version of Node Exporter to install |
| `node_exporter_listen_address` | `0.0.0.0:9100` | Address and port to listen on |
| `node_exporter_user` | `node_exporter` | System user to run the service |
| `node_exporter_group` | `node_exporter` | System group for the service |

## Dependencies

None.

## Example Playbook

### Basic Usage

```yaml
- hosts: all
  become: true
  roles:
    - role: monitoring
```

### With Custom Configuration

```yaml
- hosts: all
  become: true
  vars:
    node_exporter_version: "1.8.0"
    node_exporter_listen_address: "0.0.0.0:9100"
  roles:
    - role: monitoring
```

### Deploy to All Nodes in Infrastructure

```yaml
- hosts: all
  become: true
  roles:
    - role: monitoring

- hosts: prometheus_servers
  become: true
  tasks:
    - name: Configure Prometheus to scrape nodes
      template:
        src: prometheus.yml.j2
        dest: /etc/prometheus/prometheus.yml
      notify: Restart prometheus
```

## What This Role Configures

1. **User and Group:**
   - Creates `node_exporter` system user (no shell, no home)
   - Creates `node_exporter` system group

2. **Binary Installation:**
   - Downloads Node Exporter from GitHub releases
   - Extracts and installs to `/usr/local/bin/node_exporter`

3. **Systemd Service:**
   - Deploys systemd unit file to `/etc/systemd/system/node_exporter.service`
   - Enables and starts the service

4. **Firewall:**
   - Opens port 9100/tcp in firewalld

## Handlers

| Handler | Description |
|---------|-------------|
| `Restart node_exporter` | Restarts Node Exporter when binary or configuration changes |

## Exposed Metrics

Node Exporter provides metrics including:

- **CPU:** Usage, cores, frequency
- **Memory:** Total, available, buffers, cache
- **Disk:** I/O, space usage, inodes
- **Network:** Interface statistics, errors
- **Filesystem:** Mount points, space
- **System:** Load average, uptime, processes

Access metrics at:
```
http://<host>:9100/metrics
```

## Prometheus Integration

Add the following to your Prometheus configuration to scrape Node Exporter:

```yaml
scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets:
          - 'node1.example.com:9100'
          - 'node2.example.com:9100'
```

Or with service discovery:

```yaml
scrape_configs:
  - job_name: 'node'
    file_sd_configs:
      - files:
          - '/etc/prometheus/targets/nodes.yml'
```

## Verification

### Check Service Status

```bash
systemctl status node_exporter
```

### Test Metrics Endpoint

```bash
curl http://localhost:9100/metrics
```

### Verify Specific Metrics

```bash
curl -s http://localhost:9100/metrics | grep node_cpu_seconds_total
curl -s http://localhost:9100/metrics | grep node_memory_MemTotal_bytes
```

## Security Considerations

- Consider binding to specific interface instead of `0.0.0.0`
- Use firewall rules to restrict access to trusted Prometheus servers
- For TLS encryption, consider using a reverse proxy or Node Exporter's built-in TLS support

## License

MIT

## Author Information

This role was created for the OnPrem AlmaLinux Lab environment.
