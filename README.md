# Enterprise On-Prem Linux Administration Lab

This repository demonstrates **realistic on-prem Linux administration**
using **AlmaLinux 9 and AlmaLinux 10 (RHEL-compatible)** on **KVM/libvirt**.

The lab mirrors enterprise environments used in data centers and regulated
industries.

---

## Architecture

Each cluster contains:

- Bastion / Jump Host
- Admin Node
- Application Node (httpd)
- Database Node (MariaDB)

Two independent clusters:
- AlmaLinux 9
- AlmaLinux 10

All systems run:
- systemd
- SELinux (Enforcing)
- firewalld
- NetworkManager
- journald
- LVM (XFS)

---

## Technologies Demonstrated

- AlmaLinux 9 & 10 (RHEL-compatible)
- KVM / libvirt
- Vagrant
- systemd
- SELinux (troubleshooting & policy)
- firewalld
- LDAP + SSSD
- Kerberos authentication
- DNS (BIND)
- NFS
- HAProxy
- Pacemaker / Corosync (HA)
- LVM expansion & snapshots
- Ansible automation (RHCE-aligned)

---

## Repository Layout

- `vagrant/` – Multi-node VM definitions
- `provision/` – OS baseline configuration
- `ansible/` – RHCE-style automation
- `docs/` – Service configuration & break/fix labs

---

## How to Use

### Bring up AlmaLinux 10 cluster
```bash
cd vagrant/alma10
vagrant up --provider=libvirt
```

### Bring up AlmaLinux 9 cluster
```bash
cd vagrant/alma9
vagrant up --provider=libvirt
```

### SSH Access
```bash
vagrant ssh alma10-admin
vagrant ssh alma9-admin
```
