# Ansible Role: sssd

Configures SSSD (System Security Services Daemon) for LDAP authentication on RHEL/AlmaLinux systems.

## Description

This role installs and configures SSSD to provide centralized authentication against an LDAP directory server. It handles package installation, SSSD configuration deployment, authselect profile setup, and automatic home directory creation via oddjobd.

## Requirements

- **Operating System:** RHEL 8/9, AlmaLinux 8/9, Rocky Linux 8/9, or compatible EL distributions
- **Ansible Version:** 2.9 or higher
- **Privileges:** Root access required
- **Prerequisites:** A functioning LDAP directory server (see `ldap` role)

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `sssd_ldap_uri` | `ldap://<dbs_host>` | LDAP server URI (ldap:// or ldaps://) |
| `sssd_ldap_base_dn` | `dc=lab,dc=local` | Base DN for LDAP searches |
| `sssd_ldap_user_search_base` | `ou=People,dc=lab,dc=local` | Search base for user entries |
| `sssd_ldap_group_search_base` | `ou=Groups,dc=lab,dc=local` | Search base for group entries |

## Dependencies

- An LDAP directory server must be available (can be configured with the `ldap` role)

## Example Playbook

### Basic Usage

```yaml
- hosts: all
  become: true
  roles:
    - role: sssd
```

### With Custom LDAP Server

```yaml
- hosts: clients
  become: true
  vars:
    sssd_ldap_uri: "ldaps://ldap.example.com"
    sssd_ldap_base_dn: "dc=example,dc=com"
    sssd_ldap_user_search_base: "ou=Users,dc=example,dc=com"
    sssd_ldap_group_search_base: "ou=Groups,dc=example,dc=com"
  roles:
    - role: sssd
```

### Combined with LDAP Role

```yaml
- hosts: ldap_servers
  become: true
  roles:
    - role: ldap

- hosts: clients
  become: true
  roles:
    - role: sssd
```

## What This Role Configures

1. **Packages Installed:**
   - `sssd` - Core SSSD daemon
   - `sssd-ldap` - LDAP provider for SSSD
   - `oddjob` - D-Bus service for running privileged operations
   - `oddjob-mkhomedir` - Home directory creation module
   - `authselect` - Authentication profile manager

2. **Services Enabled:**
   - `sssd` - Authentication daemon
   - `oddjobd` - Automatic home directory creation

3. **Authentication Configuration:**
   - Configures authselect with SSSD profile
   - Enables automatic home directory creation on first login

## Handlers

| Handler | Description |
|---------|-------------|
| `Restart sssd` | Restarts SSSD service when configuration changes |

## Troubleshooting

### Verify SSSD Status

```bash
systemctl status sssd
sssctl config-check
```

### Test User Lookup

```bash
id <username>
getent passwd <username>
```

### Check SSSD Logs

```bash
journalctl -u sssd
cat /var/log/sssd/sssd_*.log
```

## License

MIT

## Author Information

This role was created for the OnPrem AlmaLinux Lab environment.
