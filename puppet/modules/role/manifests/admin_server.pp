# Role: Admin Server
# Includes: base config, DNS, firewall, monitoring
class role::admin_server {
  include profile::base
  include profile::dns
  include profile::firewall
  include profile::monitoring
}
