# Role: Database Server
# Includes: base config, MariaDB, firewall, NFS server, monitoring
class role::db_server {
  include profile::base
  include profile::db
  include profile::firewall
  include profile::nfs_server
  include profile::monitoring
}
