# PRD: Enterprise On-Prem Linux Administration Lab

## Purpose

This project is a hands-on lab environment that demonstrates enterprise Linux
administration skills relevant to a **Linux Administrator** role. It uses
AlmaLinux 9/10 (RHEL-compatible) on KVM/libvirt with Vagrant and Ansible to
simulate a realistic on-prem data center with multiple nodes, enterprise
services, and troubleshooting scenarios.

The goal is twofold:
1. **Interview preparation** -- brush up on core Linux admin competencies
   (systemd, SELinux, firewalld, storage, networking, identity, HA)
2. **Portfolio artifact** -- a public repo that demonstrates practical knowledge
   to hiring managers and technical interviewers

---

## Current State

### What exists today

| Component | Status | Notes |
|-----------|--------|-------|
| Vagrant multi-node cluster (alma9 + alma10) | Done | 4 nodes each: bastion, admin, app, db |
| Provisioning script (`provision-common.sh`) | Done | Baseline packages, SELinux enforcing, firewalld, chrony |
| Ansible structure (`site.yml`, inventory, 4 roles) | Done | common, firewall, web, db -- minimal but functional |
| `docs/` stubs | Stubbed | 8 files, all 1-2 line placeholders (except ldap-sssd) |

### What is missing

- All `docs/` files are placeholder stubs with no real content
- Ansible roles have no handlers, variables, templates, or defaults
- No alma9 Ansible inventory
- No advanced services implemented (LDAP, Kerberos, DNS, NFS, HAProxy, Pacemaker)
- No break/fix lab exercises written out
- No TLS/certificate setup
- No monitoring or log aggregation

---

## Plan

Work is organized into phases. Each phase builds on the previous one and maps
to skills commonly tested in Linux admin interviews.

### Phase 1 -- Fill Out Core Documentation (`docs/`)

Flesh out every stub in `docs/` into a proper lab guide. Each doc should
follow a consistent format:

```
# Service Name

## Overview
What this service does and why it matters in enterprise environments.

## Architecture
Which lab nodes are involved and their roles (server vs client).

## Prerequisites
Packages, firewall ports, SELinux booleans needed.

## Step-by-Step Setup
Numbered commands to install, configure, and verify the service.

## Verification / Testing
How to confirm the service works end-to-end.

## Troubleshooting
Common failure modes and how to diagnose them (journalctl, ausearch, ss, etc.)

## Interview Talking Points
Key concepts and commands a candidate should be able to discuss.
```

Priority order for docs (highest interview value first):

1. **`lvm-labs.md`** -- LVM is asked about constantly. Cover PV/VG/LV creation,
   extending volumes online, snapshots, restoring from snapshots, `pvs/vgs/lvs`
   output interpretation, XFS vs ext4 resize differences.

2. **`break-fix.md`** -- Troubleshooting is the core of any admin interview.
   Write 6-8 discrete scenarios:
   - SELinux denial blocking httpd from serving content in a non-default dir
   - firewalld misconfiguration preventing client access
   - Full `/var` filesystem causing service failures
   - Failed systemd unit (bad ExecStart path, dependency issues)
   - Chrony/NTP drift or unreachable upstream
   - Broken DNS resolution (missing `/etc/resolv.conf` or firewall blocking 53)
   - Permission denied on NFS mount (root squash, UID mismatch)
   - MariaDB won't start (socket file, port conflict)

   Each scenario: symptoms, diagnostic commands, root cause, fix, prevention.

3. **`dns-bind.md`** -- Forward and reverse zone setup on admin node, all nodes
   use it as primary resolver. Cover `named.conf`, zone files, `dig`/`nslookup`
   verification, firewall port 53/tcp+udp, SELinux context for zone files.

4. **`nfs.md`** -- NFS server on db node, clients on app/admin. Cover
   `/etc/exports`, `exportfs -arv`, firewall services (`nfs`, `mountd`, `rpc-bind`),
   SELinux booleans (`nfs_export_all_rw`, `use_nfs_home_dirs`),
   autofs for on-demand mounting, fstab for persistent mounts.

5. **`ldap-sssd.md`** -- Already has the most content. Expand with full
   OpenLDAP server setup on db node, SSSD client config, `authselect`,
   `ldapsearch` verification, home directory auto-creation via `oddjob-mkhomedir`,
   SELinux booleans for LDAP.

6. **`kerberos.md`** -- KDC on admin node, integrate with SSSD. Cover
   `krb5.conf`, `kadmin.local`, keytab creation, `kinit`/`klist` verification,
   PAM/SSSD integration.

7. **`haproxy.md`** -- HAProxy on bastion node fronting the app node(s).
   Cover `haproxy.cfg`, frontend/backend definitions, health checks, stats page,
   firewall and SELinux (`haproxy_connect_any`), testing with `curl`.

8. **`pacemaker.md`** -- Two-node HA cluster (app + db or add a second app
   node). Cover `pcs cluster setup`, resources, constraints, fencing/STONITH
   (use sbd for lab), failover testing, `pcs status` interpretation.

### Phase 2 -- Harden Ansible Roles

Improve the existing Ansible roles to demonstrate real automation skill:

- **common role**: Add `handlers/main.yml` (restart chronyd, reload firewalld).
  Add `defaults/main.yml` for configurable package lists. Add a task to set
  the timezone and hostname.
- **firewall role**: Parameterize allowed services via `defaults/main.yml`
  so each host group opens only the ports it needs (http/https for app,
  mysql for db, etc.). Add zone assignment.
- **web role**: Add a Jinja2 template for `/etc/httpd/conf.d/vhost.conf`.
  Add a handler to restart httpd on config change. Add a smoke-test task
  using `uri` module.
- **db role**: Add `mysql_secure_installation` equivalent tasks. Add a
  template for `/etc/my.cnf.d/server.cnf`. Create an application database
  and user with `community.mysql` collection.

Add new roles:

- **dns role**: Deploy BIND with templated zone files
- **nfs role**: Export directories, configure clients
- **ldap role**: Deploy OpenLDAP with base DIT
- **haproxy role**: Deploy config with backend discovery from inventory

### Phase 3 -- Add New Lab Scenarios

Create additional doc pages for interview-relevant topics not yet covered:

- **`docs/systemd-deep-dive.md`** -- Custom unit files, timer units (cron
  replacement), journal filtering, resource limits (CPUQuota, MemoryMax),
  `systemctl mask` vs `disable`, analyzing boot with `systemd-analyze`.
- **`docs/selinux-deep-dive.md`** -- Policy booleans, `audit2allow`,
  `semanage fcontext`, `restorecon`, port labeling, custom file contexts,
  troubleshooting with `ausearch -m avc`.
- **`docs/networking.md`** -- `nmcli` connection management, bonding/teaming,
  VLANs, static routes, `/etc/hosts` management, `ss`/`ip`/`nmstatectl`.
- **`docs/user-management.md`** -- Local users/groups, password policies
  (`chage`, `/etc/login.defs`), sudo configuration, PAM modules, account
  lockout with `faillock`.
- **`docs/boot-process.md`** -- GRUB2 configuration, kernel parameters,
  rescue/emergency mode, `dracut`, resetting root password, boot target
  management (`multi-user.target` vs `graphical.target`).
- **`docs/backup-restore.md`** -- `tar`, `rsync`, LVM snapshots for
  consistent backups, `cron` scheduling, `anacron`, off-site considerations.

### Phase 4 -- Expand Infrastructure

- **Add alma9 inventory** to Ansible so both clusters can be managed
- **Add a second app node** to each cluster (alma10-app2 / alma9-app2)
  to enable real load balancing and HA labs
- **Add Vagrant provisioning for additional disks** on db nodes for LVM
  labs (can't practice LVM creation without unpartitioned disks)
- **Add Ansible Vault** for secrets (MariaDB passwords, LDAP bind DN, etc.)
- **Add a Makefile or justfile** at repo root with convenience targets:
  `make up-alma10`, `make destroy-all`, `make ansible-run`, etc.

### Phase 5 -- Polish and Interview Prep

- **Update `README.md`** with a topology diagram (ASCII or mermaid), quickstart
  instructions, and a skills matrix mapping each lab to interview topics
- **Add a `docs/cheat-sheet.md`** with rapid-fire commands grouped by topic
  (storage, networking, services, users, SELinux, firewall) for last-minute
  review before interviews
- **Add a `docs/interview-questions.md`** with common Linux admin interview
  questions and where in this lab each one is demonstrated
- **Tag releases** (v0.1 = current baseline, v0.2 = docs complete, etc.)

---

## Key Interview Topics Mapped to Lab Components

| Interview Topic | Lab Component | Doc File |
|----------------|---------------|----------|
| LVM / Storage | Vagrant extra disks + LVM labs | `lvm-labs.md` |
| SELinux | Enforcing mode on all nodes, troubleshooting | `break-fix.md`, `selinux-deep-dive.md` |
| firewalld | Per-service rules, zone management | `break-fix.md`, Ansible firewall role |
| systemd | Unit management, custom units, timers | `systemd-deep-dive.md`, `break-fix.md` |
| Networking | nmcli, bonding, DNS, static routes | `networking.md`, `dns-bind.md` |
| User Management | LDAP/SSSD, local users, sudo, PAM | `ldap-sssd.md`, `user-management.md` |
| Web Services | Apache httpd, vhosts, TLS | Ansible web role, `haproxy.md` |
| Databases | MariaDB admin, backup/restore | Ansible db role |
| High Availability | Pacemaker, HAProxy | `pacemaker.md`, `haproxy.md` |
| Automation | Ansible roles, playbooks, Jinja2 | `ansible/` directory |
| Troubleshooting | Break/fix scenarios | `break-fix.md` |
| DNS | BIND forward/reverse zones | `dns-bind.md` |
| NFS | Server/client, autofs, exports | `nfs.md` |
| Boot Process | GRUB2, rescue mode, dracut | `boot-process.md` |
| Backup | tar, rsync, LVM snapshots, cron | `backup-restore.md` |
| Kerberos / Auth | KDC, keytabs, SSSD integration | `kerberos.md` |

---

## Suggested Work Order

Start with **Phase 1** (docs). This has the highest ROI for interview prep
because writing the lab guides forces you to actually walk through each
procedure and solidify the knowledge. It also makes the repo look complete to
anyone reviewing it.

Within Phase 1, prioritize by interview frequency:
1. LVM (almost always asked)
2. Break/Fix troubleshooting (the "what would you do if..." questions)
3. DNS (fundamental networking knowledge)
4. NFS (common in enterprise environments)
5. LDAP/SSSD (identity management)
6. Kerberos (often paired with LDAP questions)
7. HAProxy (load balancing concepts)
8. Pacemaker (HA is a differentiator)

Phase 2 (Ansible hardening) is second priority -- it shows you don't just
run commands manually but can automate properly.

Phases 3-5 can be done as time permits and are more about depth and polish.

---

## Success Criteria

- Every `docs/` file has actionable, tested lab steps (not just theory)
- An interviewer cloning this repo can `vagrant up` and follow any lab guide
- You can explain every command in every doc from memory
- The Ansible automation actually converges cleanly on a fresh cluster
- Break/fix scenarios can be set up and solved in under 10 minutes each
