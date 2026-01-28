# Ansible Role: db

An Ansible role that installs and configures MariaDB server on RHEL-based systems. This role performs secure installation steps including setting the root password, removing anonymous users and test database, and creates an application database with a dedicated user.

## Requirements

### Operating Systems

- AlmaLinux 8/9
- RHEL 8/9
- CentOS Stream 8/9
- Rocky Linux 8/9

### Ansible Version

- Ansible 2.9 or higher

### Prerequisites

- Target hosts must have access to DNF package repositories
- Python 3 with PyMySQL library (installed automatically by this role)

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `db_name` | `appdb` | Name of the application database to create |
| `db_user` | `appuser` | Username for the application database user |
| `db_password` | `{{ vault_db_app_password \| default('changeme') }}` | Password for the application database user |
| `db_root_password` | `{{ vault_db_root_password \| default('changeme') }}` | MariaDB root password |
| `db_bind_address` | `0.0.0.0` | IP address MariaDB binds to (0.0.0.0 = all interfaces) |
| `db_innodb_buffer_pool_size` | `256M` | InnoDB buffer pool size for caching data and indexes |

### Security Note

It is strongly recommended to use Ansible Vault for storing sensitive variables:

```yaml
# group_vars/dbservers/vault.yml (encrypted)
vault_db_root_password: "secure_root_password_here"
vault_db_app_password: "secure_app_password_here"
```

## Dependencies

None.

## Handlers

This role includes the following handlers:

- **Restart mariadb**: Restarts the MariaDB service when configuration changes

## Templates

| Template | Destination | Description |
|----------|-------------|-------------|
| `server.cnf.j2` | `/etc/my.cnf.d/server.cnf` | MariaDB server configuration |

### Server Configuration Details

The deployed `server.cnf` includes:

- Configurable bind address and InnoDB buffer pool size
- InnoDB log file size: 64M
- File-per-table enabled for InnoDB
- Maximum connections: 100
- Character set: utf8mb4 with unicode_ci collation

## Tasks Performed

1. Installs `mariadb-server` and `python3-PyMySQL` packages
2. Deploys MariaDB server configuration from template
3. Enables and starts the MariaDB service
4. Sets the MariaDB root password
5. Removes anonymous MySQL users (security hardening)
6. Removes the test database (security hardening)
7. Creates the application database
8. Creates the application database user with full privileges on the app database

## Example Playbook

### Basic Usage

```yaml
---
- hosts: dbservers
  become: true
  roles:
    - db
```

### With Custom Configuration

```yaml
---
- hosts: dbservers
  become: true
  vars:
    db_name: myapp_production
    db_user: myapp_user
    db_password: "{{ vault_db_app_password }}"
    db_root_password: "{{ vault_db_root_password }}"
    db_bind_address: 127.0.0.1
    db_innodb_buffer_pool_size: 512M
  roles:
    - db
```

### With Ansible Vault

```yaml
---
- hosts: dbservers
  become: true
  vars_files:
    - vars/vault.yml
  vars:
    db_name: production_db
    db_user: prod_user
  roles:
    - db
```

### With Inventory Variables

```ini
# inventory/hosts
[dbservers]
db01.example.com

[dbservers:vars]
db_name=appdb
db_user=appuser
db_bind_address=0.0.0.0
```

```yaml
---
- hosts: dbservers
  become: true
  vars_files:
    - vault/db_credentials.yml
  roles:
    - db
```

## Testing

After running this role, you can verify the installation:

```bash
# Check MariaDB status
systemctl status mariadb

# Test database connection as root
mysql -u root -p -e "SHOW DATABASES;"

# Test application user connection
mysql -u appuser -p appdb -e "SHOW TABLES;"

# Verify server configuration
cat /etc/my.cnf.d/server.cnf
```

## Security Considerations

- This role removes anonymous users and the test database as part of security hardening
- The application user is granted privileges only on the specified application database
- Remote root login is configured via the bind address setting
- All password-related tasks use `no_log: true` to prevent credential exposure in logs
- Use Ansible Vault for production deployments to encrypt sensitive credentials

## License

MIT

## Author Information

This role was created for the AlmaLinux Lab environment.

For issues and contributions, please visit the project repository.
