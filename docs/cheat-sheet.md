# Linux Admin Cheat Sheet

Quick-reference commands grouped by category for last-minute interview prep.
Each entry includes the command, a brief description, and commonly used flags.

---

## Storage

### Partitioning

```bash
# fdisk -- MBR partition management (< 2TB disks)
fdisk /dev/sdb                    # Interactive partition editor
fdisk -l /dev/sdb                 # List partitions on a disk
fdisk -l                          # List all disks and partitions

# gdisk -- GPT partition management (> 2TB disks, modern standard)
gdisk /dev/sdb                    # Interactive GPT partition editor
gdisk -l /dev/sdb                 # List GPT partitions

# parted -- Works with both MBR and GPT, supports scripting
parted /dev/sdb print             # Show partition table
parted /dev/sdb mklabel gpt      # Create GPT label
parted /dev/sdb mkpart primary xfs 0% 100%   # Create partition using full disk
parted -s /dev/sdb mkpart primary 1MiB 10GiB # Scripted (non-interactive)
```

### LVM (Logical Volume Manager)

```bash
# Physical Volume operations
pvcreate /dev/sdb1                # Initialize PV
pvs                               # List PVs (short)
pvdisplay                         # List PVs (detailed)
pvremove /dev/sdb1                # Remove PV

# Volume Group operations
vgcreate vg_data /dev/sdb1 /dev/sdc1  # Create VG from PVs
vgs                               # List VGs (short)
vgdisplay                         # List VGs (detailed)
vgextend vg_data /dev/sdd1       # Add PV to VG
vgreduce vg_data /dev/sdc1       # Remove PV from VG

# Logical Volume operations
lvcreate -L 10G -n lv_app vg_data         # Create 10GB LV
lvcreate -l 100%FREE -n lv_app vg_data    # Use all free space
lvs                               # List LVs (short)
lvdisplay                         # List LVs (detailed)
lvextend -L +5G /dev/vg_data/lv_app       # Extend by 5GB
lvextend -l +100%FREE /dev/vg_data/lv_app # Extend to fill VG
lvreduce -L 5G /dev/vg_data/lv_app        # Reduce to 5GB (DANGEROUS -- backup first)
lvremove /dev/vg_data/lv_app              # Remove LV

# LVM snapshots
lvcreate -s -L 2G -n snap_app /dev/vg_data/lv_app  # Create snapshot
lvconvert --merge /dev/vg_data/snap_app             # Restore from snapshot
```

### Filesystems

```bash
# Create filesystems
mkfs.xfs /dev/vg_data/lv_app     # XFS (default for RHEL/AlmaLinux)
mkfs.ext4 /dev/vg_data/lv_app    # ext4

# Resize filesystems (after lvextend)
xfs_growfs /mountpoint            # Grow XFS (online, XFS only grows -- never shrinks)
resize2fs /dev/vg_data/lv_app    # Grow/shrink ext4

# Disk usage
df -h                             # Filesystem usage (human-readable)
df -i                             # Inode usage
du -sh /var/log                   # Directory size
du -sh /var/log/*                 # Size of each item in directory
du -sh --max-depth=1 /            # Top-level directory sizes

# Device information
lsblk                             # Block devices tree view
lsblk -f                          # Show filesystem types and UUIDs
blkid                             # Block device attributes (UUID, TYPE)
blkid /dev/sdb1                   # Specific device

# Mount operations
mount /dev/vg_data/lv_app /data   # Mount filesystem
mount -o remount,ro /data         # Remount read-only
mount -a                          # Mount all from /etc/fstab
umount /data                      # Unmount
```

### /etc/fstab Format

```
# <device>                                <mountpoint>  <type>  <options>        <dump> <pass>
/dev/mapper/vg_data-lv_app                /data         xfs     defaults         0      0
UUID=abc12345-def6-7890-abcd-ef1234567890 /data         xfs     defaults         0      0
alma10-db:/srv/nfs/shared                 /mnt/shared   nfs     defaults,_netdev 0      0
```

---

## Networking

### IP and Interface Management

```bash
# ip command (replaces ifconfig)
ip addr show                      # Show all interfaces and IPs
ip addr show eth0                 # Show specific interface
ip addr add 192.168.1.100/24 dev eth0     # Add IP (temporary)
ip addr del 192.168.1.100/24 dev eth0     # Remove IP
ip link show                      # Show link-layer info
ip link set eth0 up               # Bring interface up
ip link set eth0 down             # Bring interface down

# Routing
ip route show                     # Show routing table
ip route add 10.0.0.0/8 via 192.168.1.1  # Add static route (temporary)
ip route del 10.0.0.0/8                   # Delete route
ip route get 8.8.8.8             # Show route to specific destination

# Socket statistics (replaces netstat)
ss -tlnp                          # TCP listening sockets with process info
ss -ulnp                          # UDP listening sockets
ss -s                             # Socket statistics summary
ss -tnp state established         # Established TCP connections
ss -tnp dst 192.168.1.1          # Connections to specific destination
```

### NetworkManager (nmcli)

```bash
# Connection management
nmcli con show                    # List all connections
nmcli con show eth0               # Show connection details
nmcli con up eth0                 # Activate connection
nmcli con down eth0               # Deactivate connection

# Create/modify connections
nmcli con add type ethernet con-name static-eth0 ifname eth0 \
  ipv4.addresses 192.168.1.100/24 ipv4.gateway 192.168.1.1 \
  ipv4.dns "8.8.8.8 8.8.4.4" ipv4.method manual
nmcli con mod eth0 ipv4.dns-search "lab.local"
nmcli con mod eth0 +ipv4.dns "1.1.1.1"  # Add DNS server

# Device management
nmcli dev status                  # Show device status
nmcli dev wifi list               # List WiFi networks
```

### Firewall

```bash
# firewall-cmd basics
firewall-cmd --state                        # Check if running
firewall-cmd --list-all                     # Show all rules (default zone)
firewall-cmd --list-all --zone=public       # Show rules for specific zone
firewall-cmd --get-active-zones             # Show active zones
firewall-cmd --get-default-zone             # Show default zone
firewall-cmd --get-zones                    # List all available zones

# Add/remove services and ports
firewall-cmd --add-service=http             # Allow HTTP (runtime only)
firewall-cmd --add-service=http --permanent # Allow HTTP (persistent)
firewall-cmd --remove-service=http --permanent  # Remove HTTP
firewall-cmd --add-port=8080/tcp --permanent    # Allow specific port
firewall-cmd --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" service name="ssh" accept' --permanent

# Apply permanent changes
firewall-cmd --reload                       # Reload to apply --permanent rules

# Zone management
firewall-cmd --zone=dmz --change-interface=eth1 --permanent
firewall-cmd --zone=internal --add-source=192.168.60.0/24 --permanent
```

### DNS and Network Diagnostics

```bash
# DNS lookup
dig example.com                   # Full DNS query
dig example.com +short            # Just the answer
dig @8.8.8.8 example.com         # Query specific DNS server
dig -x 192.168.1.1               # Reverse DNS lookup
dig example.com MX                # Query specific record type
nslookup example.com              # Simple lookup

# Network diagnostics
ping -c 4 192.168.1.1            # Ping with count
traceroute 8.8.8.8               # Trace route
mtr 8.8.8.8                      # Combined ping + traceroute
nmap -sT 192.168.1.1             # TCP port scan
nmap -sV 192.168.1.1 -p 22,80   # Service version detection
curl -v http://localhost/         # HTTP request (verbose)
curl -o /dev/null -s -w "%{http_code}" http://localhost/  # Just HTTP status code

# Packet capture
tcpdump -i eth0                   # Capture all on interface
tcpdump -i eth0 port 80          # Capture HTTP traffic
tcpdump -i eth0 host 192.168.1.1 # Capture traffic to/from host
tcpdump -i eth0 -w capture.pcap  # Write to file
tcpdump -r capture.pcap          # Read from file

# netstat (legacy, use ss instead)
netstat -tlnp                     # TCP listening sockets
netstat -an                       # All connections, numeric
```

---

## Services (systemd)

```bash
# Service management
systemctl start httpd             # Start service
systemctl stop httpd              # Stop service
systemctl restart httpd           # Restart service
systemctl reload httpd            # Reload config (no restart)
systemctl enable httpd            # Enable at boot
systemctl disable httpd           # Disable at boot
systemctl enable --now httpd      # Enable and start
systemctl status httpd            # Show status
systemctl is-active httpd         # Check if running (exit code)
systemctl is-enabled httpd        # Check if enabled (exit code)
systemctl mask httpd              # Prevent starting (even manually)
systemctl unmask httpd            # Reverse mask
systemctl list-units --type=service                 # List loaded services
systemctl list-units --type=service --state=running # List running services
systemctl list-unit-files --type=service            # List all installed services

# Targets (runlevels)
systemctl get-default             # Show default target
systemctl set-default multi-user.target   # Set default (non-graphical)
systemctl isolate rescue.target   # Switch to rescue mode

# Journal / Logs
journalctl -u httpd               # Logs for specific unit
journalctl -u httpd --since "1 hour ago"  # Time-filtered
journalctl -u httpd -f            # Follow (tail)
journalctl -b                     # Current boot
journalctl -b -1                  # Previous boot
journalctl --since "2024-01-01" --until "2024-01-02"
journalctl -p err                 # Priority: emerg/alert/crit/err/warning/notice/info/debug
journalctl --disk-usage           # Journal disk usage
journalctl --vacuum-size=100M     # Trim journal to 100MB

# System analysis
systemd-analyze                   # Boot time
systemd-analyze blame             # Slowest units during boot
systemd-analyze critical-chain    # Critical path during boot
```

---

## SELinux

```bash
# Status
getenforce                        # Current mode: Enforcing/Permissive/Disabled
sestatus                          # Detailed SELinux status
setenforce 0                      # Set permissive (temporary, until reboot)
setenforce 1                      # Set enforcing (temporary)

# File contexts
ls -Z /var/www/html/              # Show SELinux context of files
semanage fcontext -l | grep httpd # List file context rules for httpd
semanage fcontext -a -t httpd_sys_content_t '/srv/web(/.*)?'  # Add context rule
restorecon -Rv /srv/web/          # Apply context rules recursively

# Port labeling
semanage port -l | grep http      # List port labels for HTTP
semanage port -a -t http_port_t -p tcp 8080  # Allow httpd on port 8080

# Booleans
getsebool -a | grep httpd         # List httpd-related booleans
setsebool -P httpd_can_network_connect on     # Allow httpd network connections
setsebool -P haproxy_connect_any on           # Allow haproxy any connection
setsebool -P nfs_export_all_rw on             # Allow NFS read-write exports

# Troubleshooting
ausearch -m avc -ts recent        # Search recent AVC denials
ausearch -m avc -c httpd          # AVC denials for httpd
sealert -a /var/log/audit/audit.log   # Human-readable analysis
audit2allow -a                    # Generate allow rules from denials
audit2allow -a -M mypolicy       # Create custom policy module
semodule -i mypolicy.pp          # Install custom policy
```

---

## Users and Groups

```bash
# User management
useradd jsmith                    # Create user
useradd -m -s /bin/bash -G wheel jsmith  # Create with home, shell, group
usermod -aG wheel jsmith          # Add to supplementary group
usermod -s /sbin/nologin jsmith   # Change shell (disable login)
userdel jsmith                    # Delete user
userdel -r jsmith                 # Delete user + home directory
passwd jsmith                     # Set password
passwd -l jsmith                  # Lock account
passwd -u jsmith                  # Unlock account

# Group management
groupadd devops                   # Create group
groupmod -n newname oldname       # Rename group
groupdel devops                   # Delete group
groups jsmith                     # Show user's groups
id jsmith                         # Show UID, GID, groups
getent passwd jsmith              # Query NSS (works with LDAP/SSSD)
getent group devops               # Query group

# Password policy
chage -l jsmith                   # Show password aging info
chage -M 90 jsmith               # Max password age: 90 days
chage -m 7 jsmith                # Min days between changes: 7
chage -W 14 jsmith               # Warn 14 days before expiry
chage -E 2025-12-31 jsmith       # Account expires on date
chage -d 0 jsmith                # Force password change on next login

# /etc/login.defs -- system-wide password defaults
# PASS_MAX_DAYS   90
# PASS_MIN_DAYS   7
# PASS_WARN_AGE   14
```

---

## Processes

```bash
# Process listing
ps aux                            # All processes (BSD format)
ps -ef                            # All processes (System V format)
ps -eo pid,ppid,user,%cpu,%mem,cmd --sort=-%cpu | head   # Custom format, sorted
ps aux --forest                   # Process tree

# Top / htop
top                               # Interactive process monitor
  # Inside top: P=sort CPU, M=sort memory, k=kill, q=quit
htop                              # Enhanced interactive monitor

# Process control
kill PID                          # Send SIGTERM (graceful)
kill -9 PID                       # Send SIGKILL (forced)
kill -HUP PID                     # Send SIGHUP (reload config)
killall httpd                     # Kill by name
pkill -f "python script.py"      # Kill by pattern

# Process priority
nice -n 10 command                # Start with lower priority (10)
renice -n 5 -p PID               # Change priority of running process

# Process search
pgrep -la httpd                   # Find processes by name
pgrep -u jsmith                   # Find processes by user

# Open files and ports
lsof                              # List all open files
lsof -i :80                       # What is using port 80
lsof -u jsmith                    # Files opened by user
lsof +D /var/log                  # Files open in directory

# System call tracing
strace -p PID                     # Trace running process
strace -e trace=network command   # Trace network syscalls
strace -c command                 # Count syscalls (summary)
```

---

## Logs

```bash
# journalctl (see systemd section above for full options)
journalctl -f                     # Follow all logs
journalctl -u sshd -p warning     # SSH warnings and above
journalctl _SYSTEMD_UNIT=sshd.service  # Alternative unit syntax

# Traditional log files
/var/log/messages                 # General system log
/var/log/secure                   # Authentication log
/var/log/audit/audit.log          # SELinux audit log
/var/log/cron                     # Cron job log
/var/log/maillog                  # Mail log
/var/log/boot.log                 # Boot messages
/var/log/dnf.log                  # Package manager log
/var/log/httpd/access_log         # Apache access log
/var/log/httpd/error_log          # Apache error log
/var/log/mariadb/mariadb.log      # MariaDB log

# Logger (send messages to syslog)
logger "Test message from command line"
logger -p auth.warning "Security event"
logger -t myapp "Application message"

# rsyslog configuration
# /etc/rsyslog.conf                # Main config
# /etc/rsyslog.d/*.conf            # Drop-in configs
# Forward to remote syslog:
# *.* @@remote-syslog:514          # TCP
# *.* @remote-syslog:514           # UDP
```

---

## Puppet

```bash
# Apply manifests
puppet apply manifests/site.pp                       # Apply site manifest
puppet apply --noop manifests/site.pp                # Dry run
puppet apply --verbose --debug manifests/site.pp     # Verbose output
puppet apply --modulepath=modules manifests/site.pp  # Custom module path
puppet apply --hiera_config=hiera.yaml manifests/site.pp  # Custom Hiera

# Agent operations (client-server mode)
puppet agent -t                   # Test run (one-time, verbose)
puppet agent -t --noop            # Test run in dry-run mode
puppet agent -t --environment=staging  # Use specific environment

# Resource inspection
puppet resource user root         # Show user 'root' as Puppet code
puppet resource service httpd     # Show service state
puppet resource package httpd     # Show package state

# Module management
puppet module list                # List installed modules
puppet module install puppetlabs-stdlib  # Install from Forge

# r10k
r10k puppetfile install --verbose # Install modules from Puppetfile
r10k deploy environment production --puppetfile  # Deploy specific environment

# Validation
puppet parser validate manifests/site.pp  # Syntax check
puppet epp validate templates/foo.epp     # EPP syntax check
puppet-lint manifests/                    # Style check

# Facts
facter                            # All facts
facter os.name                    # Specific fact
facter networking.ip              # Network IP
facter --json                     # JSON output
```

---

## Terraform

```bash
# Initialization
terraform init                    # Download providers, configure backend
terraform init -upgrade           # Upgrade provider versions

# Planning and applying
terraform plan                    # Show what will change
terraform plan -out=tfplan        # Save plan to file
terraform apply                   # Apply changes (prompts for confirmation)
terraform apply tfplan            # Apply saved plan (no prompt)
terraform apply -auto-approve     # Apply without confirmation
terraform destroy                 # Destroy all resources
terraform destroy -target=aws_instance.app  # Destroy specific resource

# Validation and formatting
terraform validate                # Validate configuration syntax
terraform fmt                     # Format files to standard style
terraform fmt -check              # Check formatting without changing
terraform fmt -diff               # Show formatting differences

# State management
terraform state list              # List all resources in state
terraform state show aws_instance.app     # Show specific resource
terraform state mv aws_instance.old aws_instance.new  # Rename resource
terraform state rm aws_instance.orphan    # Remove from state (keeps real resource)
terraform state pull              # Download state to stdout

# Import existing resources
terraform import aws_instance.app i-0123456789  # Import EC2 instance
terraform import module.vpc.aws_vpc.main vpc-0123  # Import into module

# Workspace management (alternative to directory-based envs)
terraform workspace list          # List workspaces
terraform workspace new staging   # Create workspace
terraform workspace select dev    # Switch workspace
terraform workspace show          # Current workspace

# Output
terraform output                  # Show all outputs
terraform output -raw vpc_id     # Show specific output (raw value)
terraform output -json            # JSON format

# Console (interactive expression evaluation)
terraform console                 # Start interactive console
```

---

## Containers (Podman / Buildah / Skopeo)

```bash
# Podman -- container runtime
podman run -d --name web -p 8080:80 httpd:2.4     # Run detached
podman run -it --rm alpine /bin/sh                  # Interactive, auto-remove
podman run -v /data:/data:Z httpd:2.4              # Volume with SELinux label
podman ps                         # Running containers
podman ps -a                      # All containers
podman logs web                   # Container logs
podman logs -f web                # Follow logs
podman inspect web                # Detailed container info (JSON)
podman exec -it web /bin/bash     # Execute command in container
podman stop web                   # Stop container
podman rm web                     # Remove container
podman images                     # List images
podman rmi httpd:2.4              # Remove image
podman pull docker.io/library/httpd:2.4  # Pull image
podman build -t myapp:1.0 .      # Build image from Containerfile
podman system prune -af           # Clean everything

# Podman pods
podman pod create --name mypod -p 8080:80   # Create pod
podman run -d --pod mypod httpd:2.4         # Add container to pod
podman pod list                   # List pods
podman pod stop mypod             # Stop pod
podman pod rm -f mypod            # Force remove pod

# Podman <-> Kubernetes
podman generate kube mypod > pod.yaml   # Generate K8s YAML
podman play kube pod.yaml               # Deploy from K8s YAML
podman play kube --down pod.yaml        # Tear down

# Buildah -- image building
buildah bud -t myapp:1.0 .       # Build from Containerfile
buildah from ubi9/ubi-minimal     # Start from base image (scriptable)
buildah images                    # List images
buildah push myapp:1.0 docker://registry.example.com/myapp:1.0

# Skopeo -- image inspection and transfer
skopeo inspect docker://docker.io/library/httpd:2.4   # Inspect remote image
skopeo copy docker://src docker://dst                   # Copy between registries
skopeo list-tags docker://docker.io/library/httpd       # List available tags

# Quadlet (systemd integration)
# Place files in ~/.config/containers/systemd/ (rootless) or /etc/containers/systemd/ (root)
systemctl --user daemon-reload    # Pick up new Quadlet files
systemctl --user start mycontainer  # Start Quadlet container
systemctl --user enable mycontainer # Enable at login
loginctl enable-linger $USER      # Enable user services at boot
```
