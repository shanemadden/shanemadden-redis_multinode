class redis_multinode::haproxy {
  # Custom bit of silliness to be able to glue together the HAProxy configs for all of our different instances.
  file { "/etc/haproxy/cfg.d/":
    ensure  => "directory",
    require => Package["haproxy"],
  }

  file { "/etc/haproxy/cfg.d/0-global.cfg":
    ensure  => "present",
    source  => "puppet:///modules/redis_multinode/haproxy-global.cfg",
    require => File["/etc/haproxy/cfg.d/"],
  }
  # .. then the check-masters.py cron running every minute will use this to write over /etc/haproxy/haproxy.cfg

  # We need to give it a custom haproxy init file, as we want reload to do -st instead of -sf.
  file { "/etc/init.d/haproxy":
    ensure  => present,
    source  => "puppet:///modules/redis_multinode/haproxy_init-${osfamily}",
    mode    => 755,
    require => Package["haproxy"],
  }

  service { "haproxy":
    enable  => true,
    ensure  => running,
    restart => "/usr/sbin/service haproxy reload",
  }
}
