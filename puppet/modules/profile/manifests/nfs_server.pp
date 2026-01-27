# Profile: NFS server
# Manages: nfs-utils, export directories, /etc/exports, SELinux booleans
class profile::nfs_server (
  Hash $exports = lookup('profile::nfs_server::exports', Hash, 'hash', {}),
) {

  package { 'nfs-utils':
    ensure => installed,
  }

  # Create export directories
  $exports.each |String $path, Hash $opts| {
    file { $path:
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }
  }

  file { '/etc/exports':
    ensure  => file,
    content => epp('profile/exports.epp', { 'exports' => $exports }),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => Package['nfs-utils'],
    notify  => Exec['exportfs-reload'],
  }

  exec { 'exportfs-reload':
    command     => '/usr/sbin/exportfs -ra',
    refreshonly => true,
    path        => ['/usr/sbin'],
  }

  # SELinux booleans for NFS
  exec { 'setsebool-nfs-export-all-rw':
    command => '/usr/sbin/setsebool -P nfs_export_all_rw on',
    unless  => '/usr/sbin/getsebool nfs_export_all_rw | /usr/bin/grep -q on$',
    path    => ['/usr/sbin', '/usr/bin'],
  }

  exec { 'setsebool-nfs-export-all-ro':
    command => '/usr/sbin/setsebool -P nfs_export_all_ro on',
    unless  => '/usr/sbin/getsebool nfs_export_all_ro | /usr/bin/grep -q on$',
    path    => ['/usr/sbin', '/usr/bin'],
  }

  service { 'nfs-server':
    ensure  => running,
    enable  => true,
    require => Package['nfs-utils'],
  }
}
