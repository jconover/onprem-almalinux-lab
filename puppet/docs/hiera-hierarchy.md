# Puppet Hiera Hierarchy Guide

This document explains how Hiera data lookup works in this Puppet environment, including best practices for organizing configuration data across nodes, roles, datacenters, and environments.

## Hierarchy Overview

Hiera uses a layered hierarchy to look up configuration values. When Puppet requests a value, Hiera searches from the most specific level to the least specific, returning the first match found.

```
┌─────────────────────────────────────────────────────────────┐
│  1. Encrypted secrets (HIGHEST PRIORITY)                    │
│     secrets.eyaml                                           │
├─────────────────────────────────────────────────────────────┤
│  2. Per-node encrypted secrets                              │
│     nodes/%{trusted.certname}.eyaml                         │
├─────────────────────────────────────────────────────────────┤
│  3. Per-node data                                           │
│     nodes/%{trusted.certname}.yaml                          │
├─────────────────────────────────────────────────────────────┤
│  4. Per-role data                                           │
│     roles/%{trusted.extensions.pp_role}.yaml                │
├─────────────────────────────────────────────────────────────┤
│  5. Per-datacenter data                                     │
│     datacenters/%{facts.datacenter}.yaml                    │
├─────────────────────────────────────────────────────────────┤
│  6. Per-environment data                                    │
│     environments/%{environment}.yaml                        │
├─────────────────────────────────────────────────────────────┤
│  7. Common data (LEAST SPECIFIC)                            │
│     common.yaml                                             │
└─────────────────────────────────────────────────────────────┘
```

## Hierarchy Levels Explained

### 1. Encrypted Secrets (`secrets.eyaml`)

**When to use:** Global secrets that need to be encrypted at rest, such as API keys or shared credentials.

**Source:** Static file checked into version control with encrypted values.

**Examples:**
- Database passwords shared across environments
- API keys for external services
- SSL certificate private keys

```yaml
# secrets.eyaml
profile::database::root_password: ENC[PKCS7,MIIBiQYJKoZIhvc...]
profile::api::secret_key: ENC[PKCS7,MIIBeQYJKoZIhvc...]
```

### 2. Per-Node Encrypted Secrets (`nodes/<certname>.eyaml`)

**When to use:** Node-specific secrets that need encryption.

**Source:** `%{trusted.certname}` - Node-specific encrypted data files.

**Examples:**
- Host-specific SSL certificates
- Node-specific API tokens
- Unique database credentials

```yaml
# nodes/db01.prod.lab.local.eyaml
profile::postgresql::replication_password: ENC[PKCS7,MIIBmQYJKoZI...]
```

### 3. Per-Node Data (`nodes/<certname>.yaml`)

**When to use:** Node-specific overrides that apply to exactly one server.

**Source:** `%{trusted.certname}` - The certificate name from the node's SSL certificate.

**Examples:**
- Custom memory settings for a specific high-traffic server
- Unique IP addresses or hostnames
- One-off configuration exceptions

```yaml
# nodes/web01.prod.lab.local.yaml
profile::java::heap_max: 8g
profile::app::custom_jvm_opts: "-XX:+UseZGC"
```

### 4. Per-Role Data (`roles/<role>.yaml`)

**When to use:** Configuration shared by all nodes performing the same function.

**Source:** `%{trusted.extensions.pp_role}` - A certificate extension set during node provisioning.

**Examples:**
- Application servers need Java and specific ports
- Database servers need PostgreSQL packages and tuning
- Web servers need nginx and SSL certificates

```yaml
# roles/app_server.yaml
profile::base::packages:
  - java-17-openjdk
profile::firewall::rules:
  app_port:
    port: 8080
    protocol: tcp
```

**Setting the role:** The `pp_role` extension must be added to the node's certificate at signing time:

```bash
puppetserver ca sign --certname web01.lab.local \
  --ext pp_role:app_server
```

### 5. Per-Datacenter Data (`datacenters/<datacenter>.yaml`)

**When to use:** Location-specific configuration like network settings, DNS servers, or NTP servers.

**Source:** `%{facts.datacenter}` - A custom fact that identifies the physical or logical datacenter.

**Examples:**
- Different NTP servers per datacenter
- Datacenter-specific network ranges
- Regional backup targets

```yaml
# datacenters/us-east-1.yaml
profile::base::ntp_servers:
  - ntp1.us-east-1.lab.local
  - ntp2.us-east-1.lab.local
profile::network::dns_servers:
  - 10.1.0.10
  - 10.1.0.11
```

**Creating the datacenter fact:** Create a custom fact on each node:

```ruby
# /etc/puppetlabs/facter/facts.d/datacenter.rb
Facter.add(:datacenter) do
  setcode do
    'us-east-1'
  end
end
```

Or as a simple text file:

```bash
# /etc/puppetlabs/facter/facts.d/datacenter.txt
datacenter=us-east-1
```

### 6. Per-Environment Data (`environments/<environment>.yaml`)

**When to use:** Settings that differ between development, staging, and production.

**Source:** `%{environment}` - The Puppet environment the node is assigned to.

**Examples:**
- Debug logging in development, warn in production
- Stricter security settings in production
- Different backup retention periods

```yaml
# environments/production.yaml
profile::base::selinux_mode: enforcing
profile::logging::log_level: warn
profile::backup::retention_days: 30
```

### 7. Common Data (`common.yaml`)

**When to use:** Default values that apply to all nodes unless overridden.

**Examples:**
- Base packages installed everywhere
- Default timezone
- Organization-wide security settings

```yaml
# common.yaml
profile::base::timezone: America/New_York
profile::base::domain: lab.local
```

## Data Lookup Examples

### Example 1: Simple Lookup

For a production app server named `web01.prod.lab.local`:

```puppet
$heap_max = lookup('profile::java::heap_max')
```

Hiera searches:
1. `nodes/web01.prod.lab.local.yaml` - Not found
2. `roles/app_server.yaml` - Found: `2g`

Result: `$heap_max = '2g'`

### Example 2: Node Override

If `nodes/web01.prod.lab.local.yaml` contains:

```yaml
profile::java::heap_max: 8g
```

Then `$heap_max = '8g'` (node-level wins)

### Example 3: Hash Merging

By default, Hiera returns the first match. For merging hashes across levels, use lookup options:

```puppet
$sysctl = lookup('profile::base::sysctl_settings', {
  'merge' => 'deep',
})
```

Or define merge behavior in `common.yaml`:

```yaml
lookup_options:
  profile::base::sysctl_settings:
    merge: deep
  profile::firewall::rules:
    merge: hash
```

### Example 4: Array Merging

To combine arrays from multiple hierarchy levels:

```yaml
# In common.yaml
lookup_options:
  profile::base::packages:
    merge: unique
```

## Best Practices

### 1. Start Broad, Override Specifically

Define sensible defaults in `common.yaml` and only override where necessary. This reduces duplication and makes the configuration easier to understand.

### 2. Use Roles for Functional Grouping

Avoid putting role-specific data in environment or node files. If multiple nodes share the same function, create a role for them.

### 3. Keep Node Data Minimal

Node-level data should be the exception, not the rule. If you find yourself copying data between node files, consider creating a role or updating common.yaml.

### 4. Document Non-Obvious Values

Add comments explaining why a value differs from the default:

```yaml
# Increased heap for high-traffic holiday season
profile::java::heap_max: 16g
```

### 5. Use Meaningful Variable Names

Namespace your Hiera keys by profile or module:

```yaml
# Good
profile::postgresql::max_connections: 200

# Bad
max_connections: 200
```

### 6. Validate Data Types

Use Puppet's type system to catch configuration errors early:

```puppet
class profile::postgresql (
  Integer $max_connections = lookup('profile::postgresql::max_connections'),
  String  $data_dir        = lookup('profile::postgresql::data_dir'),
) {
  # ...
}
```

### 7. Test Lookups Before Deploying

Use `puppet lookup` to verify values before applying:

```bash
# On the Puppet server
puppet lookup profile::java::heap_max --node web01.prod.lab.local

# With debug output showing hierarchy
puppet lookup profile::java::heap_max --node web01.prod.lab.local --explain
```

## Directory Structure

```
puppet/
├── hiera.yaml                 # Hierarchy configuration
└── data/
    ├── common.yaml            # Global defaults
    ├── secrets.eyaml          # Encrypted global secrets
    ├── environments/
    │   ├── production.yaml    # Production settings
    │   └── development.yaml   # Development settings
    ├── datacenters/
    │   ├── us-east-1.yaml     # US East datacenter
    │   └── us-west-1.yaml     # US West datacenter
    ├── roles/
    │   ├── app_server.yaml    # Application servers
    │   ├── db_server.yaml     # Database servers
    │   └── web_server.yaml    # Web servers
    └── nodes/
        ├── web01.prod.lab.local.yaml   # Node-specific overrides
        └── web01.prod.lab.local.eyaml  # Node-specific encrypted secrets
```

## Troubleshooting

### Value Not Found

Check that:
1. The YAML file exists in the correct location
2. The key name matches exactly (case-sensitive)
3. The variable interpolation is working (`--explain` flag helps)

### Wrong Value Returned

Use `puppet lookup --explain` to see which hierarchy level provided the value:

```bash
puppet lookup profile::base::selinux_mode --node web01.prod.lab.local --explain
```

### Merge Not Working

Ensure merge behavior is configured in `lookup_options` and that you're using the correct merge strategy (`deep`, `hash`, or `unique`).
