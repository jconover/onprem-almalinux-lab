# DNS Role

Ansible role for deploying and configuring a BIND DNS server with forward and reverse zone support.

## Description

This role installs and configures BIND (Berkeley Internet Name Domain) as an authoritative DNS server on RHEL/AlmaLinux systems. It provides:

- Installation of BIND packages (`bind`, `bind-utils`)
- Configuration of `named.conf` with customizable options
- Forward zone file generation with A records
- Reverse zone file generation with PTR records
- SELinux configuration for BIND
- Service management (enable and start)

## Requirements

### Supported Operating Systems

- AlmaLinux 8.x / 9.x / 10.x
- RHEL 8.x / 9.x
- Rocky Linux 8.x / 9.x
- CentOS Stream 8 / 9

### Ansible Version

- Ansible 2.9 or higher

### Prerequisites

- Target systems must have network connectivity
- SELinux in enforcing or permissive mode (role handles SELinux booleans)
- Firewall rules should allow DNS traffic (port 53 TCP/UDP) if firewalld is enabled

## Role Variables

### Required Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `dns_domain` | `lab.local` | The DNS domain name for forward and reverse zones |
| `dns_reverse_zone` | `60.168.192` | The reverse zone network (first three octets in reverse order) |
| `dns_records` | See defaults | List of DNS A records with `name` and `ip` keys |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `dns_forwarders` | `["8.8.8.8", "8.8.4.4"]` | List of upstream DNS forwarders for recursive queries |
| `dns_listen_addresses` | `["127.0.0.1", "{{ ansible_default_ipv4.address }}"]` | IP addresses for BIND to listen on |

### DNS Records Format

The `dns_records` variable expects a list of dictionaries:

```yaml
dns_records:
  - { name: "server1", ip: "192.168.60.10" }
  - { name: "server2", ip: "192.168.60.11" }
  - { name: "server3", ip: "192.168.60.12" }
```

## Dependencies

None.

## Example Playbook

### Basic Usage

```yaml
---
- name: Configure DNS server
  hosts: dns_servers
  become: true
  roles:
    - dns
```

### With Custom Variables

```yaml
---
- name: Configure DNS server with custom settings
  hosts: dns_servers
  become: true
  vars:
    dns_domain: example.com
    dns_reverse_zone: "10.0.10"
    dns_forwarders:
      - 1.1.1.1
      - 9.9.9.9
    dns_records:
      - { name: "web", ip: "10.0.10.10" }
      - { name: "db", ip: "10.0.10.11" }
      - { name: "app", ip: "10.0.10.12" }
    dns_listen_addresses:
      - "127.0.0.1"
      - "10.0.10.5"
  roles:
    - dns
```

### Inventory Example

```ini
[dns_servers]
dns01.example.com ansible_host=192.168.60.10
```

## Handlers

| Handler | Description |
|---------|-------------|
| `Restart named` | Restarts the BIND service (triggered on config changes) |
| `Reload named` | Reloads zone files without full restart |

## Templates

| Template | Destination | Description |
|----------|-------------|-------------|
| `named.conf.j2` | `/etc/named.conf` | Main BIND configuration file |
| `forward.zone.j2` | `/var/named/forward.{{ dns_domain }}` | Forward zone file with A records |
| `reverse.zone.j2` | `/var/named/reverse.{{ dns_domain }}` | Reverse zone file with PTR records |

## SELinux

This role automatically configures the following SELinux boolean:

- `named_write_master_zones` - Allows BIND to write to master zone files

## Testing

After applying the role, verify DNS functionality:

```bash
# Test forward lookup
dig @localhost server1.lab.local

# Test reverse lookup
dig @localhost -x 192.168.60.10

# Check BIND status
systemctl status named
```

## License

MIT

## Author Information

This role was created for the OnPrem AlmaLinux Lab environment.

- GitHub: [onprem-almalinux-lab](https://github.com/onprem-almalinux-lab)
