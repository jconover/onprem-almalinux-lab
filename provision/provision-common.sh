
#!/usr/bin/env bash
set -euxo pipefail
dnf -y update
dnf -y install vim firewalld chrony policycoreutils-python-utils setools-console   bind-utils iproute procps-ng net-tools tcpdump traceroute nmap-ncat lvm2
systemctl enable --now firewalld chronyd
setenforce 1 || true
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload
