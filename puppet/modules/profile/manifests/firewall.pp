# Profile: Firewall configuration
# Manages: firewalld service and per-role ports from Hiera
class profile::firewall (
  Array[String] $allowed_services = lookup('profile::firewall::allowed_services', Array, 'unique', ['ssh']),
) {

  # Ensure firewalld is managed by base profile
  # Add allowed services
  $allowed_services.each |String $service| {
    exec { "firewall-allow-${service}":
      command => "/usr/bin/firewall-cmd --permanent --add-service=${service} && /usr/bin/firewall-cmd --reload",
      unless  => "/usr/bin/firewall-cmd --query-service=${service}",
      path    => ['/usr/bin'],
      require => Service['firewalld'],
    }
  }
}
