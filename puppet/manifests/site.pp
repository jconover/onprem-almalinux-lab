# Site manifest -- node classification
# Maps hostnames to roles using the role/profile pattern

node 'alma10-app', 'alma10-app2' {
  include role::app_server
}

node 'alma10-db' {
  include role::db_server
}

node 'alma10-admin' {
  include role::admin_server
}

node 'alma10-bastion' {
  include role::bastion
}

# Default node (catch-all)
node default {
  include profile::base
  include profile::firewall
  include profile::monitoring
}
