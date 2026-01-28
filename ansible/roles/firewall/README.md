# Firewall

An Ansible role that manages firewalld configuration on RHEL-based systems, ensuring the firewall service is running and configured with the specified services and zones.

## Requirements

- **Operating System**: AlmaLinux 8/9, RHEL 8/9, Rocky Linux 8/9, or other RHEL-compatible distributions
- **Ansible Version**: 2.9 or higher
- **Privileges**: Root access required (become: yes)
- **Package**: firewalld must be installed (included in the `common` role)

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `firewall_services` | `['ssh']` | List of firewalld services to allow through the firewall |
| `firewall_zone` | `public` | Firewalld zone to configure (e.g., `public`, `internal`, `dmz`, `trusted`) |

### Available Firewalld Services

Common services that can be added to `firewall_services`:

- `ssh` - SSH access (port 22)
- `http` - HTTP web traffic (port 80)
- `https` - HTTPS web traffic (port 443)
- `dns` - DNS queries (port 53)
- `ntp` - NTP time synchronization (port 123)
- `smtp` - Email relay (port 25)
- `mysql` - MySQL/MariaDB database (port 3306)
- `postgresql` - PostgreSQL database (port 5432)

For a complete list, run: `firewall-cmd --get-services`

## Dependencies

- It is recommended to apply the `common` role first to ensure firewalld is installed

## Example Playbook

### Basic Usage (SSH only)

```yaml
- hosts: all
  become: yes
  roles:
    - firewall
```

### Web Server Configuration

```yaml
- hosts: webservers
  become: yes
  roles:
    - role: firewall
      vars:
        firewall_services:
          - ssh
          - http
          - https
        firewall_zone: public
```

### Database Server Configuration

```yaml
- hosts: databases
  become: yes
  roles:
    - role: firewall
      vars:
        firewall_services:
          - ssh
          - mysql
        firewall_zone: internal
```

### Multi-Service Application Server

```yaml
- hosts: appservers
  become: yes
  roles:
    - role: firewall
      vars:
        firewall_services:
          - ssh
          - http
          - https
          - ntp
        firewall_zone: dmz
```

## Tasks Performed

1. **Service Enablement**: Ensures firewalld is enabled and running
2. **Service Configuration**: Allows specified services through the configured firewall zone with both permanent and immediate effect

## Handlers

| Handler | Description |
|---------|-------------|
| `Reload firewalld` | Reloads firewalld configuration to apply changes |

## Notes

- All firewall rules are applied both permanently and immediately, so no reboot is required
- The default zone `public` is suitable for most internet-facing servers
- Use `internal` or `trusted` zones for servers in protected network segments
- Consider using the `dmz` zone for servers in a demilitarized zone

## License

MIT

## Author Information

This role was created for the AlmaLinux Lab environment.
