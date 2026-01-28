# Linux Administration Knowledge Check

55 essential topics organized by skill level (Junior → Senior). Each topic covers
what you should understand, why it matters in production, and where to practice
in this lab.

---

## 1. Linux Fundamentals (Junior Level)

### Q1: Describe the Linux boot process from power-on to login prompt.

**What you should understand:**
- POST -> UEFI/BIOS -> GRUB2 bootloader -> kernel + initramfs -> systemd (PID 1)
- systemd reads the default target (`multi-user.target` or `graphical.target`)
- systemd starts units in dependency order
- Login prompt via `getty` or display manager

**Practice this in:** `docs/break-fix.md` (boot troubleshooting scenarios)

---

### Q2: Explain systemd targets and how they replace SysV runlevels.

**What you should understand:**
- Targets are grouping units that define system states
- `multi-user.target` = runlevel 3 (text mode, network, services)
- `graphical.target` = runlevel 5 (multi-user + GUI)
- `rescue.target` = runlevel 1 (single user, root shell)
- `emergency.target` = minimal root shell (no services)
- `systemctl get-default` / `systemctl set-default`
- `systemctl isolate rescue.target` to switch at runtime

**Practice this in:** `docs/cheat-sheet.md` (Services section)

---

### Q3: What is the difference between a process, a thread, and a daemon?

**What you should understand:**
- Process: independent execution unit with its own memory space (PID)
- Thread: lightweight execution unit within a process, shares memory
- Daemon: background process with no controlling terminal (typically started by systemd)
- `ps aux` shows processes, thread count visible with `ps -eLf`
- Daemons often have "d" suffix: `httpd`, `sshd`, `chronyd`

**Practice this in:** `docs/cheat-sheet.md` (Processes section)

---

### Q4: Explain file permissions, including special bits (setuid, setgid, sticky).

**What you should understand:**
- Standard: rwx for owner/group/other (octal: 755, 644)
- setuid (4xxx): execute as file owner (e.g., `/usr/bin/passwd`)
- setgid (2xxx): execute as file group, or inherit group on directories
- Sticky bit (1xxx): only owner can delete files in directory (e.g., `/tmp`)
- `chmod`, `chown`, `chgrp` for modification
- ACLs with `setfacl` / `getfacl` for granular permissions
- `umask` sets default permissions for new files (typical: 022 -> files 644, dirs 755)

**Practice this in:** `docs/cheat-sheet.md` (Users/Groups section)

---

### Q5: How does package management work on RHEL/AlmaLinux? Explain dnf vs yum.

**What you should understand:**
- `dnf` replaced `yum` in RHEL 8+ (`yum` is a symlink to `dnf`)
- Repositories defined in `/etc/yum.repos.d/`
- `dnf install`, `dnf update`, `dnf remove`, `dnf search`, `dnf info`
- `dnf history` for transaction history and rollback
- `dnf module` for modular content (AppStream)
- RPM is the underlying package format: `rpm -qi`, `rpm -ql`, `rpm -qf`
- `dnf provides /usr/bin/dig` to find which package owns a file

**Practice this in:** General lab knowledge (all nodes use dnf)

---

### Q6: What is the difference between hard links and soft (symbolic) links?

**What you should understand:**
- Hard link: same inode, same data blocks, cannot cross filesystems, cannot link to directories
- Soft link: separate inode pointing to a path, can cross filesystems, can link to directories
- `ln file hardlink` (hard), `ln -s file softlink` (soft)
- Deleting the original: hard links still work (data persists), soft links become dangling
- `ls -li` shows inode numbers, hard link count

**Practice this in:** General Linux knowledge

---

## 2. Storage & Filesystems (Mid Level)

### Q7: Walk through creating an LVM volume from scratch.

**What you should understand:**
1. Create partition: `fdisk /dev/sdb` -> type 8e (Linux LVM)
2. Create PV: `pvcreate /dev/sdb1`
3. Create VG: `vgcreate vg_data /dev/sdb1`
4. Create LV: `lvcreate -L 10G -n lv_app vg_data`
5. Create filesystem: `mkfs.xfs /dev/vg_data/lv_app`
6. Mount: `mount /dev/vg_data/lv_app /data`
7. Persist: add to `/etc/fstab`

**Practice this in:** `docs/lvm-labs.md`, `docs/cheat-sheet.md` (Storage section)

---

### Q8: How do you extend a logical volume online?

**What you should understand:**
- `lvextend -L +5G /dev/vg_data/lv_app` or `-l +100%FREE`
- For XFS: `xfs_growfs /mountpoint` (XFS can only grow, never shrink)
- For ext4: `resize2fs /dev/vg_data/lv_app`
- Both can be done online (no unmount needed)
- Verify with `df -h` and `lvs`

**Practice this in:** `docs/lvm-labs.md`

---

### Q9: Compare XFS and ext4. When would you choose each?

**What you should understand:**
- XFS: default on RHEL/AlmaLinux, excellent large file performance, parallel I/O, cannot shrink
- ext4: mature, can shrink (offline only), better for many small files, lower overhead
- XFS: better for databases, media, large file workloads
- ext4: better for boot partitions, general purpose, when shrink capability is needed
- Both support online growth

**Practice this in:** `docs/lvm-labs.md`

---

### Q10: Explain NFS exports and the difference between root_squash and no_root_squash.

**What you should understand:**
- `root_squash` (default): remote root mapped to `nfsnobody` -- prevents remote root from having full access
- `no_root_squash`: remote root retains root privileges -- use only for trusted admin hosts
- `/etc/exports` format: `/path client(options)`
- `exportfs -arv` to apply changes
- SELinux booleans: `nfs_export_all_rw`, `use_nfs_home_dirs`

**Practice this in:** `docs/nfs.md`

---

### Q11: Describe RAID levels 0, 1, 5, 6, and 10. When would you use each?

**What you should understand:**
- RAID 0: striping, no redundancy, max performance, any disk failure = data loss
- RAID 1: mirroring, 50% capacity, simple redundancy for boot/OS drives
- RAID 5: striping + distributed parity, min 3 disks, 1 disk failure tolerance
- RAID 6: striping + double parity, min 4 disks, 2 disk failure tolerance
- RAID 10: mirrored stripes, min 4 disks, best performance + redundancy, 50% capacity
- RAID 10 for databases (performance + redundancy), RAID 6 for archival (capacity + safety)

**Practice this in:** General Linux knowledge

---

## 3. Networking (Mid Level)

### Q12: Describe the TCP three-way handshake and how you would troubleshoot connection issues.

**What you should understand:**
- SYN -> SYN-ACK -> ACK
- Troubleshooting: `ss -tnp` to check connections, `tcpdump` to capture packets
- Connection refused = port not listening; timeout = firewall blocking or host unreachable
- `telnet host port` or `nc -zv host port` to test connectivity

**Practice this in:** `docs/cheat-sheet.md` (Networking section)

---

### Q13: Explain DNS resolution flow from a client request to response.

**What you should understand:**
1. Application calls `getaddrinfo()` -> NSS (Name Service Switch)
2. Check `/etc/hosts` first (per `/etc/nsswitch.conf`)
3. Query resolvers listed in `/etc/resolv.conf`
4. Recursive resolver checks cache, then walks hierarchy: root -> TLD -> authoritative
5. Response cached by resolver with TTL
6. `dig +trace` shows the full resolution path
7. Lab runs its own BIND server on alma10-admin for `lab.local` domain

**Practice this in:** `docs/dns-bind.md`

---

### Q14: How do firewalld zones work? Describe a scenario using multiple zones.

**What you should understand:**
- Zones define trust levels: drop, block, public, external, dmz, work, home, internal, trusted
- Interfaces and sources are assigned to zones
- Default zone applies to traffic not matching any zone rule
- Scenario: `public` zone for external interface (SSH only), `internal` zone for management VLAN (all services), `dmz` zone for web servers (HTTP/HTTPS only)
- Lab example: bastion gets HTTP/HTTPS, db gets mysql/nfs/mountd/rpc-bind

**Practice this in:** `docs/cheat-sheet.md` (Firewall section), Puppet `profile::firewall`

---

### Q15: How would you troubleshoot "I can't reach the server" reported by a user?

**What you should understand:**
1. **Is it DNS?** `dig hostname` / `nslookup hostname`
2. **Is it network?** `ping hostname` (ICMP) / `traceroute hostname`
3. **Is it the port?** `ss -tlnp` on server / `nc -zv host port` from client
4. **Is it the firewall?** `firewall-cmd --list-all` on server
5. **Is it SELinux?** `ausearch -m avc -ts recent`
6. **Is it the service?** `systemctl status httpd` / `journalctl -u httpd`
7. Work from the bottom of the network stack up: physical -> IP -> TCP -> application

**Practice this in:** `docs/break-fix.md`

---

## 4. Security (Mid-Senior Level)

### Q16: Explain SELinux modes and how you troubleshoot a denial.

**What you should understand:**
- Modes: Enforcing (denies + logs), Permissive (logs only), Disabled (off)
- `getenforce`, `setenforce 0/1`, persistent in `/etc/selinux/config`
- Troubleshooting flow:
  1. `ausearch -m avc -ts recent` to find the denial
  2. `sealert -a /var/log/audit/audit.log` for human-readable explanation
  3. Fix with: `semanage fcontext` + `restorecon`, `setsebool`, or `semanage port`
  4. Last resort: `audit2allow` to generate custom policy module
- Common lab scenarios: httpd serving from non-default directory, haproxy connecting to backends

**Practice this in:** `docs/break-fix.md`, `docs/cheat-sheet.md` (SELinux section)

---

### Q17: Describe Kerberos authentication flow.

**What you should understand:**
1. User runs `kinit username` -> sends AS-REQ to KDC
2. KDC returns AS-REP with Ticket Granting Ticket (TGT)
3. User presents TGT to request service ticket (TGS-REQ -> TGS-REP)
4. User presents service ticket to target service
5. Service validates ticket against its keytab
- Key components: KDC (Key Distribution Center), krb5.conf, keytabs, principals
- SSSD caches tickets for offline authentication

**Practice this in:** `docs/kerberos.md`

---

### Q18: How would you set up centralized authentication with LDAP and SSSD?

**What you should understand:**
- LDAP server (OpenLDAP or 389 Directory Server) stores user/group data
- SSSD on clients caches identity and authentication
- `authselect` configures PAM and NSS to use SSSD
- SSSD domain config: `id_provider = ldap`, `auth_provider = ldap` (or `krb5`)
- `oddjob-mkhomedir` creates home directories on first login
- Test with: `getent passwd ldapuser`, `id ldapuser`, `su - ldapuser`

**Practice this in:** `docs/ldap-sssd.md`

---

### Q19: What SSH hardening measures would you implement?

**What you should understand:**
- Disable root login: `PermitRootLogin no`
- Disable password auth: `PasswordAuthentication no` (key-only)
- Change default port (debatable -- security through obscurity)
- Use `AllowUsers` or `AllowGroups` to restrict access
- Set `MaxAuthTries 3`, `LoginGraceTime 30`
- Use `fail2ban` or `pam_faillock` for brute-force protection
- Use SSH keys with passphrase, consider SSH certificates for large fleets
- `ClientAliveInterval 300`, `ClientAliveCountMax 2` for idle timeouts

**Practice this in:** General security knowledge

---

### Q20: Explain sudo configuration best practices.

**What you should understand:**
- Edit with `visudo` (syntax checking prevents lockouts)
- Use `/etc/sudoers.d/` drop-in files for modular config
- Principle of least privilege: grant specific commands, not `ALL`
- Use groups: `%wheel ALL=(ALL) ALL`
- Log sudo usage: configured by default in `/var/log/secure`
- `sudo -l` to list user's allowed commands
- Never: `NOPASSWD: ALL` for non-service accounts
- Consider: `Defaults timestamp_timeout=5` for session timeout

**Practice this in:** General security knowledge

---

## 5. High Availability (Senior Level)

### Q21: Explain Pacemaker/Corosync architecture and key concepts.

**What you should understand:**
- Corosync: cluster communication layer (messaging, membership, quorum)
- Pacemaker: cluster resource manager (starts/stops/monitors resources)
- Resources: primitives (single service), groups (ordered set), clones (run everywhere)
- Constraints: location (where), order (sequence), colocation (together/apart)
- Quorum: majority of nodes must agree for cluster to operate
- `pcs cluster setup`, `pcs status`, `pcs resource create`

**Practice this in:** `docs/pacemaker.md`

---

### Q22: What is STONITH and why is it critical for HA clusters?

**What you should understand:**
- STONITH = "Shoot The Other Node In The Head" (fencing)
- Purpose: ensure a failed node is truly dead before another takes over
- Without fencing: split-brain scenario where both nodes think they own the resource
- Split-brain with shared storage = data corruption
- Methods: IPMI/iLO, PDU power cycling, SBD (watchdog-based), cloud API fencing
- Lab uses SBD (Storage-Based Death) for Vagrant/KVM environments

**Practice this in:** `docs/pacemaker.md`

---

### Q23: Describe HAProxy load balancing algorithms and when to use each.

**What you should understand:**
- `roundrobin`: rotate requests evenly -- default, good for stateless services
- `leastconn`: send to server with fewest connections -- good for long-lived connections
- `source`: hash client IP for sticky sessions -- good for session affinity
- `uri`: hash URI for cache optimization
- Health checks: `option httpchk GET /health` for application-level checks
- Lab config: roundrobin with two app backends (`alma10-app`, `alma10-app2`)
- Stats page on port 8404 for real-time monitoring

**Practice this in:** `docs/haproxy.md`

---

### Q24: How do you design for zero-downtime deployments?

**What you should understand:**
- Blue/green deployment: two identical environments, switch traffic
- Rolling update: update one node at a time behind load balancer
- Canary deployment: route small percentage of traffic to new version
- HAProxy can drain connections: set server to `drain` state
- Database migrations: backward-compatible changes, run migration before code deployment
- Health check endpoints: remove node from LB before update, add back after verification

**Practice this in:** `docs/haproxy.md`, `docs/pacemaker.md`

---

## 6. Automation & IaC (Senior Level)

### Q25: Describe the Puppet role/profile pattern with an example.

**What you should understand:**
- Role = business purpose (one per node): `role::app_server`
- Profile = technology stack (composable): `profile::base`, `profile::web`
- site.pp classifies nodes to roles
- Data lives in Hiera, not in code
- Lab example: `role::db_server` includes `profile::base`, `profile::db`, `profile::firewall`, `profile::nfs_server`, `profile::monitoring`

**Practice this in:** `docs/puppet.md` (Section 4.2)

---

### Q26: How do you manage Puppet environments and promote changes?

**What you should understand:**
- r10k maps Git branches to Puppet environments
- Feature branch = test environment
- Merge to main = production environment
- Puppetfile pins module versions for reproducibility
- CI validates syntax, lint, and rspec-puppet on every PR
- Agents can be targeted to specific environments: `puppet agent -t --environment=staging`

**Practice this in:** `docs/puppet.md` (Section 4.6), `docs/gitops.md`

---

### Q27: Explain Ansible idempotency and give examples of idempotent vs non-idempotent tasks.

**What you should understand:**
- Idempotent: running the task multiple times produces the same result
- Idempotent: `dnf` module (`state: present`), `file` module, `service` module
- Non-idempotent: `command`/`shell` modules (unless using `creates`/`when`)
- Non-idempotent: `command: dnf install -y httpd` (use `dnf` module instead)
- The `changed` status should only appear when actual changes are made
- `--check --diff` mode validates idempotency

**Practice this in:** General Ansible knowledge, `docs/gitops.md`

---

### Q28: How do you handle Terraform state in a team environment?

**What you should understand:**
- Remote state backend (S3 + DynamoDB for AWS)
- State locking prevents concurrent modifications
- Never commit state to Git (contains secrets)
- Separate state files per environment
- `terraform state mv` for refactoring without destroy/recreate
- `terraform import` for adopting existing resources
- Break glass: `terraform force-unlock` for stuck locks

**Practice this in:** `docs/terraform-aws.md` (Section 4.8)

---

### Q29: Describe your Terraform module design approach.

**What you should understand:**
- Single responsibility: VPC module, security groups module, compute module
- Inputs via variables (with descriptions and types), outputs for chaining
- Consistent tagging via `merge(var.tags, local_tags)`
- Pin provider versions, use `required_version` for Terraform version
- Environments compose modules with different parameters
- Lab example: VPC -> Security Groups -> EC2 Cluster -> RDS

**Practice this in:** `docs/terraform-aws.md` (Section 4.6)

---

### Q30: What is your GitOps workflow for infrastructure changes?

**What you should understand:**
- All changes go through Git PRs
- CI runs lint, validate, plan on every PR
- Plan output posted as PR comment for review
- Apply only happens from CI/CD after merge to main
- No manual `terraform apply` from laptops
- Drift detection via scheduled plan jobs

**Practice this in:** `docs/gitops.md`

---

### Q31: How do you test Puppet code? Ansible roles?

**What you should understand:**
- Puppet: `puppet parser validate` (syntax), `puppet-lint` (style), `rspec-puppet` (unit), Beaker/Litmus (acceptance), PDK (wraps all)
- Ansible: `yamllint` (YAML syntax), `ansible-lint` (best practices), `--syntax-check`, Molecule (integration testing with containers)
- Both: CI/CD pipelines running tests on every PR

**Practice this in:** `docs/puppet.md` (Section 5), `docs/gitops.md` (Section 4.3)

---

### Q32: Explain Hiera's lookup hierarchy and merge strategies.

**What you should understand:**
- Hiera looks up data in order from most specific to least specific
- Lab hierarchy: per-node data (`nodes/%{certname}.yaml`) -> common (`common.yaml`)
- Merge strategies: `first` (default -- first match wins), `unique` (array dedup), `hash` (merge hashes), `deep` (recursive hash merge)
- Automatic parameter binding: `profile::base::packages` auto-binds to class parameter `$packages`
- `lookup()` function for explicit lookups with merge strategy control

**Practice this in:** `docs/puppet.md` (Section 4.3)

---

## 7. Monitoring & Troubleshooting (Senior Level)

### Q33: Describe your monitoring stack and justify your choices.

**What you should understand:**
- Prometheus for metrics (pull-based, PromQL, cloud-native, CNCF)
- Grafana for visualization (dashboards, alerting UI)
- Alertmanager for alert routing (severity-based, inhibition, silencing)
- node_exporter on all nodes for OS metrics
- ELK or Loki for log aggregation
- Why Prometheus: powerful query language, integrates with K8s service discovery, scalable via federation

**Practice this in:** `docs/monitoring.md`

---

### Q34: Write PromQL to detect disk usage above 80%.

**What you should understand:**
```promql
(1 - (node_filesystem_avail_bytes{fstype!="tmpfs"} /
      node_filesystem_size_bytes{fstype!="tmpfs"})) * 100 > 80
```
- Filter out tmpfs to avoid false positives
- Use `avail_bytes` (not `free_bytes`) which accounts for reserved blocks
- Set `for: 5m` to avoid transient spikes triggering alerts

**Practice this in:** `docs/monitoring.md` (Section 4.3)

---

### Q35: What is the difference between metrics, logs, and traces?

**What you should understand:**
- Metrics: numeric time-series (CPU at 85%), cheap to store, good for alerting
- Logs: event records ("user X failed login"), rich context, expensive at scale
- Traces: request path through distributed systems (latency per hop)
- Metrics tell you SOMETHING is wrong, logs tell you WHAT, traces tell you WHERE
- Tools: Prometheus (metrics), ELK/Loki (logs), Jaeger/Zipkin (traces)

**Practice this in:** `docs/monitoring.md` (Section 1)

---

### Q36: How do you handle alert fatigue?

**What you should understand:**
- Every alert must be actionable (if no action needed, it is a dashboard metric)
- Severity routing: critical pages on-call, warnings go to channel
- Alert inhibition: node down suppresses all service alerts for that node
- Regular alert review meetings to tune or remove noisy alerts
- Runbooks linked to every alert
- Aggregate: one alert for "3 of 100 nodes have high disk" not 3 separate alerts

**Practice this in:** `docs/monitoring.md` (Section 8)

---

### Q37: A web server is slow. Walk through your troubleshooting methodology.

**What you should understand:**
1. **Reproduce**: Can I see the slowness? `curl -o /dev/null -s -w "%{time_total}" http://server/`
2. **Check metrics**: CPU, memory, disk I/O, network on the server (`top`, `vmstat`, `iostat`)
3. **Check application**: `systemctl status httpd`, `journalctl -u httpd`, Apache access/error logs
4. **Check network**: `ss -tnp` for connection count, `tcpdump` for packet analysis
5. **Check downstream**: database query performance, NFS latency
6. **Check resources**: `df -h` (disk full?), `free -m` (swapping?), `dmesg` (OOM?)
7. **Narrow down**: is it all requests or specific endpoints? Single client or all clients?

**Practice this in:** `docs/break-fix.md`, `docs/monitoring.md`

---

### Q38: Describe the incident response process.

**What you should understand:**
1. Detect: alert fires from monitoring
2. Acknowledge: on-call responds within SLA
3. Assess: severity (P1-P4), impact (users affected)
4. Communicate: status page update, stakeholder notification
5. Investigate: dashboards, logs, recent changes
6. Mitigate: restore service (rollback, restart, failover)
7. Resolve: root cause fix
8. Post-mortem: blameless review, timeline, root cause, action items
- Use structured communication templates during incidents
- Track Mean Time To Detect (MTTD) and Mean Time To Resolve (MTTR)

**Practice this in:** `docs/monitoring.md` (Section 8)

---

### Q39: How would you debug an OOM (Out Of Memory) kill?

**What you should understand:**
- Check `dmesg | grep -i oom` for OOM killer messages
- `journalctl -k | grep -i oom` for kernel log OOM events
- `/var/log/messages` may also contain OOM records
- The log shows which process was killed, how much memory it was using
- `free -m` to check current memory state
- `/proc/meminfo` for detailed memory breakdown
- Prevention: set memory limits in systemd (`MemoryMax=`), tune `vm.overcommit_memory`
- For containers: check cgroup memory limits

**Practice this in:** `docs/break-fix.md`

---

## 8. Containers (Senior Level)

### Q40: Why did RHEL move from Docker to Podman?

**What you should understand:**
- Docker daemon is a single point of failure running as root
- If daemon crashes, all containers die
- Podman uses fork/exec model: each container is an independent process
- Rootless by default: reduced attack surface
- Native systemd integration via Quadlet
- OCI-compatible: `alias docker=podman` works
- No daemon socket (no `/var/run/docker.sock` privilege escalation risk)

**Practice this in:** `docs/containers.md`

---

### Q41: How do rootless containers work?

**What you should understand:**
- User namespaces map container UID 0 to unprivileged host UID
- `/etc/subuid` and `/etc/subgid` define subordinate UID ranges
- Networking via `slirp4netns` or `pasta` (no root needed for bridges)
- Storage in `~/.local/share/containers/`
- Limitations: cannot bind ports < 1024 (without sysctl), no `--privileged`

**Practice this in:** `docs/containers.md` (Section 4.3)

---

### Q42: What is Quadlet and when would you use it?

**What you should understand:**
- Systemd integration for containers via `.container` unit files
- Placed in `/etc/containers/systemd/` (root) or `~/.config/containers/systemd/` (user)
- systemd generator converts to proper unit files at boot
- Use for: persistent services, auto-start at boot, health checks, auto-updates
- Replaced deprecated `podman generate systemd`
- Supports pods via `.pod` files

**Practice this in:** `docs/containers.md` (Section 4.5)

---

### Q43: Explain the container runtime landscape: Docker, containerd, CRI-O, Podman.

**What you should understand:**
- Docker: original, daemon-based, full lifecycle management
- containerd: extracted from Docker, used by most cloud Kubernetes
- CRI-O: purpose-built for Kubernetes CRI, minimal, used by OpenShift
- Podman: daemonless, rootless, CLI-compatible with Docker, not a daemon
- OCI runtime: `runc` or `crun` at the bottom, creates namespaces/cgroups
- For K8s: CRI-O or containerd (both implement CRI interface)
- For dev/ops: Podman (Docker-compatible, rootless)

**Practice this in:** `docs/containers.md` (Section 4.8)

---

## 9. Architecture & Leadership (Lead Level)

### Q44: You are tasked with designing infrastructure for a new datacenter. Walk through your approach.

**What you should understand:**
- Requirements gathering: workload types, capacity needs, compliance requirements
- Network design: spine-leaf topology, VLANs, firewalls, load balancers, DNS
- Compute: standardized server hardware, bare metal vs virtualization
- Storage: SAN/NAS, tiered storage (SSD for hot, HDD for warm/cold)
- Identity: centralized auth (LDAP/AD + Kerberos), SSH key management
- Automation from day one: PXE boot -> Puppet/Ansible -> monitoring registration
- Monitoring: Prometheus + Grafana, ELK for logs, alerting to PagerDuty
- HA: redundant everything (dual power, dual network, clustered services)
- Security: SELinux enforcing, CIS benchmarks, vulnerability scanning
- DR: backup strategy (RPO/RTO), offsite replication, documented runbooks

**Practice this in:** Overall lab architecture, `docs/pacemaker.md`, `docs/monitoring.md`

---

### Q45: Describe how you would migrate 500 servers from on-prem to AWS.

**What you should understand:**
- Discovery: inventory all servers, dependencies, data volumes
- Assessment: which workloads are lift-and-shift, which need re-architecting
- Landing zone: VPC design, Transit Gateway, Direct Connect for hybrid period
- Migration waves: group by application, migrate least critical first
- Tools: AWS Application Migration Service (MGN) for server migration, DMS for databases
- Terraform for infrastructure, Puppet/Ansible for config management on EC2
- Testing: parallel run period, compare on-prem and cloud behavior
- Cutover: DNS failover, decommission on-prem after validation period
- Post-migration: right-sizing, cost optimization, managed services adoption

**Practice this in:** `docs/terraform-aws.md`

---

### Q46: Build vs buy: when do you build custom tooling vs adopt existing solutions?

**What you should understand:**
- Buy (or adopt open source) when the problem is well-understood and tools exist
- Build when requirements are unique to your organization and no tool fits
- Consider: maintenance burden, hiring/training, vendor lock-in, integration effort
- Examples:
  - Buy: monitoring (Prometheus/Datadog), CI/CD (GitHub Actions/Jenkins), database (RDS)
  - Build: custom deployment orchestration specific to your architecture, internal developer platform
- Decision framework: If > 2 engineers maintaining custom tooling, evaluate buying
- Total Cost of Ownership matters more than license cost

**Practice this in:** `docs/terraform-aws.md` (Section 7 -- RDS vs self-hosted)

---

### Q47: How do you approach capacity planning?

**What you should understand:**
- Baseline: monitor current utilization (CPU, memory, disk, network) over time
- Trending: project growth based on historical data and business plans
- Headroom: maintain 30-40% headroom for burst capacity
- Right-sizing: identify over-provisioned resources
- Cost modeling: reserved instances vs on-demand, data transfer costs
- Review cycle: quarterly capacity review meetings with engineering and product
- Automation: auto-scaling for variable workloads (cloud), additional VMs (on-prem)
- Signals: lead time for hardware procurement (12+ weeks for on-prem)

**Practice this in:** `docs/terraform-aws.md` (Section 4.11 -- Cost Management)

---

### Q48: Describe your disaster recovery planning approach.

**What you should understand:**
- Define RPO (Recovery Point Objective -- max data loss) and RTO (Recovery Time Objective -- max downtime)
- Classification: Tier 1 (RPO 0, RTO 1hr), Tier 2 (RPO 1hr, RTO 4hr), Tier 3 (RPO 24hr, RTO 24hr)
- Backup strategy: 3-2-1 rule (3 copies, 2 media types, 1 offsite)
- Database: streaming replication to standby, point-in-time recovery capability
- Infrastructure: IaC (Terraform/Puppet) can rebuild environment from code
- DR testing: quarterly DR drills, documented runbooks, measure actual RTO
- Automation: failover automation for Tier 1 systems, manual runbooks for Tier 2/3
- Communication: DR communication plan (who to notify, escalation paths)

**Practice this in:** `docs/pacemaker.md`, `docs/terraform-aws.md`

---

### Q49: How do you handle technical debt in infrastructure?

**What you should understand:**
- Track it: maintain a technical debt register with impact and effort estimates
- Categorize: security debt (urgent), operational debt (next quarter), cosmetic debt (backlog)
- Allocate time: 20% of sprint capacity for debt reduction
- Measure impact: incidents caused by debt, time spent working around debt
- Prioritize: debt that causes incidents or slows delivery gets addressed first
- Prevention: code review, CI/CD gates, documentation requirements
- Examples: upgrading from CentOS 7 to AlmaLinux 9, migrating from hand-managed configs to Puppet

**Practice this in:** General leadership knowledge

---

### Q50: A team member wants to use a new tool (e.g., Kubernetes). How do you evaluate this?

**What you should understand:**
- Define the problem: what are we solving that current tools cannot?
- Evaluate fit: does the complexity match our team's capacity?
- POC: time-boxed proof of concept with defined success criteria
- Total cost: licensing, training, hiring, migration effort, ongoing maintenance
- Risk assessment: what happens if the tool fails or is abandoned?
- Team readiness: do we have expertise or need to hire/train?
- Migration path: can we adopt incrementally or is it all-or-nothing?
- Decision framework: present findings with recommendation, let the team decide

**Practice this in:** General leadership knowledge

---

## Bonus Topics

### Q51: Explain the difference between `systemctl mask` and `systemctl disable`.

**What you should understand:**
- `disable`: removes symlinks from `*.wants/` directories -- service will not start at boot but CAN be started manually
- `mask`: creates a symlink to `/dev/null` -- service CANNOT be started at all (even manually or as a dependency)
- Use `mask` when you absolutely need to prevent a service from starting (e.g., `iptables` when using `firewalld`)

---

### Q52: What happens when you run `chmod 4755 /usr/bin/myapp`?

**What you should understand:**
- Sets setuid bit (4) + rwxr-xr-x (755)
- When any user executes `myapp`, it runs with the file OWNER's privileges (typically root)
- Security risk if the program has vulnerabilities
- Example: `/usr/bin/passwd` is setuid root so users can change their own password

---

### Q53: Explain the purpose of /etc/nsswitch.conf.

**What you should understand:**
- Name Service Switch configuration -- determines lookup order for system databases
- `passwd: files sss` = check local files first, then SSSD (LDAP)
- `hosts: files dns myhostname` = check /etc/hosts first, then DNS
- Critical for LDAP/SSSD integration -- if `sss` is not listed, LDAP users cannot log in
- `authselect` manages this file on RHEL 8+

---

### Q54: How do you rotate logs in Linux?

**What you should understand:**
- `logrotate`: `/etc/logrotate.conf` and `/etc/logrotate.d/`
- Options: `daily/weekly/monthly`, `rotate N` (keep N files), `compress`, `missingok`, `notifempty`
- `postrotate` script to send HUP signal to service
- journald: `SystemMaxUse=` in `/etc/systemd/journald.conf` or `journalctl --vacuum-size=100M`
- Critical for preventing disk full incidents

---

### Q55: What is the difference between `su` and `su -`?

**What you should understand:**
- `su user`: switch user but keep current environment (PATH, HOME, etc.)
- `su - user`: switch user AND load the target user's environment (login shell)
- `su -` is almost always what you want
- `sudo -i`: equivalent to `su - root` (interactive login shell as root)
- `sudo -s`: root shell with current user's environment
