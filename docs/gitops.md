# GitOps for Infrastructure

## 1. Overview

GitOps is the practice of using Git as the single source of truth for
infrastructure and configuration. Every change goes through a pull request,
is reviewed, tested in CI, and applied automatically or via a controlled
process. For Senior Linux Admin roles, this means managing Puppet code,
Ansible playbooks, and Terraform configurations through Git workflows
with CI/CD pipelines.

This document covers:
- Git branching strategies for infrastructure teams
- GitOps workflows for each tool in the lab (Puppet, Ansible, Terraform)
- CI/CD pipeline examples using GitHub Actions
- Drift detection strategies
- Secret management in Git-based workflows

---

## 2. Architecture

### Lab GitOps Flow

```
Developer Workstation
        |
  git push (feature branch)
        |
  +-----v------+
  | GitHub Repo |
  |             |
  | PR Created  +---> CI Pipeline Triggers
  |             |     +-- puppet-lint + parser validate
  +-----+------+     +-- ansible-lint + molecule
        |             +-- terraform fmt + validate + plan
        |             +-- commit status checks
  Code Review         |
  (Approve + Merge)   |
        |             |
  +-----v------+      |
  | main branch|------+
  +-----+------+
        |
  CD Pipeline Triggers
  +-- r10k deploy (Puppet environments)
  +-- ansible-playbook site.yml
  +-- terraform apply (saved plan)
```

### Tool-Specific Git Structures

```
onprem-almalinux-lab/           # Monorepo approach
  puppet/                       # Puppet control repo
    Puppetfile                  # Module versions (r10k)
    manifests/site.pp
    modules/role/
    modules/profile/
    data/                       # Hiera data
  ansible/                      # Ansible playbook repo
    site.yml
    inventory.ini
    roles/
    group_vars/
    vault.yml                   # Encrypted secrets
  terraform/                    # Terraform IaC
    modules/
    environments/dev/
    environments/prod/          # (future)
```

---

## 3. Prerequisites

- Git installed and configured
- GitHub repository with branch protection rules
- CI/CD platform (GitHub Actions, GitLab CI, or Jenkins)
- Tool-specific linters and testing frameworks:
  - Puppet: `puppet-lint`, `puppet parser validate`, `rspec-puppet`, `PDK`
  - Ansible: `ansible-lint`, `molecule`, `yamllint`
  - Terraform: `terraform fmt`, `terraform validate`, `tflint`

---

## 4. Step-by-Step Setup / Deep Dive

### 4.1 Git Workflow for Infrastructure Teams

#### Branching Strategy: Trunk-Based Development

For infrastructure code, **trunk-based development** is recommended over GitFlow.

| Strategy       | GitFlow                          | Trunk-Based                      |
|---------------|----------------------------------|----------------------------------|
| Main branch   | `main` + `develop`               | `main` only                      |
| Feature work  | Long-lived feature branches      | Short-lived branches (< 2 days)  |
| Releases      | Release branches                 | Tags on main                     |
| Merge method  | Merge commits                    | Squash merge preferred           |
| Complexity    | High (multiple long-lived branches) | Low (one main branch)         |
| Best for      | Application releases             | Infrastructure (continuous)      |

**Why trunk-based for infra**: Infrastructure changes should be small, incremental,
and applied frequently. Long-lived branches lead to merge conflicts in Hiera data
and Terraform state. Short-lived branches with fast CI keep the feedback loop tight.

#### Branch Protection Rules

```
main branch:
  - Require pull request reviews (1+ approval)
  - Require status checks to pass (lint, validate, plan)
  - Require branches to be up to date before merging
  - Do not allow force push
  - Do not allow deletion
```

#### Commit Conventions

Use conventional commits for infrastructure changes:

```
feat(puppet): add profile::monitoring for node_exporter
fix(ansible): correct firewall handler notification
refactor(terraform): extract security groups into module
docs(monitoring): add PromQL examples
chore(ci): add terraform plan to PR workflow
```

### 4.2 GitOps for Puppet

#### Control Repo + r10k

The Puppet directory in this lab IS the control repo. In a production setup,
it would be its own repository.

**How r10k branches map to Puppet environments**:

```
Git branch            Puppet environment    Usage
==========            ==================    =====
main                  production            Active nodes
staging               staging               Pre-production testing
feature/add-nginx     feature_add_nginx     Developer testing
```

When a developer pushes a new branch, r10k creates a corresponding Puppet
environment directory on the Puppet Server. Nodes can be pointed to that
environment for testing:

```bash
# On a test node, apply the feature environment
sudo puppet agent -t --environment=feature_add_nginx

# Or with puppet apply:
sudo puppet apply \
  --modulepath=/etc/puppetlabs/code/environments/feature_add_nginx/modules \
  --hiera_config=/etc/puppetlabs/code/environments/feature_add_nginx/hiera.yaml \
  /etc/puppetlabs/code/environments/feature_add_nginx/manifests/site.pp
```

**Workflow**:

```
1. git checkout -b feature/add-monitoring
2. Edit profile::monitoring, update Hiera data
3. git commit + git push
4. CI runs: puppet parser validate, puppet-lint, rspec-puppet
5. PR created -> reviewer approves
6. Merge to main
7. Webhook triggers: r10k deploy environment production --puppetfile
8. Puppet agents pick up changes on next run (30 min) or manual trigger
```

#### Puppetfile Versioning

Pin module versions in the Puppetfile for reproducibility:

```ruby
# Puppet Forge modules (pinned versions)
mod 'puppetlabs-stdlib',    '9.0.0'
mod 'puppetlabs-firewall',  '7.0.0'

# Git modules (pinned to tag or commit)
mod 'custom_module',
  :git => 'https://github.com/myorg/custom_module.git',
  :tag => 'v1.2.0'
```

**Never use `:latest` or unpinned versions** -- this makes environments
non-reproducible and can break production when upstream changes.

### 4.3 GitOps for Ansible

#### Playbook Repository Structure

```
ansible/
  site.yml              # Master playbook
  inventory.ini         # Static inventory
  inventory-alma9.ini   # Second cluster inventory
  ansible.cfg           # Configuration
  vault.yml             # Encrypted secrets (ansible-vault)
  group_vars/
    all.yml             # Variables for all hosts
    apps.yml            # Variables for app group
    dbs.yml             # Variables for db group
  host_vars/
    alma10-admin.yml    # Per-host variables
  roles/
    common/             # Base OS configuration
    firewall/           # firewalld management
    web/                # Apache httpd
    db/                 # MariaDB
    dns/                # BIND
    nfs/                # NFS server
    haproxy/            # HAProxy LB
    ldap/               # OpenLDAP
    sssd/               # SSSD client
    monitoring/         # node_exporter
```

#### ansible-lint in CI

```yaml
# .github/workflows/ansible-lint.yml
name: Ansible Lint
on:
  pull_request:
    paths: ['ansible/**']

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install ansible-lint
        run: pip install ansible-lint yamllint

      - name: Run yamllint
        run: yamllint ansible/

      - name: Run ansible-lint
        run: ansible-lint ansible/site.yml
```

#### Molecule for Role Testing

Molecule creates temporary environments to test Ansible roles in isolation.

```yaml
# ansible/roles/web/molecule/default/molecule.yml
---
dependency:
  name: galaxy
driver:
  name: podman      # Use Podman as test driver (container-based)
platforms:
  - name: alma10-test
    image: quay.io/almalinuxorg/almalinux:10
    pre_build_image: true
    privileged: true
    command: /sbin/init
provisioner:
  name: ansible
verifier:
  name: ansible
```

```yaml
# ansible/roles/web/molecule/default/converge.yml
---
- name: Converge
  hosts: all
  become: true
  roles:
    - web
```

```yaml
# ansible/roles/web/molecule/default/verify.yml
---
- name: Verify
  hosts: all
  tasks:
    - name: Check httpd is running
      ansible.builtin.service:
        name: httpd
        state: started
      check_mode: true
      register: httpd_status
      failed_when: httpd_status.changed
```

```bash
# Run molecule test (full lifecycle)
cd ansible/roles/web
molecule test       # create -> converge -> verify -> destroy

# Run just converge (for development)
molecule converge

# Run just verify
molecule verify
```

#### Vault Secrets in Git

Ansible Vault encrypts sensitive variables so they can be committed safely:

```bash
# Create encrypted vault file
ansible-vault create ansible/vault.yml

# Edit encrypted file
ansible-vault edit ansible/vault.yml

# Encrypt existing file
ansible-vault encrypt ansible/group_vars/dbs.yml

# Use in playbook
ansible-playbook -i inventory.ini site.yml --ask-vault-pass

# Or with password file (for CI)
ansible-playbook -i inventory.ini site.yml --vault-password-file=.vault_pass
```

In CI, the vault password is stored as a GitHub secret and injected:

```yaml
- name: Run Ansible
  env:
    ANSIBLE_VAULT_PASSWORD: ${{ secrets.ANSIBLE_VAULT_PASSWORD }}
  run: |
    echo "$ANSIBLE_VAULT_PASSWORD" > .vault_pass
    ansible-playbook -i inventory.ini site.yml --vault-password-file=.vault_pass
    rm -f .vault_pass
```

### 4.4 GitOps for Terraform

#### PR-Based Plan/Apply Workflow

This is the most mature GitOps workflow for Terraform.

```
Feature branch -> PR -> terraform plan (CI) -> Review plan output -> Merge -> terraform apply (CD)
```

**Atlantis** or **Terraform Cloud** can automate this. With GitHub Actions:

```yaml
# .github/workflows/terraform.yml
name: Terraform
on:
  pull_request:
    paths: ['terraform/**']
  push:
    branches: [main]
    paths: ['terraform/**']

jobs:
  plan:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: terraform/environments/dev
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3

      - name: Terraform Format Check
        run: terraform fmt -check -recursive

      - name: Terraform Init
        run: terraform init

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan
        id: plan
        run: terraform plan -no-color -out=tfplan
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

      - name: Post Plan to PR
        uses: actions/github-script@v7
        with:
          script: |
            const plan = `${{ steps.plan.outputs.stdout }}`;
            github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `### Terraform Plan\n\`\`\`\n${plan}\n\`\`\``
            });

  apply:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: terraform/environments/dev
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: terraform init

      - name: Terraform Apply
        run: terraform apply -auto-approve
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

#### Puppet CI Pipeline

```yaml
# .github/workflows/puppet.yml
name: Puppet Validation
on:
  pull_request:
    paths: ['puppet/**']

jobs:
  validate:
    runs-on: ubuntu-latest
    container: puppet/puppet-agent:latest
    steps:
      - uses: actions/checkout@v4

      - name: Puppet Parser Validate
        run: |
          find puppet/manifests puppet/modules -name '*.pp' \
            -exec puppet parser validate {} +

      - name: Puppet Lint
        run: |
          gem install puppet-lint
          puppet-lint --no-140chars-check puppet/modules/

      - name: Validate Hiera YAML
        run: |
          find puppet/data -name '*.yaml' -exec ruby -ryaml -e \
            "YAML.load_file('{}'); puts 'OK: {}'" \;

      - name: EPP Syntax Check
        run: |
          find puppet/modules -name '*.epp' -exec puppet epp validate {} +
```

#### Ansible CI Pipeline

```yaml
# .github/workflows/ansible.yml
name: Ansible CI
on:
  pull_request:
    paths: ['ansible/**']

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install Dependencies
        run: pip install ansible ansible-lint yamllint molecule podman

      - name: YAML Lint
        run: yamllint ansible/

      - name: Ansible Lint
        run: ansible-lint ansible/site.yml

      - name: Ansible Syntax Check
        run: |
          cd ansible
          ansible-playbook --syntax-check -i inventory.ini site.yml

  molecule:
    runs-on: ubuntu-latest
    needs: lint
    strategy:
      matrix:
        role: [common, firewall, web, db]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install Dependencies
        run: pip install ansible molecule podman

      - name: Run Molecule
        run: |
          cd ansible/roles/${{ matrix.role }}
          molecule test
```

### 4.5 Drift Detection

#### Puppet Drift Detection

Puppet agents run every 30 minutes and automatically detect and correct drift:

```bash
# Check for drift without correcting (noop mode)
sudo puppet agent -t --noop

# View recent corrective changes in PuppetDB
# (query via PuppetDB API or PE console)
```

For this lab (masterless), schedule noop checks via cron:

```bash
# /etc/cron.d/puppet-drift-check
0 */2 * * * root /opt/puppetlabs/bin/puppet apply --noop \
  --modulepath=/vagrant/puppet/modules \
  /vagrant/puppet/manifests/site.pp \
  --hiera_config=/vagrant/puppet/hiera.yaml 2>&1 | \
  grep -E 'Would have|current_value' > /var/log/puppet-drift.log
```

#### Terraform Drift Detection

Schedule `terraform plan` in CI to detect drift from manual changes:

```yaml
# .github/workflows/drift-check.yml
name: Terraform Drift Detection
on:
  schedule:
    - cron: '0 6 * * *'   # Daily at 6 AM UTC

jobs:
  drift-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        working-directory: terraform/environments/dev
        run: terraform init

      - name: Terraform Plan (Drift Check)
        working-directory: terraform/environments/dev
        id: plan
        run: terraform plan -detailed-exitcode -no-color
        continue-on-error: true
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

      # Exit code 2 = drift detected
      - name: Alert on Drift
        if: steps.plan.outcome == 'failure'
        run: |
          echo "::warning::Terraform drift detected! Review plan output."
          # Could also post to Slack or create an issue
```

#### Ansible Drift Detection

```bash
# Check mode shows what WOULD change (i.e., current drift)
ansible-playbook -i inventory.ini site.yml --check --diff

# In CI as a scheduled job
# Same playbook, but --check --diff mode
# Non-zero exit code = drift detected
```

---

## 5. Verification / Testing

### Pre-Merge Verification Checklist

| Tool       | Check                          | Command |
|------------|--------------------------------|---------|
| Puppet     | Syntax validation              | `puppet parser validate *.pp` |
| Puppet     | Style linting                  | `puppet-lint modules/` |
| Puppet     | EPP template validation        | `puppet epp validate templates/*.epp` |
| Puppet     | Unit tests                     | `pdk test unit` |
| Ansible    | YAML lint                      | `yamllint ansible/` |
| Ansible    | Ansible lint                   | `ansible-lint site.yml` |
| Ansible    | Syntax check                   | `ansible-playbook --syntax-check site.yml` |
| Ansible    | Role tests                     | `molecule test` |
| Terraform  | Format check                   | `terraform fmt -check` |
| Terraform  | Validation                     | `terraform validate` |
| Terraform  | Plan                           | `terraform plan` |
| All        | Commit message format          | `commitlint` or custom check |

---

## 6. Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| CI fails on `puppet-lint` | Style violations | Run `puppet-lint --fix` locally |
| `ansible-lint` fails on `command` module | Using shell/command instead of module | Use appropriate Ansible module (e.g., `dnf` instead of `command: dnf install`) |
| Terraform plan shows unexpected changes | State drift from manual change | Either apply to reconcile or import the manual change |
| r10k deploy fails | Puppetfile has invalid module reference | Verify forge module name and version exist |
| Molecule fails with Podman | Missing Podman or permissions | Install Podman, verify user can run rootless containers |
| Vault-encrypted file breaks in CI | Vault password not available | Add vault password as CI secret |
| Merge conflicts in Hiera YAML | Two PRs modify same data file | Keep PRs small, rebase frequently |
| CI passes but apply fails | CI env differs from apply env | Ensure same Terraform/Puppet/Ansible version in CI and target |

---

## 7. Architecture Decision Rationale

### Why Monorepo over Separate Repos

**Decision**: Keep Puppet, Ansible, and Terraform in one repository.

**Rationale**:
- Lab context: all tools manage the same infrastructure
- Easier to see the full picture in one place
- Cross-tool changes (e.g., add monitoring to Puppet AND Ansible) go in one PR
- Simpler CI configuration
- Production alternative: separate repos per tool with cross-repo references

### Why Trunk-Based over GitFlow

**Decision**: Use trunk-based development with short-lived branches.

**Rationale**:
- Infrastructure changes should be small and continuous
- Long-lived branches lead to Hiera/state merge conflicts
- Fast feedback loop: push, CI validates, merge same day
- GitFlow's release branches add complexity without benefit for infra code
- Feature flags are not needed for infrastructure

### Why GitHub Actions over Jenkins

**Decision**: Use GitHub Actions for CI/CD examples.

**Rationale**:
- Native integration with GitHub PRs (status checks, PR comments)
- YAML-based pipeline definitions committed alongside code
- Free tier is sufficient for a lab
- Production: could use Jenkins, GitLab CI, or CircleCI -- principles are the same
- The patterns (lint -> validate -> plan -> apply) transfer to any CI platform

### Why Scheduled Drift Detection

**Decision**: Run automated drift checks on a schedule.

**Rationale**:
- Manual checks are forgotten; automation catches drift early
- Non-blocking: alerts on drift without auto-remediation
- Allows human review before corrective action
- Combined with Puppet agent runs (auto-correction) provides defense in depth
- Cost: minimal (one CI job per day per environment)

---

## 8. Interview Talking Points

### "Describe your GitOps workflow for infrastructure."

> "All infrastructure code lives in Git with protected main branch. Every change
> starts as a PR from a short-lived feature branch. CI runs automatically:
> puppet-lint, ansible-lint, terraform plan. The plan output is posted as a PR
> comment so reviewers can see exactly what will change in production. After
> review and approval, merge to main triggers deployment: r10k deploys Puppet
> environments, Ansible runs against the target inventory, and Terraform applies
> the plan. No one runs `terraform apply` from their laptop. This gives us
> an audit trail, peer review, and rollback via `git revert`."

### "How do you handle config drift?"

> "Three layers. First, Puppet agents run every 30 minutes and automatically
> correct drift to the declared state. Second, Terraform drift detection runs
> as a scheduled CI job -- `terraform plan` at 6 AM daily. If drift is
> detected, it creates an alert. Third, Ansible `--check --diff` runs weekly
> to verify idempotent convergence. For emergency manual changes, we have a
> policy: fix it now, then codify it in a PR within 24 hours. The PR adds the
> change to automation so it persists and is version-controlled."

### "How do you manage secrets in Git?"

> "We never store plaintext secrets in Git. For Ansible, we use ansible-vault
> to encrypt sensitive variables in `vault.yml`. The vault password is stored
> in the CI platform's secret manager. For Terraform, sensitive variables are
> marked with `sensitive = true` and injected via CI environment variables
> from the secret store. For Puppet, hiera-eyaml encrypts values inline in
> YAML files using asymmetric encryption. All three approaches let us commit
> the encrypted files to Git while keeping plaintext secrets out of version
> control. For rotation, we re-encrypt and commit a new PR."

### "What is your code review process for infrastructure changes?"

> "Every infrastructure PR requires at least one approval from a team member.
> Reviewers check: Does the change match the stated intent? Does the Terraform
> plan look correct? Are there any security implications (open ports, public
> access)? Is the change reversible? Are there test results (Molecule, rspec)?
> We use PR templates with checklists for common concerns. For high-risk
> changes (anything touching production networking or databases), we require
> two approvals and a deployment window."

### "How do you handle rollbacks for infrastructure changes?"

> "For Puppet and Ansible, `git revert` the PR and deploy. The next Puppet
> agent run or Ansible playbook execution reverts the configuration. For
> Terraform, it depends on the change. Reverting the code and running
> `terraform apply` works for most cases. For destructive changes (deleted
> resources), you may need to recreate from scratch or restore from backup.
> This is why we review Terraform plans carefully before merge. We also tag
> known-good states so we can check out a specific version if needed."
