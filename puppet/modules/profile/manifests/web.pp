# Profile: Apache web server
# Manages: httpd package/service, vhost config, index page
class profile::web (
  String  $server_name = lookup('profile::web::server_name', String, 'first', $facts['networking']['fqdn']),
  String  $doc_root    = lookup('profile::web::doc_root', String, 'first', '/var/www/html'),
  Integer $listen_port = lookup('profile::web::listen_port', Integer, 'first', 80),
) {

  package { ['httpd', 'mod_ssl']:
    ensure => installed,
  }

  file { '/etc/httpd/conf.d/vhost.conf':
    ensure  => file,
    content => epp('profile/vhost.conf.epp', {
      'server_name' => $server_name,
      'doc_root'    => $doc_root,
      'listen_port' => $listen_port,
    }),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => Package['httpd'],
    notify  => Service['httpd'],
  }

  file { "${doc_root}/index.html":
    ensure  => file,
    content => "<html><body><h1>${facts['networking']['hostname']}</h1><p>Managed by Puppet | ${server_name}</p></body></html>\n",
    owner   => 'apache',
    group   => 'apache',
    mode    => '0644',
    require => Package['httpd'],
  }

  service { 'httpd':
    ensure  => running,
    enable  => true,
    require => Package['httpd'],
  }
}
