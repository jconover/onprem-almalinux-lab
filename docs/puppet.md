# Puppet Configuration Management

## 1. Overview

Puppet is a **declarative**, model-driven configuration management tool that ensures
systems converge to a desired state. This lab uses Puppet to manage all AlmaLinux 10
nodes -- bastion, admin, app, and db -- using the **role/profile pattern**, Hiera
data lookups, EPP templates, and r10k for module management.

Puppet is a critical skill for Senior Linux Admin roles because many enterprises
adopted it before Ansible existed. Understanding both tools, and when to choose
each, is a common interview differentiator.

### Puppet vs Ansible Comparison

| Aspect              | Puppet                              | Ansible                                |
|---------------------|-------------------------------------|----------------------------------------|
| **Paradigm**        | Declarative (desired state)         | Procedural / Declarative hybrid        |
| **Architecture**    | Agent-based (pull model)            | Agentless (push via SSH)               |
| **Language**        | Puppet DSL (Ruby-based)             | YAML playbooks + Jinja2 templates      |
| **Idempotency**     | Built into the resource model       | Module-dependent                       |
| **Ordering**        | Dependency graph (unordered by default) | Top-to-bottom task execution       |
| **Data Separation** | Hiera (hierarchical)                | group_vars / host_vars / vault         |
| **Secret Mgmt**     | hiera-eyaml, Vault                  | ansible-vault                          |
| **Testing**         | rspec-puppet, PDK                   | Molecule, ansible-lint                 |
| **Module Ecosystem**| Puppet Forge                        | Ansible Galaxy / Collections           |
| **Reporting**       | PuppetDB + Puppet Enterprise        | AWX / Ansible Tower                    |
| **Drift Detection** | Agent runs every 30 min by default  | Manual --check --diff runs             |
| **Best For**        | Continuous config enforcement        | Ad-hoc tasks, orchestration, cloud     |

**Key Insight**: Puppet enforces state *continuously* via agent runs. Ansible
runs on demand. In a mature enterprise, both often coexist -- Puppet for
baseline OS config enforcement, Ansible for orchestration and application
deployments.

---

## 2. Architecture

### Lab Nodes and Roles

```
site.pp (node classification)
  |
  |-- node 'alma10-app', 'alma10-app2'  -->  role::app_server
  |-- node 'alma10-db'                  -->  role::db_server
  |-- node 'alma10-admin'               -->  role::admin_server
  |-- node 'alma10-bastion'             -->  role::bastion
  |-- node default                      -->  profile::base + firewall + monitoring
```

### Directory Layout

```
puppet/
  Puppetfile              # r10k module declarations (forge + git)
  environment.conf        # modulepath, manifest, environment_timeout
  hiera.yaml              # Hiera 5 hierarchy definition
  manifests/
    site.pp               # Node classification (entry point)
  data/
    common.yaml           # Default values for all nodes
    nodes/
      alma10-app.yaml     # Per-node overrides
      alma10-app2.yaml
      alma10-db.yaml
      alma10-admin.yaml
      alma10-bastion.yaml
  modules/
    role/
      manifests/
        app_server.pp     # Role: app -> base + web + firewall + monitoring
        db_server.pp      # Role: db  -> base + db + firewall + nfs + monitoring
        admin_server.pp   # Role: admin -> base + dns + firewall + monitoring
        bastion.pp        # Role: bastion -> base + haproxy + firewall + monitoring
    profile/
      manifests/
        base.pp           # Packages, SELinux, chrony, sysctl, MOTD
        firewall.pp       # firewalld per-role services via Hiera
        web.pp            # Apache httpd with EPP vhost template
        db.pp             # MariaDB server, secure install, app db/user
        dns.pp            # BIND named.conf + zone files
        nfs_server.pp     # NFS exports, SELinux booleans
        haproxy.pp        # HAProxy LB config, SELinux boolean
        monitoring.pp     # Prometheus node_exporter
      templates/
        sysctl.conf.epp
        motd.epp
        vhost.conf.epp
        server.cnf.epp
        named.conf.epp
        zone.db.epp
        exports.epp
        haproxy.cfg.epp
        node_exporter.service.epp
```

---

## 3. Prerequisites

- AlmaLinux 10 cluster running via `make up-alma10`
- Puppet agent installed (the provision script handles this)
- r10k installed for module management
- Puppet modules declared in `Puppetfile` deployed to `modules/`

### Packages Installed by Provisioning

```bash
# provision-puppet.sh installs:
sudo dnf install -y puppet-agent
# Adds /opt/puppetlabs/bin to PATH
```

---

## 4. Step-by-Step Setup / Deep Dive

### 4.1 Puppet Language Fundamentals

#### Resources -- The Atomic Unit

Every Puppet manifest is a collection of **resources**. A resource declares the
desired state of a single system entity:

```puppet
# Ensure a package is installed
package { 'httpd':
  ensure => installed,
}

# Ensure a service is running and enabled
service { 'httpd':
  ensure  => running,
  enable  => true,
  require => Package['httpd'],   # ordering metaparameter
}

# Ensure a file exists with specific content
file { '/etc/httpd/conf.d/vhost.conf':
  ensure  => file,
  content => epp('profile/vhost.conf.epp', { ... }),
  owner   => 'root',
  mode    => '0644',
  notify  => Service['httpd'],   # triggers refresh on change
}
```

**Core resource types**: `package`, `service`, `file`, `exec`, `user`, `group`,
`cron`, `mount`, `firewall`, `selboolean`, `sysctl`.

#### Classes -- Grouping Resources

A **class** is a named collection of resources that can be `include`d on a node:

```puppet
class profile::base (
  Array[String] $packages = lookup('profile::base::packages'),
) {
  package { $packages:
    ensure => installed,
  }
}
```

#### Modules -- Reusable Units

A **module** is a directory following Puppet's autoloading convention:

```
mymodule/
  manifests/
    init.pp       # class mymodule { ... }
    config.pp     # class mymodule::config { ... }
  templates/      # EPP/ERB templates
  files/          # Static files
  lib/
    facter/       # Custom facts
```

#### Defined Types -- Parameterized Resource Wrappers

When you need to create multiple instances of a resource pattern:

```puppet
define profile::firewall_service (
  String $zone = 'public',
) {
  exec { "firewall-allow-${name}":
    command => "/usr/bin/firewall-cmd --permanent --zone=${zone} --add-service=${name}",
    unless  => "/usr/bin/firewall-cmd --zone=${zone} --query-service=${name}",
    notify  => Exec['firewall-reload'],
  }
}
```

### 4.2 The Role/Profile Pattern

This is the **most important Puppet design pattern** and a guaranteed interview topic.

#### The Hierarchy

```
site.pp          # "Which role does this node get?"
  -> role        # "What is this machine's business purpose?"
    -> profiles  # "What technology stacks does this role need?"
      -> modules # "How is this specific technology configured?"
```

#### Rules

1. A node includes **exactly one role**.
2. A role includes **one or more profiles** and nothing else.
3. A profile includes **modules and resources** -- this is where the logic lives.
4. Profiles read data from **Hiera** -- no hardcoded values.

#### Lab Implementation

**site.pp** -- Node-to-role mapping:

```puppet
node 'alma10-app', 'alma10-app2' {
  include role::app_server
}

node 'alma10-db' {
  include role::db_server
}

node 'alma10-admin' {
  include role::admin_server
}

node 'alma10-bastion' {
  include role::bastion
}

node default {
  include profile::base
  include profile::firewall
  include profile::monitoring
}
```

**role::app_server** -- What an app server is:

```puppet
class role::app_server {
  include profile::base        # OS baseline
  include profile::web         # Apache httpd
  include profile::firewall    # Per-node firewall rules
  include profile::monitoring  # node_exporter
}
```

**role::db_server** -- What a database server is:

```puppet
class role::db_server {
  include profile::base
  include profile::db           # MariaDB
  include profile::firewall
  include profile::nfs_server   # NFS exports
  include profile::monitoring
}
```

**profile::web** -- How Apache is configured (actual lab code):

```puppet
class profile::web (
  String  $server_name = lookup('profile::web::server_name', ...),
  String  $doc_root    = lookup('profile::web::doc_root', ...),
  Integer $listen_port = lookup('profile::web::listen_port', ...),
) {
  package { ['httpd', 'mod_ssl']:
    ensure => installed,
  }

  file { '/etc/httpd/conf.d/vhost.conf':
    ensure  => file,
    content => epp('profile/vhost.conf.epp', { ... }),
    require => Package['httpd'],
    notify  => Service['httpd'],
  }

  service { 'httpd':
    ensure  => running,
    enable  => true,
    require => Package['httpd'],
  }
}
```

### 4.3 Hiera Data in Practice

Hiera separates **data** from **code**. This lab uses Hiera 5.

#### Hierarchy Configuration (`hiera.yaml`)

```yaml
---
version: 5
defaults:
  datadir: data
  data_hash: yaml_data

hierarchy:
  - name: "Per-node data"
    path: "nodes/%{trusted.certname}.yaml"
  - name: "Common data"
    path: "common.yaml"
```

**Lookup order**: Per-node data wins over common data. This lets you set defaults
in `common.yaml` and override per node.

#### Common Defaults (`data/common.yaml`)

```yaml
profile::base::packages:
  - vim
  - firewalld
  - chrony
  - policycoreutils-python-utils
  - setools-console
  - bind-utils
  - tcpdump
  - net-tools
  - lvm2
  - tar
  - rsync

profile::base::timezone: America/New_York
profile::base::domain: lab.local
profile::base::selinux_mode: enforcing
profile::monitoring::node_exporter_version: '1.7.0'
```

#### Per-Node Overrides (`data/nodes/alma10-db.yaml`)

```yaml
profile::firewall::allowed_services:
  - mysql
  - nfs
  - mountd
  - rpc-bind

profile::db::db_name: appdb
profile::db::db_user: appuser
profile::db::db_password: 'LabApp2024!'
profile::db::root_password: 'LabRoot2024!'
profile::db::bind_address: '0.0.0.0'
profile::db::innodb_buffer_pool_size: '256M'
```

#### Lookup Functions

```puppet
# Explicit lookup with merge strategy
$packages = lookup('profile::base::packages', Array, 'unique', [])

# Automatic parameter binding -- Hiera key matches class::param
class profile::base (
  Array[String] $packages = [],  # Hiera auto-binds profile::base::packages
) { ... }
```

**Merge strategies**: `first` (default), `unique` (array merge), `hash` (hash merge),
`deep` (recursive hash merge).

### 4.4 EPP vs ERB Templates

This lab uses **EPP** (Embedded Puppet) exclusively. EPP is the modern standard.

| Feature          | EPP                        | ERB                       |
|------------------|----------------------------|---------------------------|
| **Language**     | Puppet DSL                 | Ruby                      |
| **Tag syntax**   | `<%= $var %>`, `<% ... %>` | `<%= @var %>`, `<% ... %>`|
| **Function call**| `epp('template', {hash})`  | `template('template')`    |
| **Validation**   | `puppet epp validate`      | Ruby syntax only          |
| **Recommended**  | Yes (modern Puppet)        | Legacy                    |

Example EPP template from the lab (`sysctl.conf.epp`):

```epp
<%- | Hash $settings | -%>
# Managed by Puppet -- DO NOT EDIT
<% $settings.each |$key, $value| { -%>
<%= $key %> = <%= $value %>
<% } -%>
```

### 4.5 Running Puppet in the Lab

Since this lab uses `puppet apply` (masterless mode), the command is:

```bash
sudo /opt/puppetlabs/bin/puppet apply \
  --modulepath=/vagrant/puppet/modules \
  /vagrant/puppet/manifests/site.pp \
  --hiera_config=/vagrant/puppet/hiera.yaml
```

**Useful flags**:

```bash
# Dry run (noop mode)
puppet apply --noop manifests/site.pp

# Verbose output
puppet apply --verbose --debug manifests/site.pp

# Show detailed diff for file changes
puppet apply --show_diff manifests/site.pp

# Specific environment (for multi-environment setups)
puppet apply --environment=production manifests/site.pp
```

### 4.6 r10k Workflow

r10k manages Puppet modules declared in the `Puppetfile` and can deploy
environment-specific branches.

#### Puppetfile (Lab)

```ruby
forge "https://forgeapi.puppetlabs.com"

mod 'puppetlabs-stdlib',    '9.0.0'
mod 'puppetlabs-firewall',  '7.0.0'
mod 'puppetlabs-concat',    '9.0.0'
mod 'puppetlabs-ntp',       '10.0.0'
mod 'puppetlabs-mysql',     '15.0.0'
mod 'puppetlabs-apache',    '12.0.0'
mod 'puppet-selinux',       '4.0.0'
```

#### r10k Commands

```bash
# Install/update modules from Puppetfile
r10k puppetfile install --verbose

# Deploy all environments (branch-based)
r10k deploy environment --puppetfile

# Deploy specific environment
r10k deploy environment production --puppetfile
```

#### Control Repo Branching for r10k

```
main (production environment)
  |
  +-- feature/add-nginx-profile    (creates 'feature_add_nginx_profile' environment)
  +-- staging                      (creates 'staging' environment)
```

Each Git branch becomes a Puppet environment. Agents can be pointed to any
environment for testing: `puppet agent -t --environment=staging`.

### 4.7 Facter

Facter collects system facts that Puppet manifests use for conditional logic.

```bash
# List all facts
facter

# Specific fact
facter os.name                   # => AlmaLinux
facter os.release.major          # => 10
facter networking.ip             # => 192.168.60.12
facter networking.hostname       # => alma10-app
facter processors.count          # => 2
facter memory.system.total       # => 2.00 GiB

# JSON output
facter --json networking
```

**In manifests**: `$facts['networking']['hostname']`, `$facts['os']['family']`.

**Custom facts**: Place Ruby files in `lib/facter/` within a module:

```ruby
# modules/profile/lib/facter/datacenter.rb
Facter.add(:datacenter) do
  setcode do
    'us-east-1'
  end
end
```

---

## 5. Verification / Testing

### Syntax Validation

```bash
# Validate all manifests
make puppet-validate
# Or directly:
find puppet/manifests puppet/modules -name '*.pp' -exec puppet parser validate {} +

# Validate EPP templates
puppet epp validate puppet/modules/profile/templates/vhost.conf.epp

# Validate Hiera YAML
ruby -ryaml -e "YAML.load_file('puppet/data/common.yaml')"
```

### Dry Run

```bash
# Noop mode shows what WOULD change without applying
sudo puppet apply --noop --show_diff \
  --modulepath=/vagrant/puppet/modules \
  /vagrant/puppet/manifests/site.pp \
  --hiera_config=/vagrant/puppet/hiera.yaml
```

### Testing Framework (rspec-puppet)

```ruby
# spec/classes/profile_web_spec.rb
require 'spec_helper'

describe 'profile::web' do
  let(:facts) do
    { networking: { hostname: 'alma10-app', fqdn: 'alma10-app.lab.local' } }
  end

  it { is_expected.to compile.with_all_deps }
  it { is_expected.to contain_package('httpd') }
  it { is_expected.to contain_service('httpd').with(ensure: 'running') }
  it { is_expected.to contain_file('/etc/httpd/conf.d/vhost.conf') }
end
```

### PDK (Puppet Development Kit)

```bash
# Create new module skeleton
pdk new module mymodule

# Create new class
pdk new class mymodule::config

# Run unit tests
pdk test unit

# Validate syntax and style
pdk validate
```

---

## 6. Troubleshooting

### Dependency Cycles

**Symptom**: `Error: Could not apply complete catalog: Found dependency cycle`

```bash
# Generate dependency graph for analysis
puppet apply --graph manifests/site.pp
dot -Tpng /opt/puppetlabs/puppet/cache/state/graphs/expanded_relationships.dot -o deps.png
```

**Common causes**: Circular `require`/`before`/`notify`/`subscribe` chains.
Fix by using `contain` instead of `include` or removing redundant relationships.

### Catalog Compilation Errors

**Symptom**: `Error: Could not retrieve catalog from remote server`

```bash
# Test catalog compilation locally
puppet apply --noop --trace manifests/site.pp

# Check for Hiera lookup failures
puppet lookup profile::base::packages --explain

# Validate individual files
puppet parser validate manifests/site.pp
```

### Fact Resolution Failures

```bash
# Debug fact collection
facter --debug 2>&1 | grep -i error

# Test custom fact
FACTERLIB=modules/profile/lib/facter facter datacenter
```

### Common Error Patterns

| Error | Cause | Fix |
|-------|-------|-----|
| `Could not find class ::role::app_server` | Missing modulepath | Add `--modulepath` with correct path |
| `Parameter 'ensure' expects a String value, got Integer` | Type mismatch in Hiera | Quote the value in YAML |
| `Duplicate declaration: Package[httpd]` | Two classes declare the same resource | Use `ensure_packages()` from stdlib |
| `Could not find template 'profile/foo.epp'` | Template not in module's templates/ dir | Check path: `modules/profile/templates/foo.epp` |
| `Evaluation Error: Unknown variable: '$foo'` | Variable not in scope | Use fully qualified name or check Hiera |

---

## 7. Architecture Decision Rationale

### Why Puppet Apply (Masterless) for This Lab

**Decision**: Use `puppet apply` (local compilation) instead of a Puppet Server.

**Rationale**:
- No need for a dedicated Puppet Server VM (saves resources)
- Simpler for a lab environment -- manifests are on the shared `/vagrant` mount
- Same code works with or without a master
- Demonstrates `puppet apply` which is useful for bootstrapping and testing
- Production: would use Puppet Server for central reporting, PuppetDB, orchestration

### Why Role/Profile Pattern

**Decision**: Structure code as site.pp -> role -> profile -> module.

**Rationale**:
- Industry standard endorsed by Puppet (former company)
- Separates business logic (roles) from technical implementation (profiles)
- A node has exactly one role, making classification simple
- Profiles are composable across roles
- Makes testing straightforward -- test profiles in isolation
- Alternative (flat manifests) does not scale past a few dozen nodes

### Why Hiera 5

**Decision**: Use Hiera 5 with YAML backend.

**Rationale**:
- Per-environment hierarchy (in `hiera.yaml` at environment root)
- Cleaner than Hiera 3 global config
- Automatic parameter binding reduces boilerplate `lookup()` calls
- YAML backend is simplest; can upgrade to eyaml for secrets without code changes

### Why EPP over ERB

**Decision**: Use EPP templates exclusively.

**Rationale**:
- EPP uses Puppet DSL, which is already familiar to Puppet users
- No need for Ruby knowledge to write templates
- `puppet epp validate` provides static validation
- ERB is legacy; EPP is the documented standard for new code

---

## 8. Interview Talking Points

### "Describe the role/profile pattern."

> "The role/profile pattern is a layered design approach for Puppet code. At the
> top, `site.pp` classifies each node into exactly one role -- like `role::app_server`.
> That role includes multiple profiles, each representing a technology stack --
> like `profile::base`, `profile::web`, and `profile::firewall`. Profiles contain
> the actual Puppet code and module includes. Data comes from Hiera, never
> hardcoded. This gives you composable, testable, reusable building blocks.
> In my lab, `role::db_server` includes five profiles covering base OS, MariaDB,
> firewall, NFS exports, and monitoring."

### "How do you handle environment promotion?"

> "We use r10k with a control repo where Git branches map to Puppet environments.
> A feature branch creates an isolated environment for testing. Developers test
> on their feature environment, merge to a staging branch for integration testing,
> then merge to production. The Puppetfile pins module versions, so each
> environment gets reproducible dependencies. CI runs `puppet parser validate`
> and rspec-puppet on every PR."

### "How do you test Puppet code?"

> "Three layers: First, `puppet parser validate` and `puppet-lint` for syntax
> and style. Second, rspec-puppet unit tests verify catalog compilation and
> resource containment. Third, Beaker or Litmus acceptance tests spin up actual
> VMs and verify real system state. PDK wraps all of this into a standard
> workflow. In CI, syntax checks run on every commit, unit tests on every PR,
> and acceptance tests nightly or on release branches."

### "How do you manage secrets in Puppet?"

> "Hiera-eyaml encrypts sensitive values inline in YAML files using asymmetric
> encryption. Each environment has its own keypair. For rotation, you can
> re-encrypt with new keys. For more sophisticated needs, the `puppet-vault`
> module integrates with HashiCorp Vault for dynamic secrets. The lab currently
> stores passwords in plain YAML for simplicity but would use eyaml in production."

### "What's the difference between `include`, `contain`, and `require` in Puppet?"

> "`include` declares a class but does not create ordering relationships with the
> including class. `contain` is like include but also anchors the contained class
> inside the containing class, so ordering applied to the outer class flows
> through. `require` is a metaparameter that creates a dependency edge -- the
> current resource will not be applied until the required resource succeeds.
> In the role/profile pattern, profiles should `contain` classes they compose
> so that roles get predictable ordering."

### "How does Puppet handle drift detection?"

> "The Puppet agent runs every 30 minutes by default. Each run compiles a catalog
> (desired state) and compares it to the actual state. Any drift is corrected
> automatically, and the change is reported to PuppetDB. You can audit drift
> without correcting it using `puppet agent -t --noop`. PuppetDB and the PE
> console provide dashboards showing which nodes have corrective changes vs
> intentional changes."

### "Puppet vs Ansible -- when do you use each?"

> "I use Puppet for continuous state enforcement of OS-level configuration --
> packages, services, files, SELinux booleans, firewall rules, NTP, sysctl.
> Things that should always be in a known state. I use Ansible for orchestration,
> application deployments, one-time provisioning tasks, and anything that involves
> ordering across multiple hosts (rolling restarts, database migrations). In this
> lab, Puppet manages per-node configuration and Ansible handles multi-node
> orchestration like deploying SSSD across all clients."
