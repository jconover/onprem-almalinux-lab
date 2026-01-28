# NFS Role

Ansible role for deploying and configuring NFS server and client systems.

## Description

This role provides a complete NFS solution that handles both server and client configuration based on group membership. It includes:

**Server Features (hosts in `dbs` group):**
- Installation of NFS server packages
- Creation of export directories
- Configuration of `/etc/exports`
- SELinux configuration for NFS exports
- NFS server service management

**Client Features (hosts not in `dbs` group):**
- Installation of NFS client packages (`nfs-utils`, `autofs`)
- Creation of mount point directories
- Persistent NFS mount configuration via `/etc/fstab`

## Requirements

### Supported Operating Systems

- AlmaLinux 8.x / 9.x / 10.x
- RHEL 8.x / 9.x
- Rocky Linux 8.x / 9.x
- CentOS Stream 8 / 9

### Ansible Version

- Ansible 2.9 or higher

### Prerequisites

- Target systems must have network connectivity between server and clients
- SELinux in enforcing or permissive mode (role handles SELinux booleans)
- Firewall rules should allow NFS traffic if firewalld is enabled:
  - TCP/UDP 2049 (NFS)
  - TCP/UDP 111 (rpcbind)

## Role Variables

### Server Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `nfs_exports` | See defaults | List of directories to export with NFS options |

#### NFS Exports Format

```yaml
nfs_exports:
  - path: /srv/nfs/shared
    options: "192.168.60.0/24(rw,sync,no_root_squash)"
  - path: /srv/nfs/home
    options: "192.168.60.0/24(rw,sync,root_squash)"
```

| Export Option | Description |
|---------------|-------------|
| `rw` | Read-write access |
| `sync` | Synchronous writes (safer) |
| `no_root_squash` | Allow root access from clients |
| `root_squash` | Map root to anonymous user (more secure) |

### Client Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `nfs_client_mounts` | See defaults | List of NFS mounts to configure on clients |

#### NFS Client Mounts Format

```yaml
nfs_client_mounts:
  - src: "192.168.60.13:/srv/nfs/shared"
    path: /mnt/shared
    fstype: nfs
    opts: defaults,_netdev
```

| Mount Field | Description |
|-------------|-------------|
| `src` | NFS server and export path (server:/path) |
| `path` | Local mount point directory |
| `fstype` | Filesystem type (should be `nfs` or `nfs4`) |
| `opts` | Mount options (`_netdev` recommended for network mounts) |

## Dependencies

None.

## Example Playbook

### Basic Usage

```yaml
---
- name: Configure NFS server and clients
  hosts: all
  become: true
  roles:
    - nfs
```

### With Custom Variables

```yaml
---
- name: Configure NFS infrastructure
  hosts: all
  become: true
  vars:
    nfs_exports:
      - path: /data/shared
        options: "10.0.0.0/8(rw,sync,no_root_squash)"
      - path: /data/backup
        options: "10.0.0.0/8(ro,sync,root_squash)"
    nfs_client_mounts:
      - src: "10.0.0.50:/data/shared"
        path: /mnt/data
        fstype: nfs
        opts: defaults,_netdev,soft,timeo=100
  roles:
    - nfs
```

### Inventory Example

The role uses group membership to determine server vs client configuration:

```ini
[dbs]
db01.example.com ansible_host=192.168.60.13

[apps]
app01.example.com ansible_host=192.168.60.12
app02.example.com ansible_host=192.168.60.14

[webservers]
web01.example.com ansible_host=192.168.60.11
```

In this example:
- `db01` (in `dbs` group) becomes the NFS server
- All other hosts become NFS clients

## Handlers

| Handler | Description |
|---------|-------------|
| `Restart nfs-server` | Restarts the NFS server service |
| `Export filesystems` | Re-exports all filesystems (`exportfs -ra`) |

## Templates

| Template | Destination | Description |
|----------|-------------|-------------|
| `exports.j2` | `/etc/exports` | NFS exports configuration file |

## SELinux

This role automatically configures the following SELinux booleans on NFS servers:

- `nfs_export_all_rw` - Allow NFS to export read-write
- `nfs_export_all_ro` - Allow NFS to export read-only

## Testing

### On NFS Server

```bash
# Check exported filesystems
exportfs -v

# Check NFS server status
systemctl status nfs-server

# View active NFS connections
ss -tlnp | grep -E '(2049|111)'
```

### On NFS Clients

```bash
# Verify mounts
mount | grep nfs

# Check mount accessibility
ls -la /mnt/shared

# Test write access (if rw)
touch /mnt/shared/testfile
```

## Troubleshooting

### Common Issues

1. **Mount fails with "access denied"**
   - Verify the client IP is in the allowed network range in exports
   - Check SELinux booleans are set correctly
   - Verify firewall rules allow NFS traffic

2. **Mount hangs**
   - Ensure NFS server is running and accessible
   - Check network connectivity between client and server
   - Verify rpcbind service is running

3. **Permission denied on mounted share**
   - Check `root_squash` vs `no_root_squash` settings
   - Verify directory permissions on the server

## License

MIT

## Author Information

This role was created for the OnPrem AlmaLinux Lab environment.

- GitHub: [onprem-almalinux-lab](https://github.com/onprem-almalinux-lab)
