#!/usr/bin/env bash
# Install Puppet agent from Puppetlabs repository
set -euxo pipefail

# Determine OS major version
OS_MAJOR=$(rpm -E %{rhel})

# Install Puppetlabs release repository
dnf -y install "https://yum.puppet.com/puppet8-release-el-${OS_MAJOR}.noarch.rpm"

# Install puppet-agent
dnf -y install puppet-agent

# Add puppet binaries to PATH for all users
cat > /etc/profile.d/puppet.sh <<'EOF'
export PATH="/opt/puppetlabs/bin:$PATH"
EOF

# Make puppet available in current session
export PATH="/opt/puppetlabs/bin:$PATH"

# Verify installation
puppet --version
