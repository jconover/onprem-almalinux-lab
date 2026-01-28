# Ansible Inventory Management

This directory contains inventory configurations for the onprem-almalinux-lab project, supporting both static and dynamic inventory sources.

## Table of Contents

- [Static vs Dynamic Inventory](#static-vs-dynamic-inventory)
- [Prerequisites](#prerequisites)
- [AWS EC2 Dynamic Inventory](#aws-ec2-dynamic-inventory)
- [Testing the Inventory](#testing-the-inventory)
- [Using with Playbooks](#using-with-playbooks)
- [Group Structure](#group-structure)
- [Troubleshooting](#troubleshooting)

---

## Static vs Dynamic Inventory

### Static Inventory

Static inventory files (like `inventory.ini`) are manually maintained lists of hosts:

```ini
[webservers]
web1.example.com
web2.example.com

[databases]
db1.example.com
```

**Pros:**
- Simple to understand and maintain for small environments
- No external dependencies
- Works offline

**Cons:**
- Must be manually updated when infrastructure changes
- Prone to drift from actual infrastructure
- Difficult to scale for large or dynamic environments

### Dynamic Inventory

Dynamic inventory scripts or plugins query external sources (AWS, Azure, etc.) in real-time:

**Pros:**
- Always reflects current infrastructure state
- Automatic group creation based on tags/attributes
- Scales effortlessly with infrastructure
- Single source of truth (your cloud provider)

**Cons:**
- Requires network connectivity and API access
- May have latency on large inventories (mitigated by caching)
- Requires proper IAM permissions

---

## Prerequisites

### 1. Install Required Python Packages

```bash
# Install boto3 and botocore (AWS SDK for Python)
pip install boto3 botocore

# Or with a specific version
pip install boto3>=1.26.0 botocore>=1.29.0
```

### 2. Install Ansible AWS Collection

```bash
# Install the amazon.aws collection
ansible-galaxy collection install amazon.aws

# Or specify version
ansible-galaxy collection install amazon.aws:>=6.0.0
```

### 3. Configure AWS Credentials

Choose one of the following methods:

#### Option A: Environment Variables

```bash
export AWS_ACCESS_KEY_ID='your-access-key'
export AWS_SECRET_ACCESS_KEY='your-secret-key'
export AWS_DEFAULT_REGION='us-east-1'
```

#### Option B: AWS Credentials File

Create or edit `~/.aws/credentials`:

```ini
[default]
aws_access_key_id = your-access-key
aws_secret_access_key = your-secret-key
```

And `~/.aws/config`:

```ini
[default]
region = us-east-1
output = json
```

#### Option C: IAM Instance Profile (Recommended for EC2)

When running Ansible from an EC2 instance, attach an IAM role with the required permissions. No credentials file needed.

### 4. Required IAM Permissions

The AWS user or role needs these minimum permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeRegions",
                "ec2:DescribeTags"
            ],
            "Resource": "*"
        }
    ]
}
```

---

## AWS EC2 Dynamic Inventory

The `aws_ec2.yml` file configures dynamic inventory for AWS EC2 instances.

### Key Configuration Options

| Option | Description |
|--------|-------------|
| `regions` | AWS regions to query |
| `filters` | EC2 filters to limit which instances are included |
| `keyed_groups` | Create Ansible groups based on instance attributes |
| `compose` | Set host variables from instance attributes |
| `hostnames` | How to name hosts in inventory |
| `cache` | Enable caching to reduce API calls |

### Instance Tagging Requirements

For optimal grouping, tag your EC2 instances with:

| Tag Key | Example Values | Purpose |
|---------|---------------|---------|
| `Name` | `web-prod-01` | Instance hostname in inventory |
| `Project` | `onprem-almalinux-lab` | Filter for this project only |
| `Role` | `webserver`, `database`, `loadbalancer` | Functional grouping |
| `Environment` | `production`, `staging`, `development` | Environment grouping |

---

## Testing the Inventory

### List All Hosts

```bash
# From the ansible directory
ansible-inventory -i inventories/aws_ec2.yml --list

# With pretty JSON output
ansible-inventory -i inventories/aws_ec2.yml --list | jq .
```

### List Groups Only

```bash
ansible-inventory -i inventories/aws_ec2.yml --graph
```

### Show Specific Host Details

```bash
ansible-inventory -i inventories/aws_ec2.yml --host <hostname>
```

### Verify Connectivity

```bash
# Ping all hosts
ansible -i inventories/aws_ec2.yml all -m ping

# Ping specific group
ansible -i inventories/aws_ec2.yml role_webserver -m ping
```

### Debug Mode

```bash
# Verbose output to troubleshoot issues
ansible-inventory -i inventories/aws_ec2.yml --list -vvv
```

---

## Using with Playbooks

### Specify Inventory on Command Line

```bash
# Use dynamic inventory only
ansible-playbook -i inventories/aws_ec2.yml playbooks/site.yml

# Use multiple inventory sources
ansible-playbook -i inventories/ playbooks/site.yml
```

### Target Specific Groups

```bash
# Target by role
ansible-playbook -i inventories/aws_ec2.yml playbooks/webserver.yml --limit role_webserver

# Target by environment
ansible-playbook -i inventories/aws_ec2.yml playbooks/site.yml --limit env_production

# Target by availability zone
ansible-playbook -i inventories/aws_ec2.yml playbooks/site.yml --limit az_us_east_1a

# Combine multiple groups
ansible-playbook -i inventories/aws_ec2.yml playbooks/site.yml --limit 'role_webserver:&env_production'
```

### Use in Playbook Headers

```yaml
---
- name: Configure web servers in production
  hosts: role_webserver:&env_production
  become: true
  roles:
    - nginx
    - app-deploy
```

### Access Host Variables in Playbooks

```yaml
---
- name: Show instance information
  hosts: all
  tasks:
    - name: Display instance details
      debug:
        msg: |
          Instance ID: {{ ec2_instance_id }}
          Region: {{ ec2_region }}
          AZ: {{ ec2_availability_zone }}
          Private IP: {{ ec2_private_ip }}
          Public IP: {{ ec2_public_ip }}
          Instance Type: {{ ec2_instance_type }}
          Tags: {{ ec2_tags }}
```

---

## Group Structure

The dynamic inventory creates the following group hierarchy:

```
@all:
  |--@ungrouped:
  |--@aws_ec2:
  |    |--web-prod-01
  |    |--web-prod-02
  |    |--db-prod-01
  |--@role_webserver:
  |    |--web-prod-01
  |    |--web-prod-02
  |--@role_database:
  |    |--db-prod-01
  |--@env_production:
  |    |--web-prod-01
  |    |--web-prod-02
  |    |--db-prod-01
  |--@env_staging:
  |    |--web-staging-01
  |--@instance_type_t3_micro:
  |    |--web-prod-01
  |    |--web-staging-01
  |--@instance_type_t3_small:
  |    |--db-prod-01
  |--@az_us_east_1a:
  |    |--web-prod-01
  |    |--db-prod-01
  |--@az_us_east_1b:
  |    |--web-prod-02
  |--@vpc_vpc_12345678:
  |    |--web-prod-01
  |    |--web-prod-02
  |    |--db-prod-01
  |--@running:
  |    |--web-prod-01
  |    |--web-prod-02
  |    |--db-prod-01
  |--@public:
  |    |--web-prod-01
  |    |--web-prod-02
```

### Group Naming Convention

| Prefix | Source | Example |
|--------|--------|---------|
| `role_` | `Role` tag | `role_webserver` |
| `env_` | `Environment` tag | `env_production` |
| `instance_type_` | Instance type | `instance_type_t3_micro` |
| `az_` | Availability zone | `az_us_east_1a` |
| `vpc_` | VPC ID | `vpc_vpc_12345678` |
| `running` | Instance state | All running instances |
| `public` | Has public IP | Instances with public IPs |

---

## Troubleshooting

### Common Issues

#### 1. "boto3 required for this module"

```bash
# Install boto3
pip install boto3

# Verify installation
python -c "import boto3; print(boto3.__version__)"
```

#### 2. "Unable to locate credentials"

```bash
# Check credentials are set
aws sts get-caller-identity

# If using profiles, specify the profile
export AWS_PROFILE=your-profile

# Or set credentials directly
export AWS_ACCESS_KEY_ID='your-key'
export AWS_SECRET_ACCESS_KEY='your-secret'
```

#### 3. "Access Denied" Errors

Verify IAM permissions include:
- `ec2:DescribeInstances`
- `ec2:DescribeRegions`
- `ec2:DescribeTags`

#### 4. Empty Inventory

Check your filters:

```bash
# List all instances without filters
aws ec2 describe-instances --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,Tags:Tags}'

# Verify tag values match exactly
aws ec2 describe-instances --filters "Name=tag:Project,Values=onprem-almalinux-lab"
```

#### 5. Wrong Region

Ensure the regions in `aws_ec2.yml` match where your instances are deployed:

```yaml
regions:
  - us-east-1  # Verify this matches your instances
```

#### 6. Cache Issues

Clear the cache if inventory seems stale:

```bash
# Remove cache files
rm -rf /tmp/aws_ec2_inventory_cache*

# Or disable caching temporarily
ansible-inventory -i inventories/aws_ec2.yml --list --flush-cache
```

#### 7. SSH Connection Failures

Verify the compose settings:

```yaml
compose:
  ansible_host: public_ip_address | default(private_ip_address, true)
  ansible_user: "'ec2-user'"  # Adjust for your AMI
```

Common SSH users by AMI:
- Amazon Linux: `ec2-user`
- Ubuntu: `ubuntu`
- CentOS/RHEL: `centos` or `ec2-user`
- Debian: `admin`

### Debug Commands

```bash
# Maximum verbosity
ansible-inventory -i inventories/aws_ec2.yml --list -vvvv

# Test specific host
ansible -i inventories/aws_ec2.yml <hostname> -m ping -vvv

# Check what Python Ansible is using
ansible --version

# Verify boto3 is accessible
ansible -m debug -a "var=ansible_python_interpreter" localhost
python -c "import boto3; print(boto3.__version__)"
```

### Performance Optimization

For large inventories:

1. **Enable caching** (already configured in `aws_ec2.yml`)
2. **Limit regions** to only those you use
3. **Use specific filters** to reduce API response size
4. **Increase cache timeout** for stable environments

---

## Additional Resources

- [Ansible AWS EC2 Inventory Plugin Documentation](https://docs.ansible.com/ansible/latest/collections/amazon/aws/aws_ec2_inventory.html)
- [Amazon.aws Collection](https://galaxy.ansible.com/amazon/aws)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Ansible Inventory Documentation](https://docs.ansible.com/ansible/latest/inventory_guide/index.html)
