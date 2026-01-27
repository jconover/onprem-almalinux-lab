# Profile: HAProxy load balancer
# Manages: haproxy package/service, config, SELinux boolean
class profile::haproxy (
  Integer $frontend_port = lookup('profile::haproxy::frontend_port', Integer, 'first', 80),
  Integer $stats_port    = lookup('profile::haproxy::stats_port', Integer, 'first', 8404),
  Integer $backend_port  = lookup('profile::haproxy::backend_port', Integer, 'first', 80),
  String  $balance       = lookup('profile::haproxy::balance', String, 'first', 'roundrobin'),
  Hash    $backends      = lookup('profile::haproxy::backends', Hash, 'hash', {}),
) {

  package { 'haproxy':
    ensure => installed,
  }

  file { '/etc/haproxy/haproxy.cfg':
    ensure  => file,
    content => epp('profile/haproxy.cfg.epp', {
      'frontend_port' => $frontend_port,
      'stats_port'    => $stats_port,
      'backend_port'  => $backend_port,
      'balance'       => $balance,
      'backends'      => $backends,
    }),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => Package['haproxy'],
    notify  => Service['haproxy'],
  }

  # SELinux boolean
  exec { 'setsebool-haproxy-connect-any':
    command => '/usr/sbin/setsebool -P haproxy_connect_any on',
    unless  => '/usr/sbin/getsebool haproxy_connect_any | /usr/bin/grep -q on$',
    path    => ['/usr/sbin', '/usr/bin'],
  }

  service { 'haproxy':
    ensure  => running,
    enable  => true,
    require => Package['haproxy'],
  }
}
