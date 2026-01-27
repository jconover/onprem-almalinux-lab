# Profile: Prometheus node_exporter
# Manages: binary, systemd unit, user/group, firewall port
class profile::monitoring (
  String $node_exporter_version = lookup('profile::monitoring::node_exporter_version', String, 'first', '1.7.0'),
  String $listen_address        = '0.0.0.0:9100',
) {

  $archive_name = "node_exporter-${node_exporter_version}.linux-amd64"
  $download_url = "https://github.com/prometheus/node_exporter/releases/download/v${node_exporter_version}/${archive_name}.tar.gz"

  group { 'node_exporter':
    ensure => present,
    system => true,
  }

  user { 'node_exporter':
    ensure  => present,
    gid     => 'node_exporter',
    system  => true,
    shell   => '/usr/sbin/nologin',
    home    => '/',
    require => Group['node_exporter'],
  }

  # Download and extract
  exec { 'download-node-exporter':
    command => "/usr/bin/curl -sL ${download_url} -o /tmp/node_exporter.tar.gz && /usr/bin/tar xzf /tmp/node_exporter.tar.gz -C /tmp/",
    creates => "/tmp/${archive_name}/node_exporter",
    path    => ['/usr/bin'],
  }

  file { '/usr/local/bin/node_exporter':
    ensure  => file,
    source  => "/tmp/${archive_name}/node_exporter",
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    require => Exec['download-node-exporter'],
    notify  => Service['node_exporter'],
  }

  file { '/etc/systemd/system/node_exporter.service':
    ensure  => file,
    content => epp('profile/node_exporter.service.epp', {
      'listen_address' => $listen_address,
    }),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    notify  => Service['node_exporter'],
  }

  service { 'node_exporter':
    ensure  => running,
    enable  => true,
    require => [
      File['/usr/local/bin/node_exporter'],
      File['/etc/systemd/system/node_exporter.service'],
      User['node_exporter'],
    ],
  }

  # Allow node_exporter port through firewall
  exec { 'firewall-allow-node-exporter':
    command => '/usr/bin/firewall-cmd --permanent --add-port=9100/tcp && /usr/bin/firewall-cmd --reload',
    unless  => '/usr/bin/firewall-cmd --query-port=9100/tcp',
    path    => ['/usr/bin'],
    require => Service['firewalld'],
  }
}
