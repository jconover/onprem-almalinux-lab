# Profile: BIND DNS server
# Manages: bind package/service, named.conf, zone files
class profile::dns (
  String      $domain       = lookup('profile::dns::domain', String, 'first', 'lab.local'),
  String      $reverse_zone = lookup('profile::dns::reverse_zone', String, 'first', '60.168.192'),
  Array       $forwarders   = lookup('profile::dns::forwarders', Array, 'unique', ['8.8.8.8']),
  Hash        $records      = lookup('profile::dns::records', Hash, 'hash', {}),
) {

  package { ['bind', 'bind-utils']:
    ensure => installed,
  }

  file { '/etc/named.conf':
    ensure  => file,
    content => epp('profile/named.conf.epp', {
      'domain'       => $domain,
      'reverse_zone' => $reverse_zone,
      'forwarders'   => $forwarders,
      'listen_addr'  => $facts['networking']['ip'],
    }),
    owner   => 'root',
    group   => 'named',
    mode    => '0640',
    require => Package['bind'],
    notify  => Service['named'],
  }

  file { "/var/named/forward.${domain}":
    ensure  => file,
    content => epp('profile/zone.db.epp', {
      'domain'       => $domain,
      'records'      => $records,
      'ns_ip'        => $facts['networking']['ip'],
      'zone_type'    => 'forward',
      'reverse_zone' => $reverse_zone,
    }),
    owner   => 'root',
    group   => 'named',
    mode    => '0640',
    require => Package['bind'],
    notify  => Service['named'],
  }

  file { "/var/named/reverse.${domain}":
    ensure  => file,
    content => epp('profile/zone.db.epp', {
      'domain'       => $domain,
      'records'      => $records,
      'ns_ip'        => $facts['networking']['ip'],
      'zone_type'    => 'reverse',
      'reverse_zone' => $reverse_zone,
    }),
    owner   => 'root',
    group   => 'named',
    mode    => '0640',
    require => Package['bind'],
    notify  => Service['named'],
  }

  # SELinux boolean
  exec { 'setsebool-named-write-master-zones':
    command => '/usr/sbin/setsebool -P named_write_master_zones on',
    unless  => '/usr/sbin/getsebool named_write_master_zones | /usr/bin/grep -q on$',
    path    => ['/usr/sbin', '/usr/bin'],
  }

  service { 'named':
    ensure  => running,
    enable  => true,
    require => Package['bind'],
  }
}
