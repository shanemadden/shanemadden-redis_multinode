class redis_multinode::sentinel {
  # Build out the initial sentinel.conf file with the base settings.  Cannot manage the whole file since it changes with the monitored instance state
  exec { "create sentinel.conf":
    command   => "/bin/echo -e \"port 26379\\npidfile /var/run/redis-sentinel.pid\\nlogfile /var/log/redis/sentinel.log\\ndaemonize yes\" > /etc/redis/sentinel.conf",
    creates   => "/etc/redis/sentinel.conf",
    require   => Class["redis_multinode::install"],
  }

  file { "/etc/init.d/redis_sentinel":
    ensure    => present,
    source    => "puppet:///modules/redis_multinode/sentinel_init.sh",
    require   => Exec["create sentinel.conf"],
    mode      => 755,
  }

  service { "redis_sentinel":
    enable    => true,
    ensure    => running,
    require   => File["/etc/init.d/redis_sentinel"],
    subscribe => Exec["compile and install redis"],
  }
}
