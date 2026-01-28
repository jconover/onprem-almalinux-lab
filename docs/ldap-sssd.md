# LDAP + SSSD Authentication

## Overview

Centralized identity management is a core enterprise requirement. This lab
implements an LDAP directory service on the db node and configures all other
nodes as SSSD clients for centralized authentication. Users defined in LDAP
can log in to any node in the cluster with automatic home directory creation.

**Important note for AlmaLinux 9 / RHEL 9:** The `openldap-servers` package
has been removed from the base repositories. This guide documents two
approaches: 389 Directory Server (the Red Hat-supported replacement) and
OpenLDAP via EPEL (for legacy familiarity). Use 389-ds for new deployments.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  LDAP + SSSD Architecture                                        │
│                                                                  │
│  db (192.168.60.13) ── LDAP Server                               │
│    │  389 Directory Server (or OpenLDAP)                         │
│    │  Base DN: dc=lab,dc=local                                   │
│    │  ├── ou=People  (testuser1, testuser2)                      │
│    │  └── ou=Groups  (labusers)                                  │
│    │  Port: 389 (LDAP), 636 (LDAPS)                              │
│    │                                                             │
│    ├──▶ bastion (192.168.60.10) ── SSSD Client                   │
│    ├──▶ admin   (192.168.60.11) ── SSSD Client                   │
│    ├──▶ app     (192.168.60.12) ── SSSD Client                   │
│    └──▶ app2    (192.168.60.14) ── SSSD Client                   │
│                                                                  │
│  authselect + SSSD + oddjob-mkhomedir on all clients             │
└──────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Packages -- 389 Directory Server Approach (Recommended)

**Server (db node):**

```bash
sudo dnf install -y 389-ds-base
```

**Clients (all other nodes):**

```bash
sudo dnf install -y sssd sssd-ldap oddjob-mkhomedir openldap-clients
```

### Packages -- OpenLDAP Approach (Legacy)

**Server (db node):**

```bash
sudo dnf install -y epel-release
sudo dnf install -y openldap-servers openldap-clients
```

**Clients:** Same as above.

### Firewall (db node)

```bash
sudo firewall-cmd --permanent --add-service=ldap
sudo firewall-cmd --permanent --add-service=ldaps
sudo firewall-cmd --reload
```

### SELinux

SELinux confines the LDAP server. If using non-standard paths for the
database, set correct contexts:

```bash
# For 389-ds (default paths are pre-labeled)
sudo semanage port -l | grep ldap_port_t

# Booleans for SSSD on clients
sudo setsebool -P authlogin_nsswitch_use_ldap on
```

---

## Step-by-Step Setup -- 389 Directory Server

### Step 1 -- Create Instance Configuration

Create an INF file for non-interactive setup:

```bash
sudo tee /root/ds-setup.inf << 'EOF'
[general]
config_version = 2
full_machine_name = db.lab.local
strict_host_checking = false

[slapd]
instance_name = lab
root_dn = cn=Directory Manager
root_password = LabPass123

[backend-userroot]
sample_entries = no
suffix = dc=lab,dc=local
EOF
```

### Step 2 -- Create the Instance

```bash
sudo dscreate from-file /root/ds-setup.inf
```

Expected output:

```
Successfully created instance slapd-lab
```

Verify:

```bash
sudo dsctl lab status
```

```
Instance "lab" is running
```

### Step 3 -- Create Base DIT (Directory Information Tree)

```bash
sudo tee /root/base.ldif << 'EOF'
dn: dc=lab,dc=local
objectClass: top
objectClass: domain
dc: lab

dn: ou=People,dc=lab,dc=local
objectClass: top
objectClass: organizationalUnit
ou: People

dn: ou=Groups,dc=lab,dc=local
objectClass: top
objectClass: organizationalUnit
ou: Groups
EOF

ldapadd -x -D "cn=Directory Manager" -w LabPass123 -H ldap://localhost -f /root/base.ldif
```

### Step 4 -- Create Test Users

```bash
sudo tee /root/users.ldif << 'EOF'
dn: uid=testuser1,ou=People,dc=lab,dc=local
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Test User 1
sn: User1
uid: testuser1
uidNumber: 10001
gidNumber: 10001
homeDirectory: /home/testuser1
loginShell: /bin/bash
userPassword: TestPass123

dn: uid=testuser2,ou=People,dc=lab,dc=local
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Test User 2
sn: User2
uid: testuser2
uidNumber: 10002
gidNumber: 10001
homeDirectory: /home/testuser2
loginShell: /bin/bash
userPassword: TestPass123

dn: cn=labusers,ou=Groups,dc=lab,dc=local
objectClass: top
objectClass: posixGroup
cn: labusers
gidNumber: 10001
memberUid: testuser1
memberUid: testuser2
EOF

ldapadd -x -D "cn=Directory Manager" -w LabPass123 -H ldap://localhost -f /root/users.ldif
```

### Step 5 -- Verify LDAP Data

```bash
ldapsearch -x -H ldap://localhost -b "dc=lab,dc=local" "(objectClass=posixAccount)" uid uidNumber
```

Expected:

```
# testuser1, People, lab.local
dn: uid=testuser1,ou=People,dc=lab,dc=local
uid: testuser1
uidNumber: 10001

# testuser2, People, lab.local
dn: uid=testuser2,ou=People,dc=lab,dc=local
uid: testuser2
uidNumber: 10002
```

---

## Step-by-Step Setup -- OpenLDAP (Legacy via EPEL)

### Step 1 -- Install and Configure slapd

```bash
sudo dnf install -y epel-release
sudo dnf install -y openldap-servers openldap-clients
sudo systemctl enable --now slapd

# Set admin password
PASS=$(slappasswd -s LabPass123)
sudo ldapmodify -Y EXTERNAL -H ldapi:/// << EOF
dn: olcDatabase={2}mdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=lab,dc=local
-
replace: olcRootDN
olcRootDN: cn=Manager,dc=lab,dc=local
-
replace: olcRootPW
olcRootPW: ${PASS}
EOF
```

### Step 2 -- Import Schemas

```bash
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif
sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
```

### Step 3 -- Add Base DIT and Users

Use the same LDIF files from the 389-ds setup above, substituting
`cn=Manager,dc=lab,dc=local` as the bind DN.

---

## Client Configuration (All Nodes)

### Step 6 -- Configure SSSD

```bash
sudo tee /etc/sssd/sssd.conf << 'EOF'
[sssd]
services = nss, pam
domains = lab.local

[domain/lab.local]
id_provider = ldap
auth_provider = ldap
ldap_uri = ldap://192.168.60.13
ldap_search_base = dc=lab,dc=local
ldap_id_use_start_tls = false
ldap_tls_reqcert = never
cache_credentials = true
enumerate = true

ldap_user_search_base = ou=People,dc=lab,dc=local
ldap_group_search_base = ou=Groups,dc=lab,dc=local

[nss]
filter_groups = root
filter_users = root

[pam]
offline_credentials_expiration = 2
EOF

sudo chmod 600 /etc/sssd/sssd.conf
sudo chown root:root /etc/sssd/sssd.conf
```

### Step 7 -- Configure authselect

```bash
sudo authselect select sssd with-mkhomedir --force
```

This configures PAM and nsswitch.conf to use SSSD and enables automatic
home directory creation on first login.

### Step 8 -- Enable Services

```bash
sudo systemctl enable --now sssd
sudo systemctl enable --now oddjobd
```

### Step 9 -- Verify User Resolution

```bash
id testuser1
```

Expected:

```
uid=10001(testuser1) gid=10001(labusers) groups=10001(labusers)
```

```bash
getent passwd testuser1
```

Expected:

```
testuser1:*:10001:10001:Test User 1:/home/testuser1:/bin/bash
```

### Step 10 -- Test Login

```bash
ssh testuser1@localhost
# Password: TestPass123
# Home directory should be created automatically
pwd
# /home/testuser1
```

---

## TLS/LDAPS Setup

For production, LDAP traffic must be encrypted.

### Generate Self-Signed Certificate (on db node)

```bash
sudo mkdir -p /etc/dirsrv/slapd-lab
sudo openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout /etc/dirsrv/slapd-lab/server-key.pem \
  -out /etc/dirsrv/slapd-lab/server-cert.pem \
  -days 365 -subj "/CN=db.lab.local"
```

### Configure 389-ds for TLS

```bash
sudo dsconf lab security enable
sudo dsconf lab security certificate add --file /etc/dirsrv/slapd-lab/server-cert.pem --name "Server-Cert"
sudo dsctl lab restart
```

### Update SSSD Clients for TLS

Update `/etc/sssd/sssd.conf`:

```ini
ldap_uri = ldaps://192.168.60.13
ldap_id_use_start_tls = true
ldap_tls_reqcert = allow
ldap_tls_cacert = /etc/pki/tls/certs/lab-ca.pem
```

Copy the CA certificate to all clients and restart SSSD.

---

## Verification / Testing

```bash
# From any client node:

# Resolve LDAP users
id testuser1
id testuser2
getent passwd testuser1
getent group labusers

# Search LDAP directly
ldapsearch -x -H ldap://192.168.60.13 -b "dc=lab,dc=local" "(uid=testuser1)"

# Test authentication
ssh testuser1@app.lab.local

# Check SSSD cache
sudo sssctl domain-status lab.local
sudo sssctl user-checks testuser1
```

---

## Troubleshooting

### "id: testuser1: no such user"

```bash
# Check SSSD is running
sudo systemctl status sssd

# Check SSSD logs
sudo journalctl -u sssd --no-pager -n 30
sudo cat /var/log/sssd/sssd_lab.local.log

# Clear SSSD cache and restart
sudo sss_cache -E
sudo systemctl restart sssd

# Verify LDAP is reachable
ldapsearch -x -H ldap://192.168.60.13 -b "dc=lab,dc=local" "(uid=testuser1)"
```

### SSSD fails to start

```bash
# Check config file permissions (must be 600)
ls -la /etc/sssd/sssd.conf
sudo chmod 600 /etc/sssd/sssd.conf

# Validate config
sudo sssctl config-check

# Check journal
sudo journalctl -u sssd --no-pager -n 30
```

### Home directory not created on login

```bash
# Check authselect
authselect current
# Should show: sssd with-mkhomedir

# Check oddjobd
sudo systemctl status oddjobd

# Manual fix
sudo authselect select sssd with-mkhomedir --force
sudo systemctl restart oddjobd
```

### LDAP server connection refused

```bash
# Check LDAP service is running
ssh db "sudo systemctl status dirsrv@lab"    # 389-ds
ssh db "sudo systemctl status slapd"          # OpenLDAP

# Check firewall
ssh db "sudo firewall-cmd --list-services"

# Test connectivity
ldapsearch -x -H ldap://192.168.60.13 -b "" -s base
```

### SELinux denials on SSSD

```bash
sudo ausearch -m avc -ts recent | grep sssd
sudo setsebool -P authlogin_nsswitch_use_ldap on
```

---

## Architecture Decision Rationale

### Why 389 Directory Server over OpenLDAP?

| Factor | OpenLDAP | 389 Directory Server |
|--------|----------|---------------------|
| RHEL 9 support | Removed from base repos | Fully supported |
| Configuration | cn=config (LDIF-based, complex) | dsconf CLI (user-friendly) |
| Replication | Manual setup | Built-in multi-supplier |
| Web console | None | Cockpit plugin available |
| Red Hat backing | Community only | Upstream of RHDS/IdM |

**Trade-off:** OpenLDAP is still widely used in non-Red Hat environments
and is valuable background knowledge. 389-ds is the forward-looking choice
for RHEL-based infrastructure.

### Why SSSD over direct PAM/LDAP?

- **SSSD caches credentials offline** -- users can log in even when LDAP
  is unreachable (for a configurable period)
- **SSSD supports multiple identity providers** -- LDAP, Kerberos, Active
  Directory, IPA -- with a single configuration framework
- **SSSD is the Red Hat/AlmaLinux standard** and is expected knowledge
  for RHCSA/RHCE and enterprise admin roles

### Why authselect over authconfig?

`authconfig` is deprecated in RHEL 8+. `authselect` is its replacement.
It manages PAM and nsswitch.conf through profiles rather than individual
file edits, reducing the risk of misconfiguration.

---

## Key Concepts to Master

### LDAP Server Options in RHEL 9

The `openldap-servers` package is missing from RHEL 9 base repositories.
Red Hat recommends 389 Directory Server as the replacement -- it is the
upstream of Red Hat Directory Server and FreeIPA. Install it with
`dnf install 389-ds-base` and configure with `dscreate` and `dsconf`.
OpenLDAP remains available via EPEL for legacy compatibility.

### Understanding SSSD

SSSD (System Security Services Daemon) provides centralized authentication,
identity lookup, and credential caching. It acts as a broker between the
system's NSS/PAM and identity providers like LDAP, Kerberos, or Active
Directory. A key benefit is offline login capability via cached credentials.

### Configuring LDAP Authentication on Linux Clients

To configure a Linux client for LDAP authentication:
1. Install sssd and sssd-ldap packages
2. Create /etc/sssd/sssd.conf with the LDAP server URI, search base, and domain settings
3. Run `authselect select sssd with-mkhomedir` to configure PAM and nsswitch
4. Enable sssd and oddjobd services

### authselect vs authconfig

authselect manages PAM and nsswitch.conf configuration through predefined
profiles. Unlike authconfig (deprecated), it does not modify PAM files
directly, reducing misconfiguration risk. Apply configurations with
`authselect select PROFILE`.

### Debugging SSSD User Resolution

When SSSD fails to resolve users, follow this troubleshooting approach:
- Verify sssd.conf permissions (must be 0600)
- Check SSSD logs in /var/log/sssd/
- Verify LDAP connectivity with ldapsearch
- Clear SSSD cache with `sss_cache -E`
- Use `sssctl user-checks USERNAME` for diagnostics

### Required POSIX Attributes for LDAP Users

LDAP user entries must have these POSIX attributes at minimum: uid, uidNumber,
gidNumber, homeDirectory, and loginShell. These are provided by the
posixAccount objectClass. Without them, the user will not be resolved as
a valid UNIX account.
