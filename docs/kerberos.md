# Kerberos

## Overview

Kerberos is a network authentication protocol that uses symmetric-key
cryptography and a trusted third party (the Key Distribution Center) to
authenticate users and services without transmitting passwords over the
network. In enterprise Linux environments, Kerberos provides single sign-on
(SSO) for services like SSH, NFS, and web applications. This lab sets up a
Kerberos realm on the admin node and integrates it with SSSD on all clients.

**Prerequisite:** DNS must be configured and working first. Kerberos relies
on DNS SRV records for KDC discovery and forward/reverse lookups for service
principal name resolution.

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│  Kerberos Architecture                                             │
│                                                                    │
│  admin (192.168.60.11) ── KDC (Key Distribution Center)            │
│    │  Realm: LAB.LOCAL                                             │
│    │  Services: krb5kdc, kadmin                                    │
│    │  Port 88 (KDC), 749 (kadmin), 464 (kpasswd)                  │
│    │                                                               │
│    │  DNS SRV Records (on admin):                                  │
│    │    _kerberos._udp.lab.local    → admin.lab.local:88           │
│    │    _kerberos._tcp.lab.local    → admin.lab.local:88           │
│    │    _kerberos-adm._tcp.lab.local → admin.lab.local:749         │
│    │    _kpasswd._udp.lab.local     → admin.lab.local:464          │
│    │                                                               │
│    ├──▶ bastion (192.168.60.10) ── Kerberos Client                 │
│    ├──▶ app     (192.168.60.12) ── Kerberos Client + HTTP keytab   │
│    ├──▶ app2    (192.168.60.14) ── Kerberos Client + HTTP keytab   │
│    └──▶ db      (192.168.60.13) ── Kerberos Client                 │
│                                                                    │
│  All nodes: /etc/krb5.conf, SSSD with auth_provider = krb5         │
└────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### DNS Must Be Working

Kerberos requires:
- Forward DNS (hostname to IP) for all nodes
- Reverse DNS (IP to hostname) for service ticket validation
- SRV records for KDC auto-discovery (see dns-bind.md)

Verify before proceeding:

```bash
dig +short admin.lab.local
# 192.168.60.11

dig +short -x 192.168.60.11
# admin.lab.local.

dig +short _kerberos._udp.lab.local SRV
# 0 0 88 admin.lab.local.
```

### Packages

**KDC (admin node):**

```bash
sudo dnf install -y krb5-server krb5-libs krb5-workstation
```

**Clients (all other nodes):**

```bash
sudo dnf install -y krb5-workstation krb5-libs sssd-krb5
```

### Firewall (admin node)

```bash
sudo firewall-cmd --permanent --add-service=kerberos
sudo firewall-cmd --permanent --add-service=kadmin
sudo firewall-cmd --permanent --add-service=kpasswd
sudo firewall-cmd --reload
```

### SELinux

The default SELinux policy permits krb5kdc and kadmin. No booleans needed
unless using non-standard paths.

### Time Synchronization

Kerberos has a 5-minute default clock skew tolerance. All nodes must be
synchronized via chrony. Verify:

```bash
chronyc tracking | grep "System time"
# System time: 0.000000123 seconds fast of NTP time
```

---

## Step-by-Step Setup

### KDC Configuration (admin node)

#### Step 1 -- Configure /etc/krb5.conf

This file is used by both the KDC and all clients. Deploy it on every node.

```bash
sudo tee /etc/krb5.conf << 'EOF'
# Configuration snippets may be placed in the /etc/krb5.conf.d/ directory

includedir /etc/krb5.conf.d/

[logging]
    default = FILE:/var/log/krb5libs.log
    kdc = FILE:/var/log/krb5kdc.log
    admin_server = FILE:/var/log/kadmind.log

[libdefaults]
    dns_lookup_realm = false
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false
    pkinit_anchors = FILE:/etc/pki/tls/certs/ca-bundle.crt
    default_realm = LAB.LOCAL
    default_ccache_name = KEYRING:persistent:%{uid}

[realms]
    LAB.LOCAL = {
        kdc = admin.lab.local
        admin_server = admin.lab.local
    }

[domain_realm]
    .lab.local = LAB.LOCAL
    lab.local = LAB.LOCAL
EOF
```

#### Step 2 -- Configure /var/kerberos/krb5kdc/kdc.conf

```bash
sudo tee /var/kerberos/krb5kdc/kdc.conf << 'EOF'
[kdcdefaults]
    kdc_ports = 88
    kdc_tcp_ports = 88

[realms]
    LAB.LOCAL = {
        master_key_type = aes256-cts
        acl_file = /var/kerberos/krb5kdc/kadm5.acl
        dict_file = /usr/share/dict/words
        admin_keytab = /var/kerberos/krb5kdc/kadm5.keytab
        supported_enctypes = aes256-cts:normal aes128-cts:normal
        max_life = 24h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
    }
EOF
```

#### Step 3 -- Configure Admin ACL

```bash
sudo tee /var/kerberos/krb5kdc/kadm5.acl << 'EOF'
*/admin@LAB.LOCAL    *
EOF
```

This grants full admin rights to any principal with `/admin` suffix.

#### Step 4 -- Create the Kerberos Database

```bash
sudo kdb5_util create -s -P MasterKeyPass123
```

Expected output:

```
Loading random data
Initializing database '/var/kerberos/krb5kdc/principal' for realm 'LAB.LOCAL',
master key name 'K/M@LAB.LOCAL'
```

#### Step 5 -- Create Admin Principal

```bash
sudo kadmin.local -q "addprinc -pw AdminPass123 admin/admin@LAB.LOCAL"
```

#### Step 6 -- Create User Principals

```bash
sudo kadmin.local -q "addprinc -pw TestPass123 testuser1@LAB.LOCAL"
sudo kadmin.local -q "addprinc -pw TestPass123 testuser2@LAB.LOCAL"
```

#### Step 7 -- Start KDC Services

```bash
sudo systemctl enable --now krb5kdc
sudo systemctl enable --now kadmin
sudo systemctl status krb5kdc
sudo systemctl status kadmin
```

#### Step 8 -- Test Authentication

```bash
kinit testuser1@LAB.LOCAL
# Enter password: TestPass123

klist
```

Expected:

```
Ticket cache: KEYRING:persistent:0:0
Default principal: testuser1@LAB.LOCAL

Valid starting       Expires              Service principal
01/01/2025 10:00:00  01/02/2025 10:00:00  krbtgt/LAB.LOCAL@LAB.LOCAL
```

```bash
kdestroy
```

---

### Service Principals and Keytabs

#### Step 9 -- Create Host Principals (for Kerberized SSH)

On the KDC (admin node), create host principals for each node:

```bash
sudo kadmin.local -q "addprinc -randkey host/bastion.lab.local@LAB.LOCAL"
sudo kadmin.local -q "addprinc -randkey host/admin.lab.local@LAB.LOCAL"
sudo kadmin.local -q "addprinc -randkey host/app.lab.local@LAB.LOCAL"
sudo kadmin.local -q "addprinc -randkey host/app2.lab.local@LAB.LOCAL"
sudo kadmin.local -q "addprinc -randkey host/db.lab.local@LAB.LOCAL"
```

#### Step 10 -- Create HTTP Service Principals (for Apache)

```bash
sudo kadmin.local -q "addprinc -randkey HTTP/app.lab.local@LAB.LOCAL"
sudo kadmin.local -q "addprinc -randkey HTTP/app2.lab.local@LAB.LOCAL"
```

#### Step 11 -- Export Keytabs

For each node, export its host keytab. Example for the app node:

```bash
# On the KDC:
sudo kadmin.local -q "ktadd -k /tmp/app.keytab host/app.lab.local@LAB.LOCAL"
sudo kadmin.local -q "ktadd -k /tmp/app-http.keytab HTTP/app.lab.local@LAB.LOCAL"

# Copy to app node:
scp /tmp/app.keytab app:/etc/krb5.keytab
scp /tmp/app-http.keytab app:/etc/httpd/conf/http.keytab
```

On the app node, set permissions:

```bash
sudo chmod 600 /etc/krb5.keytab
sudo chown root:root /etc/krb5.keytab
sudo chmod 640 /etc/httpd/conf/http.keytab
sudo chown root:apache /etc/httpd/conf/http.keytab
```

Verify the keytab:

```bash
sudo klist -ke /etc/krb5.keytab
```

---

### SSSD Integration with Kerberos

#### Step 12 -- Update SSSD for Kerberos Authentication

Modify `/etc/sssd/sssd.conf` on all client nodes to use Kerberos for
authentication while keeping LDAP for identity:

```ini
[domain/lab.local]
id_provider = ldap
auth_provider = krb5
chpass_provider = krb5

ldap_uri = ldap://192.168.60.13
ldap_search_base = dc=lab,dc=local
ldap_id_use_start_tls = false
ldap_tls_reqcert = never

krb5_server = admin.lab.local
krb5_realm = LAB.LOCAL
krb5_kpasswd = admin.lab.local
cache_credentials = true

ldap_user_search_base = ou=People,dc=lab,dc=local
ldap_group_search_base = ou=Groups,dc=lab,dc=local
```

```bash
sudo systemctl restart sssd
```

---

### Kerberized SSH

#### Step 13 -- Configure SSH Server

On each node, edit `/etc/ssh/sshd_config`:

```
GSSAPIAuthentication yes
GSSAPICleanupCredentials yes
```

```bash
sudo systemctl restart sshd
```

#### Step 14 -- Configure SSH Client

On the client node, edit `/etc/ssh/ssh_config` (or `~/.ssh/config`):

```
Host *.lab.local
    GSSAPIAuthentication yes
    GSSAPIDelegateCredentials yes
```

#### Step 15 -- Test Kerberized SSH

```bash
kinit testuser1@LAB.LOCAL
ssh app.lab.local    # should not prompt for password
klist                # should show service ticket for host/app.lab.local
```

---

## Verification / Testing

```bash
# Test Kerberos authentication
kinit testuser1@LAB.LOCAL
klist

# Test password change
kpasswd testuser1@LAB.LOCAL

# Test admin operations
kinit admin/admin@LAB.LOCAL
kadmin -q "listprincs"

# Test kerberized SSH
kinit testuser1@LAB.LOCAL
ssh app.lab.local hostname

# Check KDC is listening
ss -ulnp | grep :88
ss -tlnp | grep :749

# Verify DNS SRV records
dig _kerberos._udp.lab.local SRV +short

# Destroy tickets
kdestroy
klist    # should show "No credentials cache found"
```

---

## Troubleshooting

### "Clock skew too great" (KRB5KRB_AP_ERR_SKEW)

```bash
# Check time on all nodes
date
chronyc tracking

# Fix: sync time
sudo chronyc makestep
# Or restart chronyd
sudo systemctl restart chronyd
```

Kerberos default skew tolerance is 5 minutes. Ensure chrony is running on
all nodes.

### "KDC unreachable" or "Cannot contact any KDC"

```bash
# Check KDC service
ssh admin "sudo systemctl status krb5kdc"

# Check firewall
ssh admin "sudo firewall-cmd --list-services"
# Must include: kerberos

# Check DNS SRV records
dig _kerberos._udp.lab.local SRV

# Test direct connection
nc -zv admin.lab.local 88
```

### "Keytab mismatch" or "Key version number mismatch"

```bash
# The keytab was regenerated on the KDC but not updated on the host
# Re-export the keytab:
# On KDC:
sudo kadmin.local -q "ktadd -k /tmp/host.keytab host/HOSTNAME.lab.local"
# Copy to host and replace /etc/krb5.keytab

# Verify keytab
sudo klist -ke /etc/krb5.keytab
```

Every time `ktadd` is run, the key version number (kvno) increments. The
keytab on the host must match the kvno in the KDC database.

### "Pre-authentication failed" (wrong password)

```bash
# Verify the principal exists
kadmin.local -q "getprinc testuser1"

# Reset password
kadmin.local -q "cpw testuser1"
```

### SSSD not using Kerberos

```bash
# Check SSSD config
grep auth_provider /etc/sssd/sssd.conf
# Should be: auth_provider = krb5

# Check SSSD logs
sudo cat /var/log/sssd/sssd_lab.local.log | grep -i krb

# Clear cache and restart
sudo sss_cache -E
sudo systemctl restart sssd
```

---

## Architecture Decision Rationale

### Why Kerberos over simple LDAP bind authentication?

- **LDAP bind** transmits the password to the server (even with TLS, the
  server sees the plaintext password). If the LDAP server is compromised,
  all passwords are exposed.
- **Kerberos** uses a challenge-response protocol. Passwords are never sent
  over the network. The KDC issues time-limited tickets that prove identity.
- **Single sign-on:** Once you have a Kerberos ticket, you can access
  multiple services (SSH, NFS, HTTP) without re-authenticating.

### Why separate id_provider (LDAP) and auth_provider (Kerberos)?

This is the standard enterprise pattern:
- **LDAP** stores identity information (uid, gid, home directory, groups)
- **Kerberos** handles authentication (password verification, tickets)
- Combining them gives centralized identity + secure authentication
- This is exactly how FreeIPA and Active Directory work under the hood

### Why DNS SRV records for KDC discovery?

Hardcoding KDC addresses in krb5.conf works but does not scale. SRV records
allow clients to discover KDCs dynamically, support multiple KDCs for HA,
and centralize KDC location changes in DNS rather than updating every
client's krb5.conf.

### STONITH for Kerberos HA?

In production, you would deploy multiple KDC replicas (one primary, one or
more replicas) using `kpropd` for database replication. The lab uses a
single KDC for simplicity but be prepared to discuss multi-KDC architecture.

---

## Key Concepts to Master

### How Kerberos Authentication Works

The client sends a request to the KDC's Authentication Service (AS).
The AS returns a Ticket Granting Ticket (TGT) encrypted with the user's
key. The client decrypts it (proving they know the password) and uses the
TGT to request service tickets from the Ticket Granting Service (TGS).
Service tickets are presented to target services, which validate them
using their keytab.

### Understanding Keytabs

A keytab is a file containing one or more Kerberos principal keys. It
allows services (like SSH or Apache) to authenticate without human
interaction. It is the service equivalent of a password. Keytabs must be
protected with strict file permissions (600 or 640).

### Clock Skew and Time Synchronization

Kerberos tickets include timestamps. If the clock difference between
client and KDC exceeds the maximum skew (default 5 minutes), authentication
fails with KRB5KRB_AP_ERR_SKEW. This is why NTP (chrony) is mandatory in
Kerberos environments.

### Essential Commands: kinit, klist, and kdestroy

`kinit` obtains a TGT from the KDC (authenticates the user). `klist`
displays currently held tickets. `kdestroy` destroys the ticket cache
(logs out from Kerberos). These are the basic Kerberos troubleshooting
commands.

### Kerberized SSH Authentication

The SSH server has a host principal keytab. The client, already holding
a TGT, requests a service ticket for `host/servername` from the KDC. The
client presents this ticket to the SSH server, which validates it using its
keytab. No password is transmitted. This requires GSSAPIAuthentication in
sshd_config and a valid TGT on the client.

### Kerberos High Availability

Deploy one primary KDC and one or more replica KDCs. Use `kpropd` to
replicate the database. Configure DNS SRV records with multiple KDC entries.
Clients will fail over automatically. The primary handles password changes
and admin operations; replicas handle read-only authentication.
