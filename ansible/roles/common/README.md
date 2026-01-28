# Common

An Ansible role that performs baseline configuration for RHEL-based systems, including package installation, timezone configuration, hostname management, MOTD deployment, sysctl hardening, and SELinux enforcement.

## Requirements

- **Operating System**: AlmaLinux 8/9, RHEL 8/9, Rocky Linux 8/9, or other RHEL-compatible distributions
- **Ansible Version**: 2.9 or higher
- **Privileges**: Root access required (become: yes)

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `common_packages` | See below | List of baseline packages to install |
| `timezone` | `America/New_York` | System timezone to configure |
| `selinux_state` | `enforcing` | SELinux state: `enforcing`, `permissive`, or `disabled` |
| `sysctl_params` | See below | Dictionary of sysctl kernel parameters for security hardening |

### Default Package List

```yaml
common_packages:
  - vim
  - firewalld
  - chrony
  - policycoreutils-python-utils
  - setools-console
  - bind-utils
  - tcpdump
  - net-tools
  - lvm2
  - tar
  - rsync
```

### Default Sysctl Parameters

```yaml
sysctl_params:
  net.ipv4.ip_forward: 0
  net.ipv4.conf.all.send_redirects: 0
  net.ipv4.conf.default.accept_redirects: 0
  net.ipv4.conf.all.accept_redirects: 0
  net.ipv4.icmp_echo_ignore_broadcasts: 1
  net.ipv4.conf.all.log_martians: 1
```

## Dependencies

None.

## Example Playbook

### Basic Usage

```yaml
- hosts: all
  become: yes
  roles:
    - common
```

### Custom Configuration

```yaml
- hosts: all
  become: yes
  roles:
    - role: common
      vars:
        timezone: UTC
        selinux_state: permissive
        common_packages:
          - vim
          - firewalld
          - chrony
          - htop
          - git
        sysctl_params:
          net.ipv4.ip_forward: 1
          net.ipv4.conf.all.send_redirects: 0
```

## Tasks Performed

1. **Package Installation**: Installs baseline packages using dnf
2. **Timezone Configuration**: Sets the system timezone
3. **Hostname Configuration**: Sets hostname based on inventory_hostname
4. **MOTD Deployment**: Deploys a custom message of the day from template
5. **Sysctl Hardening**: Deploys security-focused kernel parameters
6. **SELinux Configuration**: Ensures SELinux is set to the configured state
7. **Service Enablement**: Enables and starts firewalld and chronyd services

## Handlers

| Handler | Description |
|---------|-------------|
| `Restart chronyd` | Restarts the chronyd service |
| `Reload firewalld` | Reloads firewalld configuration |
| `Reload sysctl` | Applies sysctl changes system-wide |

## Templates

This role requires the following templates in `templates/`:

- `motd.j2` - Message of the day template
- `sysctl.conf.j2` - Sysctl hardening configuration template

## License

MIT

## Author Information

This role was created for the AlmaLinux Lab environment.
