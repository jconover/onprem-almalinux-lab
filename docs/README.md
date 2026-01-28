# Documentation Index

Welcome to the Enterprise On-Prem Linux Administration Lab documentation. This collection of guides covers the full spectrum of skills needed for Senior Linux Administrator and DevOps Engineer roles, from foundational storage and networking to advanced topics like high-availability clustering and infrastructure-as-code.

Each document is designed as a hands-on learning resource with architecture diagrams, step-by-step procedures, troubleshooting guidance, and key concepts to master.

---

## Quick Start Guides

Get up and running with core Linux administration skills.

| Document | Description |
|----------|-------------|
| [**cheat-sheet.md**](cheat-sheet.md) | Quick-reference commands for storage, networking, systemd, SELinux, users, processes, logs, Puppet, Terraform, and containers |
| [**lvm-labs.md**](lvm-labs.md) | Five hands-on LVM labs covering volume creation, online extension, snapshots, and thin provisioning |
| [**break-fix.md**](break-fix.md) | Eight troubleshooting scenarios with injected faults covering SELinux, firewalld, storage, systemd, DNS, NFS, and databases |

---

## Advanced Topics

Deep-dive guides for enterprise infrastructure services.

| Document | Description |
|----------|-------------|
| [**dns-bind.md**](dns-bind.md) | Authoritative DNS with BIND: forward and reverse zones, zone file syntax, and DNS troubleshooting |
| [**nfs.md**](nfs.md) | NFSv4 server and client configuration with persistent mounts, autofs on-demand mounting, and SELinux integration |
| [**ldap-sssd.md**](ldap-sssd.md) | Centralized identity management with 389 Directory Server (or OpenLDAP), SSSD clients, and authselect |
| [**kerberos.md**](kerberos.md) | Kerberos KDC setup, keytab management, GSSAPI SSH, and SSSD integration for single sign-on |
| [**haproxy.md**](haproxy.md) | HTTP/TCP load balancing with HAProxy: backends, health checks, statistics dashboard, and zero-downtime deployments |
| [**pacemaker.md**](pacemaker.md) | Two-node HA clustering with Pacemaker/Corosync: resources, constraints, VIP failover, and STONITH fencing |
| [**containers.md**](containers.md) | Podman, Buildah, and Skopeo: rootless containers, pods, Quadlet systemd integration, and Kubernetes awareness |
| [**monitoring.md**](monitoring.md) | Prometheus and Grafana monitoring stack: node_exporter, PromQL queries, alerting, and observability concepts |

---

## Automation and Infrastructure-as-Code

Modern configuration management and GitOps practices.

| Document | Description |
|----------|-------------|
| [**puppet.md**](puppet.md) | Puppet configuration management: role/profile pattern, Hiera data separation, EPP templates, r10k workflow, and testing |
| [**terraform-aws.md**](terraform-aws.md) | Terraform for AWS: VPC modules, security groups, EC2 clusters, RDS, state management, and CI/CD integration |
| [**gitops.md**](gitops.md) | GitOps workflows for infrastructure: branching strategies, CI/CD pipelines, drift detection, and secret management |

---

## Skills Development

Test your knowledge and identify areas for growth.

| Document | Description |
|----------|-------------|
| [**knowledge-check.md**](knowledge-check.md) | 55 essential topics organized by skill level (Junior to Lead), covering Linux fundamentals through architecture and leadership |

---

## Recommended Learning Path

For those new to enterprise Linux administration, we suggest the following progression:

### Foundation (Week 1-2)
1. **[cheat-sheet.md](cheat-sheet.md)** - Familiarize yourself with essential commands
2. **[lvm-labs.md](lvm-labs.md)** - Master storage management fundamentals
3. **[break-fix.md](break-fix.md)** - Build systematic troubleshooting skills

### Core Services (Week 3-4)
4. **[dns-bind.md](dns-bind.md)** - DNS is foundational for all other services
5. **[nfs.md](nfs.md)** - Shared storage across the cluster
6. **[ldap-sssd.md](ldap-sssd.md)** - Centralized identity management
7. **[kerberos.md](kerberos.md)** - Enterprise authentication (requires DNS first)

### High Availability (Week 5-6)
8. **[haproxy.md](haproxy.md)** - Load balancing and reverse proxy
9. **[pacemaker.md](pacemaker.md)** - Automatic failover clustering
10. **[monitoring.md](monitoring.md)** - Observability and alerting

### Modern Infrastructure (Week 7-8)
11. **[containers.md](containers.md)** - Podman and container workflows
12. **[puppet.md](puppet.md)** - Configuration management at scale
13. **[terraform-aws.md](terraform-aws.md)** - Infrastructure-as-code for cloud
14. **[gitops.md](gitops.md)** - Version-controlled infrastructure workflows

### Assessment
15. **[knowledge-check.md](knowledge-check.md)** - Validate your understanding across all topics

---

## Document Conventions

All documentation follows a consistent structure:

- **Overview** - What the technology is and why it matters
- **Architecture** - Diagrams showing how components interact in this lab
- **Prerequisites** - Packages, firewall rules, and dependencies
- **Step-by-Step Setup** - Detailed procedures with explanations
- **Verification/Testing** - How to confirm everything works
- **Troubleshooting** - Common issues and solutions
- **Architecture Decision Rationale** - Why we made specific design choices
- **Key Concepts to Master** - Essential knowledge for interviews and production

---

## Contributing

Found an error or want to improve the documentation? See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines on submitting changes.
