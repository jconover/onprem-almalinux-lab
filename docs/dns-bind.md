# DNS (BIND)

## Overview

BIND (Berkeley Internet Name Domain) is the most widely deployed DNS server
in enterprise environments. This lab sets up an authoritative DNS server on
the admin node that resolves all lab hostnames to their IP addresses (forward
lookup) and IP addresses back to hostnames (reverse lookup). Functioning
DNS is a prerequisite for Kerberos, LDAP, and many other enterprise services.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  DNS Architecture                                                │
│                                                                  │
│  admin (192.168.60.11)  ◄── Authoritative DNS Server (named)     │
│    │  Forward zone: lab.local                                    │
│    │  Reverse zone: 60.168.192.in-addr.arpa                      │
│    │                                                             │
│    ├── bastion.lab.local  ──  192.168.60.10                      │
│    ├── admin.lab.local    ──  192.168.60.11                      │
│    ├── app.lab.local      ──  192.168.60.12                      │
│    ├── db.lab.local       ──  192.168.60.13                      │
│    └── app2.lab.local     ──  192.168.60.14                      │
│                                                                  │
│  All nodes use 192.168.60.11 as their primary DNS resolver.      │
│  Recursion enabled with forwarders to upstream DNS.              │
└──────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Packages (admin node)

```bash
sudo dnf install -y bind bind-utils
```

### Packages (all client nodes)

```bash
sudo dnf install -y bind-utils   # provides dig, nslookup, host
```

### Firewall (admin node)

```bash
sudo firewall-cmd --permanent --add-service=dns
sudo firewall-cmd --reload
```

This opens port 53 on both TCP and UDP.

### SELinux

BIND runs confined under the `named_t` SELinux domain. Zone files must be
stored in `/var/named/` with the correct context:

```bash
ls -Z /var/named/
# Expected context: system_u:object_r:named_zone_t:s0
```

---

## Step-by-Step Setup

### Step 1 -- Configure /etc/named.conf

Back up the default configuration:

```bash
sudo cp /etc/named.conf /etc/named.conf.bak
```

Edit `/etc/named.conf`:

```
options {
    listen-on port 53 { 127.0.0.1; 192.168.60.11; };
    listen-on-v6 port 53 { none; };
    directory       "/var/named";
    dump-file       "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";

    allow-query     { localhost; 192.168.60.0/24; };
    recursion yes;
    forwarders { 8.8.8.8; 8.8.4.4; };

    dnssec-validation yes;

    managed-keys-directory "/var/named/dynamic";
    pid-file "/run/named/named.pid";
    session-keyfile "/run/named/session.key";
};

logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
};

zone "." IN {
    type hint;
    file "named.ca";
};

zone "lab.local" IN {
    type master;
    file "lab.local.zone";
    allow-update { none; };
};

zone "60.168.192.in-addr.arpa" IN {
    type master;
    file "60.168.192.rev";
    allow-update { none; };
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
```

### Step 2 -- Create Forward Zone File

Create `/var/named/lab.local.zone`:

```
$TTL 86400
@   IN  SOA admin.lab.local. root.lab.local. (
            2025010101  ; Serial (YYYYMMDDNN)
            3600        ; Refresh (1 hour)
            1800        ; Retry (30 minutes)
            604800      ; Expire (1 week)
            86400       ; Minimum TTL (1 day)
)

; Name Servers
@       IN  NS  admin.lab.local.

; A Records
bastion IN  A   192.168.60.10
admin   IN  A   192.168.60.11
app     IN  A   192.168.60.12
db      IN  A   192.168.60.13
app2    IN  A   192.168.60.14

; Kerberos SRV Records (for Kerberos lab)
_kerberos._udp      IN  SRV 0 0 88  admin.lab.local.
_kerberos._tcp      IN  SRV 0 0 88  admin.lab.local.
_kerberos-adm._tcp  IN  SRV 0 0 749 admin.lab.local.
_kpasswd._udp       IN  SRV 0 0 464 admin.lab.local.
```

### Step 3 -- Create Reverse Zone File

Create `/var/named/60.168.192.rev`:

```
$TTL 86400
@   IN  SOA admin.lab.local. root.lab.local. (
            2025010101  ; Serial
            3600        ; Refresh
            1800        ; Retry
            604800      ; Expire
            86400       ; Minimum TTL
)

; Name Servers
@   IN  NS  admin.lab.local.

; PTR Records
10  IN  PTR bastion.lab.local.
11  IN  PTR admin.lab.local.
12  IN  PTR app.lab.local.
13  IN  PTR db.lab.local.
14  IN  PTR app2.lab.local.
```

### Step 4 -- Set File Ownership and SELinux Context

```bash
sudo chown root:named /var/named/lab.local.zone
sudo chown root:named /var/named/60.168.192.rev
sudo chmod 640 /var/named/lab.local.zone
sudo chmod 640 /var/named/60.168.192.rev

# Restore SELinux contexts
sudo restorecon -Rv /var/named/
```

### Step 5 -- Validate Configuration

```bash
sudo named-checkconf /etc/named.conf
```

No output means success.

```bash
sudo named-checkzone lab.local /var/named/lab.local.zone
```

Expected:

```
zone lab.local/IN: loaded serial 2025010101
OK
```

```bash
sudo named-checkzone 60.168.192.in-addr.arpa /var/named/60.168.192.rev
```

Expected:

```
zone 60.168.192.in-addr.arpa/IN: loaded serial 2025010101
OK
```

### Step 6 -- Start and Enable named

```bash
sudo systemctl enable --now named
sudo systemctl status named
```

### Step 7 -- Configure Clients

On each node, set the admin node as the primary DNS server. Using
NetworkManager:

```bash
sudo nmcli con mod "System eth1" ipv4.dns "192.168.60.11"
sudo nmcli con mod "System eth1" ipv4.dns-search "lab.local"
sudo nmcli con mod "System eth1" ipv4.ignore-auto-dns yes
sudo nmcli con up "System eth1"
```

Or edit `/etc/resolv.conf` directly (will be overwritten by NetworkManager
unless `ipv4.ignore-auto-dns` is set):

```
search lab.local
nameserver 192.168.60.11
```

---

## Verification / Testing

### Forward Lookups

```bash
dig @192.168.60.11 bastion.lab.local
```

Expected answer section:

```
;; ANSWER SECTION:
bastion.lab.local.    86400   IN  A   192.168.60.10
```

Test all nodes:

```bash
for host in bastion admin app db app2; do
  echo -n "$host: "
  dig +short @192.168.60.11 ${host}.lab.local
done
```

### Reverse Lookups

```bash
dig @192.168.60.11 -x 192.168.60.10
```

Expected:

```
;; ANSWER SECTION:
10.60.168.192.in-addr.arpa. 86400 IN PTR bastion.lab.local.
```

### Short Name Resolution

With `search lab.local` in resolv.conf:

```bash
dig +short admin
# Should return 192.168.60.11
ping -c 1 app
# Should resolve to 192.168.60.12
```

### SRV Records (for Kerberos)

```bash
dig @192.168.60.11 _kerberos._udp.lab.local SRV +short
# Expected: 0 0 88 admin.lab.local.
```

### nslookup (Alternative)

```bash
nslookup bastion.lab.local 192.168.60.11
nslookup 192.168.60.10 192.168.60.11
```

---

## Troubleshooting

### named won't start

```bash
sudo journalctl -u named --no-pager -n 30
sudo named-checkconf /etc/named.conf
sudo named-checkzone lab.local /var/named/lab.local.zone
```

Common causes:
- Syntax error in named.conf (missing semicolon, brace mismatch)
- Zone file error (missing trailing dot on FQDNs)
- Permission denied on zone files (wrong ownership or SELinux context)

### Queries return SERVFAIL

```bash
# Check if named is listening
sudo ss -ulnp | grep :53
sudo ss -tlnp | grep :53

# Check named logs
sudo tail -50 /var/named/data/named.run
```

Common causes:
- Zone file syntax error (loaded but contains invalid records)
- DNSSEC validation failure on forwarded queries

### Client cannot reach DNS server

```bash
# From client
dig @192.168.60.11 admin.lab.local

# If timeout: check firewall on admin node
ssh admin "sudo firewall-cmd --list-services"

# Check that named listens on the network interface (not just 127.0.0.1)
ssh admin "sudo ss -ulnp | grep :53"
```

### Permission denied errors

```bash
# Check SELinux
sudo ausearch -m avc -ts recent | grep named

# Check file ownership
ls -laZ /var/named/

# Fix contexts
sudo restorecon -Rv /var/named/
```

### SOA serial number not incremented

If you edit a zone file but forget to increment the serial number, secondary
servers (or caches) will not pick up the change. Always update the serial
in YYYYMMDDNN format.

---

## Architecture Decision Rationale

### Why BIND over alternatives (dnsmasq, Unbound)?

- **BIND** is the industry standard for authoritative DNS. It supports zone
  files, DNSSEC, dynamic updates, views, and split-horizon DNS. It is what
  enterprise environments run and what interviewers expect you to know.
- **dnsmasq** is lightweight and great for small-scale DNS/DHCP but lacks
  features needed for enterprise authoritative DNS.
- **Unbound** is a recursive-only resolver; it cannot serve authoritative
  zones. It is a good complement to BIND (Unbound as resolver, BIND as
  authoritative) but not a replacement.

### Why include SRV records?

Kerberos clients use DNS SRV records to discover KDC servers. Including them
in the forward zone eliminates the need to hardcode the KDC address in
`/etc/krb5.conf` and demonstrates production-like DNS integration.

### Forward zone vs reverse zone

Forward zones (name to IP) are used by applications and users. Reverse zones
(IP to name) are used by logging systems, SSH host verification, and mail
servers. Both are expected in any enterprise DNS deployment.

---

## Interview Talking Points

**Q: Explain the difference between an authoritative and recursive DNS server.**
A: An authoritative server has definitive answers for zones it hosts (e.g.,
lab.local). A recursive server queries other servers on behalf of clients to
resolve names it does not host. BIND can be configured as either or both.

**Q: What is the significance of the trailing dot in zone files?**
A: The trailing dot denotes a fully qualified domain name (FQDN). Without it,
BIND appends the zone origin. So `admin.lab.local` in the lab.local zone
becomes `admin.lab.local.lab.local`, which is a common misconfiguration.

**Q: How do you troubleshoot DNS resolution failures?**
A: Start with `dig @server name` to test the specific server. Check if named
is running and listening (ss -tlnp). Validate zone files with
named-checkzone. Check firewall for port 53. Check SELinux denials. Review
/var/named/data/named.run for logs.

**Q: What is a PTR record and why does it matter?**
A: PTR records map IP addresses back to hostnames (reverse DNS). They are
used by many services for verification: SSH may check reverse DNS on
connecting clients, mail servers check PTR records to reject spam, and
logging systems use them for readable hostnames.

**Q: How do you add a new host to DNS?**
A: Add an A record to the forward zone file, a PTR record to the reverse zone
file, increment the SOA serial in both files, validate with named-checkzone,
and reload named with `rndc reload` or `systemctl reload named`.

**Q: What DNS record types should you know?**
A: A (IPv4 address), AAAA (IPv6), CNAME (alias), MX (mail exchange), NS
(name server), PTR (reverse lookup), SOA (start of authority), SRV (service
location), TXT (arbitrary text, used for SPF/DKIM/DMARC).
