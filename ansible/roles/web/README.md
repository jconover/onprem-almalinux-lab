# Ansible Role: web

An Ansible role that installs and configures Apache HTTP Server (httpd) with mod_ssl on RHEL-based systems. This role deploys a virtual host configuration, sets up a default index page, and ensures the web server is running and enabled.

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
- The `domain` variable must be defined in your inventory or playbook

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `web_server_name` | `{{ inventory_hostname }}.{{ domain }}` | The ServerName directive for the virtual host |
| `web_doc_root` | `/var/www/html` | Document root directory for the web server |
| `web_listen_port` | `80` | HTTP port the web server listens on |
| `domain` | *(required)* | Domain name used in server name and index page |

## Dependencies

None.

## Handlers

This role includes the following handlers:

- **Restart httpd**: Performs a full restart of the httpd service
- **Reload httpd**: Gracefully reloads httpd configuration without dropping connections

## Templates

| Template | Destination | Description |
|----------|-------------|-------------|
| `vhost.conf.j2` | `/etc/httpd/conf.d/vhost.conf` | Apache virtual host configuration |

## Tasks Performed

1. Installs `httpd` and `mod_ssl` packages
2. Deploys virtual host configuration from template
3. Creates a default index.html page with hostname information
4. Enables and starts the httpd service
5. Verifies the web server is responding correctly (smoke test)

## Example Playbook

### Basic Usage

```yaml
---
- hosts: webservers
  become: true
  vars:
    domain: example.com
  roles:
    - web
```

### Custom Configuration

```yaml
---
- hosts: webservers
  become: true
  vars:
    domain: example.com
    web_server_name: www.example.com
    web_doc_root: /srv/www/html
    web_listen_port: 8080
  roles:
    - web
```

### With Inventory Variables

```ini
# inventory/hosts
[webservers]
web01.example.com

[webservers:vars]
domain=example.com
web_listen_port=80
```

```yaml
---
- hosts: webservers
  become: true
  roles:
    - web
```

## Testing

After running this role, you can verify the installation:

```bash
# Check httpd status
systemctl status httpd

# Test HTTP response
curl -I http://localhost:80/

# View virtual host configuration
cat /etc/httpd/conf.d/vhost.conf
```

## License

MIT

## Author Information

This role was created for the AlmaLinux Lab environment.

For issues and contributions, please visit the project repository.
