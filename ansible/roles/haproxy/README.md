# Ansible Role: haproxy

Installs and configures HAProxy load balancer on RHEL/AlmaLinux systems.

## Description

This role deploys HAProxy as a Layer 7 HTTP load balancer with configurable frontend/backend settings, statistics dashboard, and SELinux compatibility. It provides a production-ready load balancing solution with health checks and multiple balancing algorithms.

## Requirements

- **Operating System:** RHEL 8/9, AlmaLinux 8/9, Rocky Linux 8/9, or compatible EL distributions
- **Ansible Version:** 2.9 or higher
- **Privileges:** Root access required
- **SELinux:** Role handles required SELinux boolean configuration

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `haproxy_frontend_port` | `80` | Port for the frontend listener |
| `haproxy_stats_port` | `8404` | Port for the statistics dashboard |
| `haproxy_stats_enabled` | `true` | Enable/disable the stats dashboard |
| `haproxy_backend_servers` | `groups['apps']` | List of backend server hostnames/IPs |
| `haproxy_backend_port` | `80` | Port on backend servers |
| `haproxy_balance_algorithm` | `roundrobin` | Load balancing algorithm |

### Supported Balance Algorithms

- `roundrobin` - Sequential server selection (default)
- `leastconn` - Fewest current connections
- `source` - Client IP hash for session persistence
- `first` - First available server
- `uri` - URI hash for cache optimization

## Dependencies

None.

## Example Playbook

### Basic Usage

```yaml
- hosts: loadbalancers
  become: true
  roles:
    - role: haproxy
```

### With Custom Configuration

```yaml
- hosts: loadbalancers
  become: true
  vars:
    haproxy_frontend_port: 8080
    haproxy_stats_port: 9000
    haproxy_stats_enabled: true
    haproxy_backend_servers:
      - web1.example.com
      - web2.example.com
      - web3.example.com
    haproxy_backend_port: 80
    haproxy_balance_algorithm: leastconn
  roles:
    - role: haproxy
```

### Using Inventory Groups

```yaml
# inventory/hosts
[apps]
app1 ansible_host=192.168.1.10
app2 ansible_host=192.168.1.11

[loadbalancers]
lb1 ansible_host=192.168.1.5

# playbook.yml
- hosts: loadbalancers
  become: true
  vars:
    haproxy_backend_servers: "{{ groups['apps'] }}"
  roles:
    - role: haproxy
```

## What This Role Configures

1. **Package Installation:**
   - `haproxy` - HAProxy load balancer

2. **Configuration:**
   - Deploys `/etc/haproxy/haproxy.cfg` with validation
   - Configures frontend listener
   - Configures backend server pool
   - Optional statistics dashboard

3. **SELinux:**
   - Sets `haproxy_connect_any` boolean for backend connectivity

4. **Service:**
   - Enables and starts `haproxy` service

## Handlers

| Handler | Description |
|---------|-------------|
| `Restart haproxy` | Restarts HAProxy service when configuration changes |

## Statistics Dashboard

When enabled, the statistics dashboard is available at:

```
http://<haproxy_host>:<haproxy_stats_port>/stats
```

The dashboard provides:
- Real-time server status
- Connection statistics
- Request/response metrics
- Health check status

## Verification

### Check HAProxy Status

```bash
systemctl status haproxy
haproxy -c -f /etc/haproxy/haproxy.cfg
```

### Test Load Balancing

```bash
curl http://<haproxy_host>:<haproxy_frontend_port>/
```

### View Statistics

```bash
curl http://<haproxy_host>:<haproxy_stats_port>/stats
```

## License

MIT

## Author Information

This role was created for the OnPrem AlmaLinux Lab environment.
