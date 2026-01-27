# EC2 Cluster Module
# Creates bastion (public), admin/app/db (private) instances

data "aws_ami" "almalinux" {
  most_recent = true
  owners      = ["764336703387"] # AlmaLinux official

  filter {
    name   = "name"
    values = ["AlmaLinux OS 9*x86_64*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# SSH Key Pair
resource "aws_key_pair" "lab" {
  key_name   = "${var.environment}-lab-key"
  public_key = var.ssh_public_key

  tags = var.tags
}

# User data bootstrap script
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf -y update
    dnf -y install vim firewalld chrony policycoreutils-python-utils \
      setools-console bind-utils iproute procps-ng net-tools tcpdump \
      traceroute nmap-ncat lvm2
    systemctl enable --now firewalld chronyd
    setenforce 1 || true
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --reload
  EOF
}

# Bastion Host (public subnet)
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.almalinux.id
  instance_type               = var.bastion_instance_type
  key_name                    = aws_key_pair.lab.key_name
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [var.bastion_sg_id]
  associate_public_ip_address = true
  user_data                   = local.user_data

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-bastion"
    Role = "bastion"
  })
}

# Admin Server (private subnet)
resource "aws_instance" "admin" {
  ami                    = data.aws_ami.almalinux.id
  instance_type          = var.admin_instance_type
  key_name               = aws_key_pair.lab.key_name
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [var.admin_sg_id]
  user_data              = local.user_data

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-admin"
    Role = "admin"
  })
}

# Application Servers (private subnets, spread across AZs)
resource "aws_instance" "app" {
  count = var.app_count

  ami                    = data.aws_ami.almalinux.id
  instance_type          = var.app_instance_type
  key_name               = aws_key_pair.lab.key_name
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [var.app_sg_id]

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf -y update
    dnf -y install vim firewalld chrony httpd mod_ssl
    systemctl enable --now firewalld chronyd httpd
    setenforce 1 || true
    firewall-cmd --permanent --add-service=ssh --add-service=http --add-service=https
    firewall-cmd --reload
    echo "<h1>App Server $(hostname)</h1>" > /var/www/html/index.html
  EOF

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-app-${count.index + 1}"
    Role = "app"
  })
}
