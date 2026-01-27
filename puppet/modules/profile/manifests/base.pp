# Profile: Base system configuration
# Manages: packages, SELinux, chrony, sysctl, MOTD, timezone
class profile::base (
  Array[String] $packages        = lookup('profile::base::packages', Array, 'unique', []),
  String        $timezone        = lookup('profile::base::timezone', String, 'first', 'America/New_York'),
  String        $domain          = lookup('profile::base::domain', String, 'first', 'lab.local'),
  String        $selinux_mode    = lookup('profile::base::selinux_mode', String, 'first', 'enforcing'),
  Array[String] $ntp_servers     = lookup('profile::base::ntp_servers', Array, 'unique', []),
  Hash          $sysctl_settings = lookup('profile::base::sysctl_settings', Hash, 'hash', {}),
) {

  # Install baseline packages
  package { $packages:
    ensure => installed,
  }

  # SELinux enforcing
  exec { 'selinux-enforcing':
    command => '/usr/sbin/setenforce 1',
    unless  => '/usr/sbin/getenforce | /usr/bin/grep -qi enforcing',
    path    => ['/usr/sbin', '/usr/bin'],
  }

  file { '/etc/selinux/config':
    ensure  => file,
    content => "SELINUX=${selinux_mode}\nSELINUXTYPE=targeted\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
  }

  # Timezone
  exec { 'set-timezone':
    command => "/usr/bin/timedatectl set-timezone ${timezone}",
    unless  => "/usr/bin/timedatectl show -p Timezone --value | /usr/bin/grep -q '^${timezone}$'",
    path    => ['/usr/bin'],
  }

  # Chrony / NTP
  service { 'chronyd':
    ensure  => running,
    enable  => true,
    require => Package['chrony'],
  }

  # Firewalld
  service { 'firewalld':
    ensure => running,
    enable => true,
  }

  # Sysctl hardening
  file { '/etc/sysctl.d/99-puppet-hardening.conf':
    ensure  => file,
    content => epp('profile/sysctl.conf.epp', { 'settings' => $sysctl_settings }),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    notify  => Exec['reload-sysctl'],
  }

  exec { 'reload-sysctl':
    command     => '/usr/sbin/sysctl --system',
    refreshonly => true,
    path        => ['/usr/sbin'],
  }

  # MOTD
  file { '/etc/motd':
    ensure  => file,
    content => epp('profile/motd.epp', {
      'hostname' => $facts['networking']['hostname'],
      'domain'   => $domain,
    }),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
  }
}
