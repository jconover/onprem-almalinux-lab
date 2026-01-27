# Role: Application Server
# Includes: base config, web server, firewall, monitoring
class role::app_server {
  include profile::base
  include profile::web
  include profile::firewall
  include profile::monitoring
}
