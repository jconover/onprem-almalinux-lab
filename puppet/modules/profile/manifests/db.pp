# Profile: MariaDB database server
# Manages: mariadb-server, config, secure install, app db/user
class profile::db (
  String $db_name                = lookup('profile::db::db_name', String, 'first', 'appdb'),
  String $db_user                = lookup('profile::db::db_user', String, 'first', 'appuser'),
  String $db_password            = lookup('profile::db::db_password', String, 'first', 'changeme'),
  String $root_password          = lookup('profile::db::root_password', String, 'first', 'changeme'),
  String $bind_address           = lookup('profile::db::bind_address', String, 'first', '0.0.0.0'),
  String $innodb_buffer_pool_size = lookup('profile::db::innodb_buffer_pool_size', String, 'first', '256M'),
) {

  package { ['mariadb-server', 'python3-PyMySQL']:
    ensure => installed,
  }

  file { '/etc/my.cnf.d/server.cnf':
    ensure  => file,
    content => epp('profile/server.cnf.epp', {
      'bind_address'           => $bind_address,
      'innodb_buffer_pool_size' => $innodb_buffer_pool_size,
    }),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => Package['mariadb-server'],
    notify  => Service['mariadb'],
  }

  service { 'mariadb':
    ensure  => running,
    enable  => true,
    require => Package['mariadb-server'],
  }

  # Secure installation: set root password
  exec { 'mariadb-root-password':
    command => "/usr/bin/mysqladmin -u root password '${root_password}'",
    unless  => "/usr/bin/mysqladmin -u root -p'${root_password}' status",
    path    => ['/usr/bin'],
    require => Service['mariadb'],
  }

  # Create application database
  exec { "create-db-${db_name}":
    command => "/usr/bin/mysql -u root -p'${root_password}' -e \"CREATE DATABASE IF NOT EXISTS ${db_name};\"",
    unless  => "/usr/bin/mysql -u root -p'${root_password}' -e \"SHOW DATABASES;\" | /usr/bin/grep -q '^${db_name}$'",
    path    => ['/usr/bin'],
    require => Exec['mariadb-root-password'],
  }

  # Create application user
  exec { "create-user-${db_user}":
    command => "/usr/bin/mysql -u root -p'${root_password}' -e \"GRANT ALL ON ${db_name}.* TO '${db_user}'@'%' IDENTIFIED BY '${db_password}'; FLUSH PRIVILEGES;\"",
    unless  => "/usr/bin/mysql -u root -p'${root_password}' -e \"SELECT User FROM mysql.user WHERE User='${db_user}';\" | /usr/bin/grep -q '${db_user}'",
    path    => ['/usr/bin'],
    require => Exec["create-db-${db_name}"],
  }
}
