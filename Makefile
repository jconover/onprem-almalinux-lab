.PHONY: help up-alma10 up-alma9 down-alma10 down-alma9 destroy-alma10 destroy-alma9 destroy-all \
       ansible-run ansible-check ansible-run-alma9 ansible-check-alma9 \
       puppet-apply puppet-validate tf-init-dev tf-plan-dev tf-validate status \
       lint lint-ansible lint-terraform lint-puppet lint-shell \
       ci ci-setup \
       pre-commit-install pre-commit-run

ALMA10_DIR := vagrant/alma10
ALMA9_DIR  := vagrant/alma9
ANSIBLE_DIR := ansible

# Filter fog warnings from vagrant-libvirt (upstream bug)
VAGRANT_FILTER := 2>&1 | grep -v '\[fog\]\[WARNING\]'

help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+: ## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ": ## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Vagrant lifecycle
# ---------------------------------------------------------------------------

up-alma10: ## Bring up AlmaLinux 10 cluster
	cd $(ALMA10_DIR) && vagrant up --provider=libvirt $(VAGRANT_FILTER)

up-alma9: ## Bring up AlmaLinux 9 cluster
	cd $(ALMA9_DIR) && vagrant up --provider=libvirt $(VAGRANT_FILTER)

down-alma10: ## Halt AlmaLinux 10 cluster
	cd $(ALMA10_DIR) && vagrant halt $(VAGRANT_FILTER)

down-alma9: ## Halt AlmaLinux 9 cluster
	cd $(ALMA9_DIR) && vagrant halt $(VAGRANT_FILTER)

destroy-alma10: ## Destroy AlmaLinux 10 cluster
	cd $(ALMA10_DIR) && vagrant destroy -f $(VAGRANT_FILTER)

destroy-alma9: ## Destroy AlmaLinux 9 cluster
	cd $(ALMA9_DIR) && vagrant destroy -f $(VAGRANT_FILTER)

destroy-all: ## Destroy ALL clusters (alma9 + alma10)
	cd $(ALMA10_DIR) && vagrant destroy -f $(VAGRANT_FILTER) || true
	cd $(ALMA9_DIR) && vagrant destroy -f $(VAGRANT_FILTER) || true

status: ## Show status of all VMs
	@echo "=== AlmaLinux 10 ==="
	@cd $(ALMA10_DIR) && vagrant status $(VAGRANT_FILTER) || true
	@echo ""
	@echo "=== AlmaLinux 9 ==="
	@cd $(ALMA9_DIR) && vagrant status $(VAGRANT_FILTER) || true

# ---------------------------------------------------------------------------
# Ansible
# ---------------------------------------------------------------------------

ansible-run: ## Run Ansible site.yml against alma10 cluster
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory.ini site.yml

ansible-check: ## Dry-run Ansible site.yml (check mode)
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory.ini site.yml --check --diff

ansible-run-alma9: ## Run Ansible site.yml against alma9 cluster
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory-alma9.ini site.yml

ansible-check-alma9: ## Dry-run Ansible site.yml against alma9 cluster
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventory-alma9.ini site.yml --check --diff

# ---------------------------------------------------------------------------
# Puppet
# ---------------------------------------------------------------------------

puppet-apply: ## Apply Puppet manifests via puppet apply (run from admin node)
	@echo "SSH into the admin node and run:"
	@echo "  sudo /opt/puppetlabs/bin/puppet apply --modulepath=/vagrant/puppet/modules /vagrant/puppet/manifests/site.pp --hiera_config=/vagrant/puppet/hiera.yaml"

puppet-validate: ## Validate Puppet manifests syntax
	cd puppet && find manifests modules -name '*.pp' -exec puppet parser validate {} +

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------

tf-init-dev: ## Initialize Terraform dev environment
	cd terraform/environments/dev && terraform init

tf-plan-dev: ## Plan Terraform dev environment
	cd terraform/environments/dev && terraform plan

tf-validate: ## Validate all Terraform configurations
	cd terraform/environments/dev && terraform validate

# ---------------------------------------------------------------------------
# Quality & Testing
# ---------------------------------------------------------------------------

lint: lint-ansible lint-terraform lint-puppet lint-shell ## Run all linters

lint-ansible: ## Run yamllint and ansible-lint on ansible/
	yamllint $(ANSIBLE_DIR)/
	ansible-lint $(ANSIBLE_DIR)/

lint-terraform: ## Run terraform fmt -check and terraform validate
	terraform fmt -check -recursive terraform/
	cd terraform/environments/dev && terraform validate

lint-puppet: ## Run puppet parser validate and puppet-lint
	cd puppet && find manifests modules -name '*.pp' -exec puppet parser validate {} +
	puppet-lint puppet/

lint-shell: ## Run shellcheck on provision/*.sh
	shellcheck provision/*.sh

# ---------------------------------------------------------------------------
# CI/CD Helpers
# ---------------------------------------------------------------------------

ci: lint tf-validate ## Run full CI validation (lint + validate)

ci-setup: ## Install CI dependencies
	pip install ansible ansible-lint yamllint
	gem install puppet-lint

# ---------------------------------------------------------------------------
# Pre-commit
# ---------------------------------------------------------------------------

pre-commit-install: ## Install pre-commit hooks
	pip install pre-commit && pre-commit install

pre-commit-run: ## Run pre-commit on all files
	pre-commit run --all-files
