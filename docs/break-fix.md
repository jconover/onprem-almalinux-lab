# Break/Fix Labs

## Overview

Troubleshooting is the core skill that separates junior admins from senior ones. These
eight scenarios simulate real production failures covering SELinux, firewalld,
storage, systemd, time sync, DNS, NFS, and database services. Each scenario
includes symptoms, diagnostic steps, root cause, fix, and prevention.

An Ansible playbook (`break-fix-setup.yml`) injects each failure, and a
companion playbook (`break-fix-reset.yml`) reverts the node to a clean state.

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  Lab Cluster                                                   │
│                                                                │
│  bastion (192.168.60.10) ── jump host, test client             │
│  admin   (192.168.60.11) ── DNS (BIND), Chrony, Kerberos KDC  │
│  app     (192.168.60.12) ── Apache httpd                       │
│  app2    (192.168.60.14) ── Apache httpd                       │
│  db      (192.168.60.13) ── MariaDB, NFS server                │
│                                                                │
│  Scenarios target various nodes as noted in each section.      │
└────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- All five nodes running with baseline provisioning complete
- SELinux in enforcing mode on all nodes (`getenforce` returns `Enforcing`)
- firewalld running on all nodes
- Core services installed: httpd, mariadb-server, named, nfs-utils, chrony

### Diagnostic Packages

```bash
sudo dnf install -y setroubleshoot-server audit policycoreutils-python-utils
```

### Automation Playbooks

```bash
# Inject a specific scenario
ansible-playbook ansible/break-fix-setup.yml -e scenario=selinux_httpd

# Reset all nodes to clean state
ansible-playbook ansible/break-fix-reset.yml
```

---

## Scenario 1: SELinux Denial on httpd (Non-Standard Port)

**Node:** app (192.168.60.12)
**Injected fault:** httpd configured to listen on port 8888 without SELinux port label.

### Symptoms

- `systemctl start httpd` fails
- `curl http://app:8888` returns connection refused

### Diagnostic Steps

```bash
# Check service status
sudo systemctl status httpd
# Output shows: "Permission denied: AH00072: make_sock: could not bind to address"

# Check SELinux denials
sudo ausearch -m avc -ts recent
# Shows: avc: denied { name_bind } for src=httpd dest=8888

# Get human-readable explanation
sudo sealert -a /var/log/audit/audit.log | head -40

# Check what ports httpd is allowed to bind
sudo semanage port -l | grep http_port_t
# http_port_t tcp 80, 81, 443, 488, 8008, 8009, 8443, 9000
```

### Root Cause

SELinux policy only permits httpd to bind to ports labeled `http_port_t`.
Port 8888 is not in that list.

### Fix

```bash
sudo semanage port -a -t http_port_t -p tcp 8888
sudo systemctl restart httpd
curl http://localhost:8888
```

### Prevention

- Always check SELinux port labels when configuring non-standard ports
- Use `semanage port -l | grep SERVICE` before changing listen ports
- Add the `semanage` command to your Ansible role as a task

---

## Scenario 2: firewalld Misconfiguration (HTTP Service Removed)

**Node:** app (192.168.60.12)
**Injected fault:** http and https services removed from the public zone.

### Symptoms

- httpd is running (`systemctl status httpd` shows active)
- `curl http://localhost` works on the app node itself
- `curl http://app` from bastion times out or is refused

### Diagnostic Steps

```bash
# Verify httpd is running and listening
sudo ss -tlnp | grep :80
# Shows httpd listening on 0.0.0.0:80

# Check firewall rules
sudo firewall-cmd --list-all
# Notice: services line does NOT include http or https

# Test from bastion
ssh bastion "curl -m 5 http://192.168.60.12"
# Times out
```

### Root Cause

The `http` service was removed from the active firewalld zone, blocking
external TCP/80 traffic.

### Fix

```bash
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-services
```

### Prevention

- Use `--permanent` with all firewall-cmd changes to survive reboots
- Always follow `--permanent` with `--reload`
- Audit firewall rules in Ansible: use `ansible.posix.firewalld` module

---

## Scenario 3: Full /var Filesystem

**Node:** db (192.168.60.13)
**Injected fault:** /var filled to 100% with a large dummy file.

### Symptoms

- MariaDB fails to start: "No space left on device"
- `journalctl` may stop writing new entries
- `dnf` commands fail with write errors

### Diagnostic Steps

```bash
# Check disk usage
df -h /var
# Shows 100% used

# Find large files
sudo du -sh /var/* | sort -rh | head -10

# Find files created recently (the injected fault)
sudo find /var -type f -size +100M -mtime -1
# Reveals: /var/tmp/breakfix_filler.img

# Check if MariaDB can start
sudo systemctl start mariadb
sudo journalctl -u mariadb --no-pager -n 20
```

### Root Cause

A large file consumed all available space on /var, preventing MariaDB from
writing to its data directory or socket file.

### Fix

```bash
# Remove the offending file
sudo rm -f /var/tmp/breakfix_filler.img

# Verify space recovered
df -h /var

# Restart affected services
sudo systemctl start mariadb
sudo systemctl status mariadb
```

### Prevention

- Place /var on a separate LVM logical volume (standard enterprise practice)
- Configure monitoring alerts at 80% and 90% usage thresholds
- Use `logrotate` to manage log file sizes
- Set MariaDB `innodb_log_file_size` and binary log expiration

---

## Scenario 4: Failed systemd Unit

**Node:** app (192.168.60.12)
**Injected fault:** httpd unit override with invalid ExecStart path.

### Symptoms

- `systemctl start httpd` fails immediately
- `systemctl status httpd` shows "failed" with exit code

### Diagnostic Steps

```bash
# Check status
sudo systemctl status httpd
# Shows: Active: failed; ExecStart path not found

# Check journal for details
sudo journalctl -u httpd --no-pager -n 30
# Shows: httpd.service: Failed at step EXEC

# Check the unit file
sudo systemctl cat httpd
# Reveals an override file with wrong ExecStart path

# List overrides
sudo systemd-delta --type=overridden
```

### Root Cause

A drop-in override file in `/etc/systemd/system/httpd.service.d/` contains
an invalid `ExecStart` path (e.g., `/usr/sbin/httpd_broken`).

### Fix

```bash
# Remove the bad override
sudo rm /etc/systemd/system/httpd.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl start httpd
sudo systemctl status httpd
```

### Prevention

- Use `systemctl edit SERVICE` to create overrides (validates syntax)
- Test changes with `systemd-analyze verify SERVICE.service`
- Use `systemctl daemon-reload` after any manual unit file edits
- Keep unit customizations in version control (Ansible templates)

---

## Scenario 5: Chrony/NTP Time Drift (Breaks Kerberos)

**Node:** admin (192.168.60.11)
**Injected fault:** System clock manually set 10 minutes ahead, chrony stopped.

### Symptoms

- Kerberos authentication fails: "Clock skew too great"
- `kinit` returns `KRB5KRB_AP_ERR_SKEW`
- Certificate validation may also fail

### Diagnostic Steps

```bash
# Check current time vs expected
date
timedatectl

# Check chrony status
sudo systemctl status chronyd
# Shows: inactive (dead)

# Check chrony sources
chronyc sources
# Shows: "506 Cannot talk to daemon"

# Verify time offset
chronyc tracking
```

### Root Cause

The chronyd service was stopped and the system clock was manually advanced.
Kerberos has a default maximum clock skew tolerance of 5 minutes.

### Fix

```bash
# Restart chrony
sudo systemctl start chronyd
sudo systemctl enable chronyd

# Force immediate sync
sudo chronyc makestep

# Verify time is correct
chronyc tracking
timedatectl

# Test Kerberos again
kinit admin
```

### Prevention

- Ensure chronyd is enabled and running on all nodes
- Monitor NTP sync status (chronyc tracking, check stratum)
- Set `makestep 1 3` in /etc/chrony.conf to allow large corrections at boot
- Never manually set the clock with `date -s` on production systems

---

## Scenario 6: Broken DNS Resolution (named Won't Start)

**Node:** admin (192.168.60.11)
**Injected fault:** Syntax error in zone file (missing dot after FQDN).

### Symptoms

- `systemctl start named` fails
- `dig @192.168.60.11 bastion.lab.local` returns SERVFAIL or times out
- All other nodes lose name resolution if admin is their DNS server

### Diagnostic Steps

```bash
# Check named status
sudo systemctl status named
sudo journalctl -u named --no-pager -n 30
# Shows: zone lab.local/IN: loading from master file failed

# Validate configuration
sudo named-checkconf /etc/named.conf
# Returns OK or shows config errors

# Validate zone file
sudo named-checkzone lab.local /var/named/lab.local.zone
# Shows: "dns_rdata_fromtext: near 'admin': not a valid name (check for missing dot)"
```

### Root Cause

A fully qualified domain name in the zone file is missing its trailing dot.
For example, `admin.lab.local` instead of `admin.lab.local.` -- BIND
interprets the former as `admin.lab.local.lab.local`.

### Fix

```bash
sudo vi /var/named/lab.local.zone
# Add trailing dot to the offending FQDN

# Validate
sudo named-checkzone lab.local /var/named/lab.local.zone

# Increment SOA serial number
# Restart
sudo systemctl restart named

# Test
dig @localhost bastion.lab.local
```

### Prevention

- Always validate zone files with `named-checkzone` before restarting named
- Use Ansible templates with `validate:` parameter
- Increment SOA serial on every change
- Use `$ORIGIN` directive to reduce FQDN errors

---

## Scenario 7: NFS Permission Denied

**Node:** db (192.168.60.13) as server, app (192.168.60.12) as client
**Injected fault:** Multiple layers -- export removed, firewall service removed,
SELinux boolean disabled.

### Symptoms

- `mount -t nfs db:/srv/nfs/shared /mnt/nfs` fails with "Permission denied"
  or "No route to host"

### Diagnostic Steps

```bash
# On the client (app):
showmount -e 192.168.60.13
# If "No route to host": firewall issue on db
# If "Export list empty": export config issue on db

# On the server (db):
# Check exports
cat /etc/exports
sudo exportfs -v
# Check if the export is listed

# Check firewall
sudo firewall-cmd --list-services | grep -E 'nfs|mountd|rpc-bind'

# Check SELinux
getsebool nfs_export_all_rw
getsebool nfs_export_all_ro

# Check SELinux denials
sudo ausearch -m avc -ts recent | grep nfs
```

### Root Cause

Three possible layers:
1. `/etc/exports` does not list the share or has wrong client subnet
2. firewalld does not have nfs, mountd, rpc-bind services open
3. SELinux boolean `nfs_export_all_rw` is set to off

### Fix

```bash
# On db node:

# 1. Fix exports
echo '/srv/nfs/shared 192.168.60.0/24(rw,sync,no_root_squash)' | sudo tee -a /etc/exports
sudo exportfs -arv

# 2. Fix firewall
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --reload

# 3. Fix SELinux
sudo setsebool -P nfs_export_all_rw on

# On app node:
sudo mount -t nfs 192.168.60.13:/srv/nfs/shared /mnt/nfs
```

### Prevention

- Layer your diagnostics: network first, then service, then permissions
- Test `showmount -e` from the client to isolate firewall vs export issues
- Include SELinux booleans in Ansible roles
- Document required firewall services per role

---

## Scenario 8: MariaDB Won't Start

**Node:** db (192.168.60.13)
**Injected fault:** Corrupt my.cnf (invalid directive), socket file directory
permissions changed.

### Symptoms

- `systemctl start mariadb` fails
- Applications that depend on MariaDB report "Can't connect to local
  MySQL server through socket"

### Diagnostic Steps

```bash
# Check status
sudo systemctl status mariadb
sudo journalctl -u mariadb --no-pager -n 40

# Check config file syntax
sudo mariadbd --help --verbose 2>&1 | head -5
# Shows: "unknown variable 'invalid_option=true'"

# Check socket directory
ls -la /var/lib/mysql/
ls -laZ /var/lib/mysql/  # check SELinux context too

# Check if another process holds the port
sudo ss -tlnp | grep 3306
```

### Root Cause

Two faults:
1. `/etc/my.cnf.d/server.cnf` contains an invalid directive that prevents
   MariaDB from starting
2. The socket directory `/var/lib/mysql` has wrong ownership or permissions

### Fix

```bash
# 1. Fix config
sudo vi /etc/my.cnf.d/server.cnf
# Remove or correct the invalid directive

# 2. Fix permissions
sudo chown -R mysql:mysql /var/lib/mysql
sudo chmod 755 /var/lib/mysql

# 3. Restore SELinux contexts
sudo restorecon -Rv /var/lib/mysql

# 4. Start and verify
sudo systemctl start mariadb
sudo systemctl status mariadb
sudo mysqladmin ping
```

### Prevention

- Validate config changes: `mariadbd --help --verbose 2>&1 | grep -i error`
- Use Ansible templates for config files with validation tasks
- Never manually chmod database directories; use `restorecon` after changes
- Keep regular backups with `mariadb-dump` or `mariabackup`

---

## Verification / Testing

After resolving each scenario, confirm the service is fully operational:

```bash
# Scenario 1: SELinux httpd
curl http://app:8888

# Scenario 2: Firewall
ssh bastion "curl http://app"

# Scenario 3: Full /var
df -h /var && sudo systemctl is-active mariadb

# Scenario 4: systemd unit
sudo systemctl is-active httpd

# Scenario 5: Chrony
chronyc tracking && kinit admin

# Scenario 6: DNS
dig @192.168.60.11 bastion.lab.local +short

# Scenario 7: NFS
mount | grep nfs && touch /mnt/nfs/test

# Scenario 8: MariaDB
sudo mysqladmin ping && mysql -e "SELECT 1"
```

---

## Troubleshooting

### General Diagnostic Workflow

1. **Check the service:** `systemctl status SERVICE`
2. **Read the journal:** `journalctl -u SERVICE --no-pager -n 50`
3. **Check SELinux:** `ausearch -m avc -ts recent`
4. **Check firewall:** `firewall-cmd --list-all`
5. **Check network:** `ss -tlnp`, `ping`, `curl`
6. **Check disk:** `df -h`, `du -sh /var/*`
7. **Check permissions:** `ls -laZ`, `namei -l /path/to/file`

### Key Diagnostic Commands Reference

| Command | Purpose |
|---------|---------|
| `ausearch -m avc -ts recent` | Recent SELinux denials |
| `sealert -a /var/log/audit/audit.log` | Human-readable SELinux analysis |
| `journalctl -u SERVICE -p err` | Service errors only |
| `journalctl -b -p err` | All errors since boot |
| `ss -tlnp` | TCP listening sockets with process |
| `systemctl list-units --failed` | All failed units |
| `systemd-analyze blame` | Slow-starting services |
| `firewall-cmd --list-all` | Current firewall rules |
| `getenforce` | SELinux mode |
| `sestatus` | Full SELinux status |

---

## Architecture Decision Rationale

### Why inject multiple fault layers per scenario?

Real production outages are rarely single-cause. By combining SELinux,
firewall, and config faults, these labs train the habit of checking all
layers rather than stopping at the first fix.

### Why use Ansible for break/fix injection?

Automation ensures scenarios are reproducible and consistent. The setup
playbook can inject specific scenarios by tag, and the reset playbook
guarantees a clean slate without re-provisioning the entire VM.

### Why these specific eight scenarios?

They map to the most common production scenarios: "The web server is down..."
and "Users cannot connect to...". Each scenario also tests
knowledge of a different subsystem (SELinux, firewall, storage, systemd,
time, DNS, NFS, databases).

---

## Key Concepts to Master

### Systematic Troubleshooting Methodology

Follow a systematic approach: identify symptoms, check service status
with systemctl, read journal logs, verify SELinux (ausearch), check firewall
rules, test network connectivity with ss/curl, and verify disk space with
df. Work from the most likely cause to the least.

### When a Web Server is Running but Clients Cannot Connect

First, verify the service is listening on the expected port (ss -tlnp).
Then check firewalld rules. Then check SELinux if the port is non-standard.
Then test from the local host vs remote to isolate network vs service issues.

### Handling a Full Filesystem in Production

Immediately identify and remove or compress the largest unnecessary files
(du -sh, find -size). If it is /var, check if logs are the culprit and
configure logrotate. Long-term: move /var to its own LVM volume and set
up monitoring alerts at 80% usage.

### Diagnosing SELinux Denials

Run `ausearch -m avc -ts recent` to see raw denials, then `sealert` for
human-readable analysis. The output typically tells you exactly what boolean
to set or what context to apply. Never set SELinux to permissive as a fix.

### When a Service Fails to Start

Run `systemctl status SERVICE` for the immediate error message, then
`journalctl -u SERVICE --no-pager -n 50` for full context. Check for
override files with `systemctl cat SERVICE`.
