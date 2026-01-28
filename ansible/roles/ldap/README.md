# Ansible Role: ldap

Installs and configures OpenLDAP server on RHEL/AlmaLinux systems.

## Description

This role deploys an OpenLDAP directory server with a basic Directory Information Tree (DIT) structure. It handles package installation, service configuration, and initial directory population with configurable users and organizational units.

**Note:** OpenLDAP server packages (`openldap-servers`) were removed from RHEL 9+ base repositories. This role attempts installation via EPEL and provides guidance for alternatives such as 389 Directory Server (`389-ds-base`) for production environments.

## Requirements

- **Operating System:** RHEL 8/9, AlmaLinux 8/9, Rocky Linux 8/9, or compatible EL distributions
- **Ansible Version:** 2.9 or higher
- **Privileges:** Root access required
- **Dependencies:** EPEL repository (recommended for EL9+)

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `ldap_domain` | `lab.local` | LDAP domain name |
| `ldap_base_dn` | `dc=lab,dc=local` | Base Distinguished Name for the directory |
| `ldap_org` | `Lab Organization` | Organization name for the directory root |
| `ldap_admin_password` | `changeme` | Admin bind password (use Ansible Vault in production) |
| `ldap_users` | *see below* | List of users to create in the directory |

### User Definition Structure

```yaml
ldap_users:
  - uid: testuser1
    cn: "Test User One"
    sn: "One"
    uidNumber: 10001
    gidNumber: 10001
    homeDirectory: /home/testuser1
    loginShell: /bin/bash
```

## Dependencies

None.

## Example Playbook

### Basic Usage

```yaml
- hosts: ldap_servers
  become: true
  roles:
    - role: ldap
```

### With Custom Configuration

```yaml
- hosts: ldap_servers
  become: true
  vars:
    ldap_domain: example.com
    ldap_base_dn: "dc=example,dc=com"
    ldap_org: "Example Corporation"
    ldap_admin_password: "{{ vault_ldap_admin_password }}"
    ldap_users:
      - uid: jdoe
        cn: "John Doe"
        sn: "Doe"
        uidNumber: 10001
        gidNumber: 10001
        homeDirectory: /home/jdoe
        loginShell: /bin/bash
  roles:
    - role: ldap
```

## Security Considerations

- Store `ldap_admin_password` in Ansible Vault for production deployments
- Consider implementing TLS/STARTTLS for secure LDAP communications
- Review ACLs and access controls before exposing to production networks

## Alternatives for RHEL 9+

If OpenLDAP server packages are unavailable, consider:

- **389 Directory Server** (`389-ds-base`): Red Hat's recommended replacement
- **FreeIPA**: Full identity management solution including LDAP, Kerberos, and DNS

## License

MIT

## Author Information

This role was created for the OnPrem AlmaLinux Lab environment.
