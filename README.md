# Enterprise On-Prem Linux Administration Lab

A **hands-on learning environment** for Junior Linux Admins developing enterprise skills through Senior Admin mentorship,
covering Puppet, Ansible, Terraform, RHEL 9/10, HA clustering, identity management,
containers, monitoring, and GitOps. Every component is runnable on a local
KVM/libvirt host using Vagrant.

---

## Network Topology

```
                         ┌─────────────────────────────────────────────────┐
                         │         KVM / libvirt Host                      │
                         │                                                 │
  AlmaLinux 10 Cluster   │   192.168.60.0/24                               │
  ═══════════════════    │                                                 │
                         │   ┌──────────────┐     ┌──────────────┐        │
                         │   │  bastion      │     │  admin        │        │
                         │   │  .60.10       │     │  .60.11       │        │
                         │   │  HAProxy      │     │  DNS (BIND)   │        │
                         │   │  Jump Host    │     │  KDC          │        │
                         │   └──────┬───────┘     │  Monitoring   │        │
                         │          │              └──────┬───────┘        │
                         │          │                     │                │
                         │   ┌──────┴─────────────────────┴───────┐       │
                         │   │           Private Network           │       │
                         │   └──┬──────────┬──────────┬───────────┘       │
                         │      │          │          │                    │
                         │   ┌──┴───┐  ┌───┴──┐  ┌───┴──┐                │
                         │   │ app   │  │ app2  │  │ db    │                │
                         │   │ .60.12│  │ .60.14│  │ .60.13│                │
                         │   │ httpd │  │ httpd │  │ MariaDB│               │
                         │   │       │  │       │  │ LDAP   │               │
                         │   │ HA ◄──┼──► HA    │  │ NFS    │               │
                         │   └───────┘  └───────┘  └───────┘               │
                         │     Pacemaker/Corosync     2x 5GB               │
                         │     VIP: .60.100           LVM disks            │
                         │                                                 │
  AlmaLinux 9 Cluster    │   192.168.70.0/24  (same layout, alma9- prefix) │
  ══════════════════     │                                                 │
                         └─────────────────────────────────────────────────┘
```

**5 VMs per cluster** | ~15 GB RAM each | Run one cluster at a time

---

## Skills Matrix

| Topic | Lab Component | Documentation |
|-------|---------------|---------------|
| **Puppet (role/profile, Hiera, r10k)** | `puppet/` -- 8 profiles, 4 roles, EPP templates, Hiera v5 | [`docs/puppet.md`](docs/puppet.md) |
| **Ansible (roles, vault, orchestration)** | `ansible/` -- 10 roles, site.yml, group_vars, break-fix playbooks | [`docs/break-fix.md`](docs/break-fix.md) |
| **Terraform (AWS VPC, EC2, RDS)** | `terraform/` -- 4 modules, dev+prod environments | [`docs/terraform-aws.md`](docs/terraform-aws.md) |
| **LVM (create, extend, snapshot, thin)** | Vagrant extra disks on db node (2x 5GB) | [`docs/lvm-labs.md`](docs/lvm-labs.md) |
| **DNS (BIND authoritative)** | `ansible/roles/dns/`, `puppet/modules/profile/manifests/dns.pp` | [`docs/dns-bind.md`](docs/dns-bind.md) |
| **NFS (server, fstab, autofs)** | `ansible/roles/nfs/`, `puppet/modules/profile/manifests/nfs_server.pp` | [`docs/nfs.md`](docs/nfs.md) |
| **LDAP + SSSD (389-ds, authselect)** | `ansible/roles/ldap/`, `ansible/roles/sssd/` | [`docs/ldap-sssd.md`](docs/ldap-sssd.md) |
| **Kerberos (KDC, keytabs, GSSAPI SSH)** | Requires DNS lab first | [`docs/kerberos.md`](docs/kerberos.md) |
| **HAProxy (load balancing)** | `ansible/roles/haproxy/`, `puppet/modules/profile/manifests/haproxy.pp` | [`docs/haproxy.md`](docs/haproxy.md) |
| **Pacemaker/Corosync (HA clustering)** | app + app2 nodes, VIP, STONITH | [`docs/pacemaker.md`](docs/pacemaker.md) |
| **Containers (Podman, Quadlet, Buildah)** | Any node (AlmaLinux ships Podman) | [`docs/containers.md`](docs/containers.md) |
| **Monitoring (Prometheus, node_exporter)** | `ansible/roles/monitoring/`, `puppet/modules/profile/manifests/monitoring.pp` | [`docs/monitoring.md`](docs/monitoring.md) |
| **GitOps (CI/CD, drift detection)** | Repo structure itself demonstrates GitOps | [`docs/gitops.md`](docs/gitops.md) |
| **SELinux, firewalld, systemd** | Every role enforces SELinux + firewalld | All docs include SELinux/firewall sections |
| **Knowledge check** | -- | [`docs/knowledge-check.md`](docs/knowledge-check.md) |
| **Command reference** | -- | [`docs/cheat-sheet.md`](docs/cheat-sheet.md) |

---

## Quickstart

### Prerequisites

- Linux host with KVM/libvirt (16+ GB RAM recommended)
- Vagrant + vagrant-libvirt plugin
- Ansible (for `ansible/` playbooks)

### Bring Up a Cluster

```bash
# AlmaLinux 10 cluster (5 VMs)
make up-alma10

# Or AlmaLinux 9 cluster
make up-alma9
```

### Run Ansible

```bash
# Dry run (check mode)
make ansible-check

# Full convergence
make ansible-run
```

### Run Puppet

```bash
# Validate manifests
make puppet-validate

# Apply on a specific node
make puppet-apply
```

### Terraform (validate only -- requires AWS credentials to apply)

```bash
make tf-init-dev
make tf-validate
```

### Tear Down

```bash
make down-alma10    # Halt VMs
make destroy-all    # Destroy all VMs
```

### SSH Access

```bash
cd vagrant/alma10
vagrant ssh alma10-admin
vagrant ssh alma10-app
vagrant ssh alma10-db
```

---

## Repository Layout

```
.
├── Makefile                    # Convenience targets for all operations
├── README.md
├── .gitignore
│
├── vagrant/
│   ├── alma10/Vagrantfile      # 5 VMs: bastion, admin, app, app2, db
│   └── alma9/Vagrantfile       # Same layout on 192.168.70.0/24
│
├── provision/
│   ├── provision-common.sh     # OS baseline (packages, firewalld, chrony, SELinux)
│   └── provision-puppet.sh     # Puppet agent install from puppetlabs repo
│
├── ansible/                    # Ansible automation (10 roles)
│   ├── ansible.cfg
│   ├── inventory.ini           # AlmaLinux 10 inventory
│   ├── inventory-alma9.ini     # AlmaLinux 9 inventory
│   ├── site.yml                # Master playbook
│   ├── vault.yml               # Encrypted secrets
│   ├── group_vars/             # Per-group variables (all, apps, dbs)
│   ├── host_vars/              # Per-host overrides
│   ├── playbooks/              # Break/fix scenario injection + reset
│   └── roles/
│       ├── common/             # Baseline: packages, timezone, MOTD, sysctl, SELinux
│       ├── firewall/           # Parameterized firewalld rules per role
│       ├── web/                # Apache httpd + vhost + mod_ssl + smoke test
│       ├── db/                 # MariaDB: secure install, app db/user creation
│       ├── dns/                # BIND: forward/reverse zones for lab.local
│       ├── nfs/                # NFS server + client (fstab + autofs)
│       ├── ldap/               # 389-ds (or OpenLDAP via EPEL) + base DIT
│       ├── sssd/               # SSSD + authselect + oddjobd
│       ├── haproxy/            # HAProxy: round-robin app backends + stats
│       └── monitoring/         # Prometheus node_exporter (binary + systemd)
│
├── puppet/                     # Puppet (role/profile pattern)
│   ├── Puppetfile              # r10k module declarations
│   ├── environment.conf
│   ├── hiera.yaml              # Hiera v5 hierarchy
│   ├── data/                   # Hiera data (common + per-node)
│   ├── manifests/site.pp       # Node classification
│   └── modules/
│       ├── profile/            # 8 profiles: base, firewall, web, db, dns,
│       │   ├── manifests/      #   nfs_server, haproxy, monitoring
│       │   └── templates/      # 9 EPP templates
│       └── role/               # 4 roles: app_server, db_server,
│           └── manifests/      #   admin_server, bastion
│
├── terraform/                  # AWS IaC (mirrors on-prem architecture)
│   ├── modules/
│   │   ├── vpc/                # VPC, subnets, IGW, NAT GW, route tables
│   │   ├── security_groups/    # Per-tier SGs (bastion, app, db, admin)
│   │   ├── ec2_cluster/        # EC2 instances + key pair + user_data
│   │   └── rds/                # Managed MariaDB (multi-AZ for prod)
│   └── environments/
│       ├── dev/                # t3.micro, single-AZ, minimal cost
│       └── prod/               # t3.medium, multi-AZ, backups
│
└── docs/                       # 15 comprehensive guides
    ├── lvm-labs.md             # 5 LVM labs with Vagrant extra disks
    ├── break-fix.md            # 8 break/fix scenarios with diagnostics
    ├── dns-bind.md             # BIND authoritative DNS for lab.local
    ├── nfs.md                  # NFSv4: server, fstab, autofs, SELinux
    ├── ldap-sssd.md            # 389-ds + OpenLDAP, SSSD, authselect
    ├── kerberos.md             # KDC, principals, keytabs, GSSAPI SSH
    ├── haproxy.md              # HAProxy LB: backends, health checks, stats
    ├── pacemaker.md            # 2-node HA: VIP, httpd, STONITH, failover
    ├── puppet.md               # Role/profile, Hiera, r10k, Puppet vs Ansible
    ├── terraform-aws.md        # Modules, state, environments, GitOps
    ├── containers.md           # Podman, rootless, Quadlet, Buildah, K8s
    ├── monitoring.md           # Prometheus/Grafana + Nagios/Zabbix/ELK
    ├── gitops.md               # CI/CD pipelines, drift detection, branching
    ├── cheat-sheet.md          # Quick-reference commands by category
    └── knowledge-check.md        # 55 essential topics with explanations
```

---

## Documentation Format

Every doc follows a consistent 8-section structure:

1. **Overview** -- What the technology does and why it matters
2. **Architecture** -- ASCII diagram showing which lab nodes are involved
3. **Prerequisites** -- Packages, firewall rules, SELinux booleans
4. **Step-by-Step Setup** -- Numbered commands with expected output
5. **Verification / Testing** -- End-to-end validation commands
6. **Troubleshooting** -- Common failures with exact diagnostic commands
7. **Architecture Decision Rationale** -- Why X over Y, with tradeoff analysis
8. **Key Concepts to Master** -- What Senior Admins expect you to understand

---

## Suggested Study Order

1. **Bring up the cluster** and run Ansible (`make up-alma10 && make ansible-run`)
2. **LVM labs** -- hands-on storage with the extra disks on the db node
3. **DNS** -- required foundation for Kerberos and hostname resolution
4. **NFS** -- shared storage between nodes
5. **LDAP + SSSD** -- centralized identity
6. **Kerberos** -- authentication (requires DNS)
7. **HAProxy** -- load balancing across app + app2
8. **Pacemaker** -- HA clustering on app + app2
9. **Break/fix scenarios** -- inject and troubleshoot real failures
10. **Puppet** -- compare the Puppet implementation with Ansible
11. **Terraform** -- review the AWS IaC that mirrors the on-prem lab
12. **Containers** -- Podman, Quadlet, rootless on any lab node
13. **Monitoring + GitOps** -- observability and workflow
14. **Knowledge check + command reference** -- validate your understanding

---

## Memory Requirements

Each cluster runs 5 VMs. Total RAM per cluster:

| Node | RAM |
|------|-----|
| bastion | 1 GB |
| admin | 2 GB |
| app | 3 GB |
| app2 | 3 GB |
| db | 3 GB |
| **Total** | **~12-15 GB** |

**Run one cluster at a time** unless you have 32+ GB RAM. Use `make down-alma10`
before `make up-alma9`.

---

## What This Lab Demonstrates

This is not a tutorial collection -- it is a working, integrated infrastructure
that demonstrates how enterprise Linux environments are actually built:

- **Configuration management** with both Puppet (declarative, continuous enforcement)
  and Ansible (procedural, orchestration)
- **Infrastructure as Code** with Terraform modules mirroring on-prem architecture
- **Security hardening** with SELinux enforcing, firewalld, sysctl tuning
- **Identity management** with LDAP + Kerberos + SSSD
- **High availability** with Pacemaker/Corosync and HAProxy
- **Monitoring** with Prometheus node_exporter on every node
- **Break/fix scenarios** that simulate real production incidents
- **Architecture decisions** documented with rationale (why X over Y)
