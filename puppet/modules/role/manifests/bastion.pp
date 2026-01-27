# Role: Bastion / Jump Host with HAProxy
# Includes: base config, HAProxy load balancer, firewall, monitoring
class role::bastion {
  include profile::base
  include profile::haproxy
  include profile::firewall
  include profile::monitoring
}
