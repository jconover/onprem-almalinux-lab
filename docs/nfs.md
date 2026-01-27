# NFS

## Overview

Network File System (NFS) provides shared storage across multiple Linux
servers. In enterprise environments, NFS is used for shared application data,
centralized home directories, and content distribution. This lab configures
NFSv4 on the db node as the server, with app and admin nodes as clients.
It covers both persistent mounts via fstab and on-demand mounts via autofs.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  NFS Architecture                                            │
│                                                              │
│  db (192.168.60.13)  ── NFS Server                           │
│    │  /srv/nfs/shared  ── shared application data (rw)       │
│    │  /srv/nfs/home    ── centralized home directories (rw)  │
│    │                                                         │
│    ├──▶ app   (192.168.60.12) ── NFS Client                  │
│    │     /mnt/nfs/shared  ── fstab persistent mount          │
│    │     /home/remote/*   ── autofs on-demand mount          │
│    │                                                         │
│    ├──▶ app2  (192.168.60.14) ── NFS Client                  │
│    │     /mnt/nfs/shared  ── fstab persistent mount          │
│    │     /home/remote/*   ── autofs on-demand mount          │
│    │                                                         │
│    └──▶ admin (192.168.60.11) ── NFS Client                  │
│          /mnt/nfs/shared  ── fstab persistent mount          │
│          /home/remote/*   ── autofs on-demand mount          │
└──────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Packages

**Server (db node):**

```bash
sudo dnf install -y nfs-utils
```

**Clients (app, app2, admin nodes):**

```bash
sudo dnf install -y nfs-utils autofs
```

### Firewall (db node -- server only)

```bash
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-services
```

No firewall changes needed on clients (NFS clients initiate outbound
connections).

### SELinux Booleans

**Server (db node):**

```bash
sudo setsebool -P nfs_export_all_rw on
sudo setsebool -P nfs_export_all_ro on
```

**Clients (app, app2, admin):**

```bash
sudo setsebool -P use_nfs_home_dirs on
```

Verify:

```bash
getsebool -a | grep nfs
```

---

## Step-by-Step Setup

### Server Configuration (db node)

#### Step 1 -- Create Export Directories

```bash
sudo mkdir -p /srv/nfs/shared
sudo mkdir -p /srv/nfs/home

# Set ownership
sudo chown nobody:nobody /srv/nfs/shared
sudo chmod 2775 /srv/nfs/shared

# Create test content
echo "NFS shared data" | sudo tee /srv/nfs/shared/readme.txt
```

#### Step 2 -- Configure /etc/exports

```bash
sudo tee /etc/exports << 'EOF'
/srv/nfs/shared  192.168.60.0/24(rw,sync,no_subtree_check,no_root_squash)
/srv/nfs/home    192.168.60.0/24(rw,sync,no_subtree_check,root_squash)
EOF
```

**Export options explained:**

| Option | Meaning |
|--------|---------|
| `rw` | Read-write access |
| `sync` | Write data to disk before replying (safer, slightly slower) |
| `no_subtree_check` | Disables subtree checking (improves reliability) |
| `no_root_squash` | Remote root has root privileges on the share |
| `root_squash` | Remote root is mapped to nobody (default, more secure) |

#### Step 3 -- Export and Start NFS

```bash
sudo exportfs -arv
```

Expected output:

```
exporting 192.168.60.0/24:/srv/nfs/home
exporting 192.168.60.0/24:/srv/nfs/shared
```

```bash
sudo systemctl enable --now nfs-server
sudo systemctl status nfs-server
```

#### Step 4 -- Verify Exports

```bash
sudo exportfs -v
showmount -e localhost
```

Expected:

```
Export list for localhost:
/srv/nfs/home   192.168.60.0/24
/srv/nfs/shared 192.168.60.0/24
```

### Client Configuration -- fstab Persistent Mount (app, app2, admin)

#### Step 5 -- Create Mount Point and Test Mount

```bash
sudo mkdir -p /mnt/nfs/shared

# Test mount manually first
sudo mount -t nfs 192.168.60.13:/srv/nfs/shared /mnt/nfs/shared

# Verify
df -hT /mnt/nfs/shared
cat /mnt/nfs/shared/readme.txt
```

#### Step 6 -- Add to /etc/fstab

```bash
echo '192.168.60.13:/srv/nfs/shared  /mnt/nfs/shared  nfs  defaults,_netdev  0 0' | sudo tee -a /etc/fstab
```

**The `_netdev` option is critical.** It tells systemd to wait for the
network to be available before attempting the mount. Without it, the system
may hang at boot trying to mount an unreachable NFS share.

Verify fstab:

```bash
sudo umount /mnt/nfs/shared
sudo mount -a
df -hT /mnt/nfs/shared
```

### Client Configuration -- autofs for Home Directories (app, app2, admin)

#### Step 7 -- Configure autofs

autofs mounts shares on demand when a user accesses them and unmounts them
after a timeout period. This is ideal for home directories.

Edit `/etc/auto.master` (or create `/etc/auto.master.d/home.autofs`):

```bash
sudo tee /etc/auto.master.d/home.autofs << 'EOF'
/home/remote  /etc/auto.home
EOF
```

Create the map file `/etc/auto.home`:

```bash
sudo tee /etc/auto.home << 'EOF'
*  -rw,sync  192.168.60.13:/srv/nfs/home/&
EOF
```

This wildcard entry mounts `/srv/nfs/home/USERNAME` on the server to
`/home/remote/USERNAME` on the client when any user accesses their directory.

#### Step 8 -- Start autofs

```bash
sudo systemctl enable --now autofs
sudo systemctl status autofs
```

#### Step 9 -- Test autofs

Create a test user home directory on the server:

```bash
# On db node:
sudo mkdir -p /srv/nfs/home/testuser1
sudo chown 10001:10001 /srv/nfs/home/testuser1
echo "Hello from NFS home" | sudo tee /srv/nfs/home/testuser1/welcome.txt
```

On the client:

```bash
ls /home/remote/testuser1/
# autofs will mount the directory and show: welcome.txt

cat /home/remote/testuser1/welcome.txt
# Output: Hello from NFS home

mount | grep auto
# Shows the automounted path
```

---

## Verification / Testing

### From any client node

```bash
# Check persistent mount
df -hT | grep nfs

# Test read/write on shared
touch /mnt/nfs/shared/testfile_$(hostname)
ls -la /mnt/nfs/shared/

# Check autofs
ls /home/remote/testuser1/

# Check NFS statistics
nfsstat -c    # client statistics
nfsstat -m    # mount options
```

### From the server (db node)

```bash
# Check active exports
sudo exportfs -v

# Check connected clients
sudo ss -tnp | grep 2049

# NFS server statistics
nfsstat -s
```

---

## Troubleshooting

### "Permission denied" on mount

```bash
# On client:
showmount -e 192.168.60.13
# If empty: check /etc/exports on server

# On server:
sudo exportfs -v
cat /etc/exports
# Ensure client IP or subnet is listed
```

### "No route to host" on mount

```bash
# Firewall issue on server
ssh db "sudo firewall-cmd --list-services"
# Must include: nfs, mountd, rpc-bind
```

### "Stale file handle" error

```bash
# Unmount and remount
sudo umount -f /mnt/nfs/shared
sudo mount -a

# If umount hangs, use lazy unmount
sudo umount -l /mnt/nfs/shared
```

### SELinux blocking NFS access

```bash
# Check denials
sudo ausearch -m avc -ts recent | grep nfs

# Common fix:
sudo setsebool -P nfs_export_all_rw on     # on server
sudo setsebool -P use_nfs_home_dirs on      # on client
```

### autofs not mounting

```bash
sudo systemctl status autofs
sudo journalctl -u autofs --no-pager -n 20

# Test manually
sudo automount -f -v
# Then access the path in another terminal to see debug output
```

### Files created by root show as nobody:nobody

This is root_squash in action. Remote root is mapped to nobody. Either:
- Use `no_root_squash` in /etc/exports (less secure)
- Create files as the owning user, not root

### NFS mount hangs at boot

Add `_netdev` to fstab mount options. If the NFS server is unreachable
at boot, the system will hang without this option. Also consider
`bg` (background) option to allow boot to continue while retrying.

---

## Architecture Decision Rationale

### Why NFSv4 over NFSv3?

| Factor | NFSv3 | NFSv4 |
|--------|-------|-------|
| Port | Multiple (2049 + dynamic) | Single port 2049 |
| Firewall | Complex (rpcbind, mountd, statd) | Simple (just 2049) |
| Security | AUTH_SYS (UID-based) | Supports Kerberos (RPCSEC_GSS) |
| State | Stateless | Stateful (better locking) |

NFSv4 is the default on AlmaLinux 9/10. However, `mountd` and `rpc-bind`
are still needed for `showmount` and backward compatibility.

### root_squash vs no_root_squash

- **root_squash (default):** Remote root is mapped to `nobody`. Use for
  home directories and shared data where root-level write access is not
  needed. This is the secure default.
- **no_root_squash:** Remote root retains root privileges on the share.
  Required when Ansible or other automation runs as root and needs to write
  to the NFS share. Use sparingly and limit to trusted subnets.

### fstab vs autofs

- **fstab:** Simple, always mounted, good for data shares that are
  continuously accessed. Downside: boot may hang if NFS server is down.
- **autofs:** Mounts on demand, times out after idle period. Ideal for home
  directories where many users exist but few are active simultaneously.
  Reduces server load and avoids boot-hang issues.

---

## Interview Talking Points

**Q: What firewall ports does NFS require?**
A: NFSv4 primarily uses TCP 2049. For full compatibility (showmount, NFSv3
fallback), also open mountd (20048) and rpc-bind (111). In firewalld, add
services: nfs, mountd, rpc-bind.

**Q: Explain root_squash.**
A: root_squash maps UID 0 (root) from NFS clients to the nobody user on the
server. This prevents a compromised client's root from having root access
to the NFS share. It is enabled by default and should only be disabled for
specific automation use cases on trusted networks.

**Q: What is the `_netdev` mount option?**
A: It tells systemd that the mount depends on network availability. Without
it, the system may try to mount the NFS share before the network is up,
causing a boot hang.

**Q: How does autofs differ from a persistent NFS mount?**
A: autofs mounts filesystems on demand when accessed and unmounts them after
a configurable timeout. This reduces server connections and avoids boot
issues. Persistent mounts (fstab) are always available but require the
server to be reachable at boot time.

**Q: How do you troubleshoot "permission denied" on an NFS mount?**
A: Check /etc/exports on the server (is the client allowed?). Check firewall
rules. Check SELinux booleans (nfs_export_all_rw on server,
use_nfs_home_dirs on client). Use showmount -e to verify exports are
visible from the client.

**Q: How would you integrate NFS with Kerberos for security?**
A: Use NFSv4 with `sec=krb5p` in exports for encryption and integrity.
Configure keytabs for nfs/hostname principals on both server and client.
This replaces UID-based trust with cryptographic authentication.
