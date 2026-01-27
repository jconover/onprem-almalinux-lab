.PHONY: help up-alma10 up-alma9 down-alma10 down-alma9 destroy-all \
       ansible-run ansible-check puppet-apply status

ALMA10_DIR := vagrant/alma10
ALMA9_DIR  := vagrant/alma9
ANSIBLE_DIR := ansible

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Vagrant lifecycle
# ---------------------------------------------------------------------------

up-alma10: ## Bring up AlmaLinux 10 cluster
	cd $(ALMA10_DIR) && vagrant up --provider=libvirt

up-alma9: ## Bring up AlmaLinux 9 cluster
	cd $(ALMA9_DIR) && vagrant up --provider=libvirt

down-alma10: ## Halt AlmaLinux 10 cluster
	cd $(ALMA10_DIR) && vagrant halt

down-alma9: ## Halt AlmaLinux 9 cluster
	cd $(ALMA9_DIR) && vagrant halt

destroy-all: ## Destroy ALL clusters (alma9 + alma10)
	cd $(ALMA10_DIR) && vagrant destroy -f || true
	cd $(ALMA9_DIR) && vagrant destroy -f || true

status: ## Show status of all VMs
	@echo "=== AlmaLinux 10 ==="
	@cd $(ALMA10_DIR) && vagrant status || true
	@echo ""
	@echo "=== AlmaLinux 9 ==="
	@cd $(ALMA9_DIR) && vagrant status || true

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
