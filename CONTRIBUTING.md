# Contributing to Enterprise On-Prem Linux Administration Lab

Thank you for your interest in contributing to this project! Whether you're fixing a typo, improving documentation, adding a new feature, or reporting a bug, your contributions help make this lab environment better for everyone learning enterprise Linux administration.

---

## Table of Contents

- [Ways to Contribute](#ways-to-contribute)
- [Development Setup](#development-setup)
- [Code Standards](#code-standards)
- [Pull Request Process](#pull-request-process)
- [Commit Message Guidelines](#commit-message-guidelines)
- [Code of Conduct](#code-of-conduct)

---

## Ways to Contribute

### Documentation Improvements
- Fix typos, grammatical errors, or unclear explanations
- Add missing steps or clarify existing procedures
- Improve architecture diagrams or add new ones
- Add troubleshooting scenarios based on your experience
- Translate documentation (coordinate with maintainers first)

### Bug Fixes
- Fix broken Ansible playbooks or roles
- Correct Puppet manifests that fail to compile or apply
- Resolve Terraform configuration errors
- Fix Vagrantfile provisioning issues
- Address shell script bugs in provisioning scripts

### New Features
- Add new Ansible roles for additional services
- Create new Puppet profiles following the role/profile pattern
- Extend Terraform modules for additional cloud resources
- Add new break-fix scenarios for troubleshooting practice
- Implement new lab exercises for skill development

### Testing
- Add Molecule tests for Ansible roles
- Create rspec-puppet unit tests for Puppet modules
- Add Terraform validation tests
- Improve CI/CD pipeline coverage
- Test on different host environments and report compatibility

---

## Development Setup

### Prerequisites

1. **Host System Requirements**
   - Linux host with KVM/libvirt support (tested on Fedora, Ubuntu, AlmaLinux)
   - Minimum 16 GB RAM (32 GB recommended for running full cluster)
   - 50 GB free disk space

2. **Required Software**
   ```bash
   # Install Vagrant with libvirt provider
   sudo dnf install -y vagrant libvirt qemu-kvm virt-manager
   # or on Ubuntu/Debian:
   # sudo apt install -y vagrant libvirt-daemon-system qemu-kvm virt-manager

   vagrant plugin install vagrant-libvirt

   # Install Ansible (for local testing)
   pip install ansible ansible-lint yamllint molecule

   # Install Puppet development tools
   gem install puppet-lint r10k

   # Install Terraform
   sudo dnf install -y terraform
   # or via tfenv for version management
   ```

3. **Clone the Repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/onprem-almalinux-lab.git
   cd onprem-almalinux-lab
   ```

4. **Start the Lab Environment**
   ```bash
   # Start AlmaLinux 10 cluster
   make up-alma10

   # Or AlmaLinux 9 cluster
   make up-alma9

   # SSH into nodes
   vagrant ssh alma10-bastion
   ```

### Running Tests Locally

```bash
# Ansible linting
ansible-lint ansible/site.yml
yamllint ansible/

# Puppet validation
find puppet/manifests puppet/modules -name '*.pp' -exec puppet parser validate {} +
puppet-lint puppet/modules/

# Terraform validation
cd terraform/environments/dev
terraform init
terraform validate
terraform fmt -check
```

---

## Code Standards

### Ansible Conventions

- **Role Structure**: Follow Ansible best practices for role layout
  ```
  roles/myservice/
    tasks/main.yml
    handlers/main.yml
    templates/
    files/
    vars/main.yml
    defaults/main.yml
    meta/main.yml
  ```

- **Task Naming**: Use descriptive, action-oriented names
  ```yaml
  # Good
  - name: Install Apache httpd package
    ansible.builtin.dnf:
      name: httpd
      state: present

  # Avoid
  - name: httpd
    dnf:
      name: httpd
  ```

- **Module Usage**: Prefer specific modules over command/shell
  ```yaml
  # Good
  - name: Enable and start firewalld
    ansible.builtin.service:
      name: firewalld
      state: started
      enabled: true

  # Avoid
  - name: Start firewalld
    ansible.builtin.command: systemctl enable --now firewalld
  ```

- **Idempotency**: Ensure tasks can run multiple times without side effects
- **Variables**: Use `defaults/main.yml` for configurable values
- **Handlers**: Use handlers for service restarts/reloads
- **Tags**: Add meaningful tags for selective execution

### Terraform Conventions

- **Module Design**: Single responsibility per module
  ```
  modules/vpc/
    main.tf
    variables.tf
    outputs.tf
    README.md
  ```

- **Variable Descriptions**: Document every variable
  ```hcl
  variable "vpc_cidr" {
    description = "CIDR block for the VPC"
    type        = string
    default     = "10.0.0.0/16"
  }
  ```

- **Output Values**: Export useful values for module composition
- **Naming**: Use snake_case for resources and variables
- **Formatting**: Run `terraform fmt` before committing
- **Tagging**: Include environment and project tags on all resources
  ```hcl
  tags = merge(var.tags, {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  })
  ```

### Puppet Conventions

- **Role/Profile Pattern**: Strictly follow the pattern
  - Roles include only profiles
  - Profiles include modules and contain logic
  - Data lives in Hiera, not manifests

- **Class Parameters**: Use Hiera automatic parameter binding
  ```puppet
  class profile::web (
    String  $server_name = lookup('profile::web::server_name'),
    Integer $listen_port = lookup('profile::web::listen_port', default_value => 80),
  ) {
    # ...
  }
  ```

- **Templates**: Use EPP over ERB
- **Resource Relationships**: Use explicit dependencies
  ```puppet
  package { 'httpd':
    ensure => installed,
  }
  -> file { '/etc/httpd/conf.d/vhost.conf':
    ensure  => file,
    content => epp('profile/vhost.conf.epp'),
  }
  ~> service { 'httpd':
    ensure => running,
    enable => true,
  }
  ```

- **Validation**: Run `puppet parser validate` and `puppet-lint` before committing

### Shell Script Conventions

- **Shebang**: Use `#!/bin/bash` and `set -euo pipefail`
  ```bash
  #!/bin/bash
  set -euo pipefail
  ```

- **Comments**: Document purpose and usage at the top of scripts
- **Error Handling**: Check command success and provide meaningful errors
- **Quoting**: Always quote variables: `"$variable"`
- **Functions**: Use functions for reusable logic
- **Naming**: Use lowercase with underscores for variables and functions

---

## Pull Request Process

1. **Fork and Branch**
   ```bash
   # Fork on GitHub, then:
   git clone https://github.com/YOUR_USERNAME/onprem-almalinux-lab.git
   cd onprem-almalinux-lab
   git checkout -b feature/your-feature-name
   ```

2. **Make Your Changes**
   - Keep changes focused and atomic
   - Follow the code standards above
   - Test your changes locally

3. **Run Validation**
   ```bash
   # Run all linters
   make lint   # if available, or run manually:
   ansible-lint ansible/site.yml
   puppet-lint puppet/modules/
   terraform fmt -check -recursive terraform/
   ```

4. **Commit Your Changes**
   - Follow the commit message guidelines below
   - Sign off your commits if required: `git commit -s`

5. **Push and Create PR**
   ```bash
   git push origin feature/your-feature-name
   ```
   Then create a Pull Request on GitHub.

6. **PR Requirements**
   - Clear title describing the change
   - Description explaining what and why
   - Link to any related issues
   - All CI checks must pass
   - At least one maintainer approval

7. **After Review**
   - Address review feedback promptly
   - Push additional commits (don't force-push during review)
   - Once approved, maintainers will merge

---

## Commit Message Guidelines

This project follows [Conventional Commits](https://www.conventionalcommits.org/) format.

### Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `docs` | Documentation changes only |
| `style` | Formatting, whitespace (no code change) |
| `refactor` | Code restructuring (no behavior change) |
| `test` | Adding or updating tests |
| `chore` | Maintenance tasks, dependencies, CI |

### Scopes

| Scope | Description |
|-------|-------------|
| `ansible` | Ansible playbooks and roles |
| `puppet` | Puppet manifests, modules, Hiera |
| `terraform` | Terraform configurations |
| `vagrant` | Vagrantfile and provisioning scripts |
| `docs` | Documentation files |
| `ci` | CI/CD pipelines |

### Examples

```
feat(ansible): add prometheus role for monitoring stack

Adds a new Ansible role that deploys Prometheus server with:
- Node exporter configuration
- Basic alerting rules
- Grafana data source

Closes #42

---

fix(puppet): correct SELinux boolean for HAProxy

The haproxy_connect_any boolean was not being set persistently,
causing SELinux denials after reboot.

---

docs(monitoring): add PromQL query examples

Adds practical PromQL examples for:
- CPU utilization alerts
- Disk space monitoring
- Network traffic analysis

---

chore(ci): add Terraform validation to PR workflow

Adds terraform fmt, validate, and plan steps to the
GitHub Actions workflow for pull requests.
```

### Commit Message Tips

- Use imperative mood: "Add feature" not "Added feature"
- Keep subject line under 72 characters
- Separate subject from body with blank line
- Explain what and why, not how
- Reference issues when applicable: "Closes #123" or "Fixes #456"

---

## Code of Conduct

### Our Standards

- **Be Respectful**: Treat everyone with respect and consideration
- **Be Constructive**: Provide helpful feedback focused on improvement
- **Be Inclusive**: Welcome contributors of all backgrounds and skill levels
- **Be Professional**: Keep discussions focused on the project

### Unacceptable Behavior

- Harassment, discrimination, or personal attacks
- Trolling or inflammatory comments
- Publishing others' private information
- Disruptive or unprofessional conduct

### Enforcement

Project maintainers will address violations by:
1. Warning the individual
2. Temporary or permanent ban from project participation

### Reporting

Report violations to the project maintainers via GitHub issues or direct contact.

---

## Questions?

If you have questions about contributing:

1. Check existing documentation and issues first
2. Open a GitHub issue for discussion
3. For sensitive matters, contact maintainers directly

Thank you for helping improve this project!
