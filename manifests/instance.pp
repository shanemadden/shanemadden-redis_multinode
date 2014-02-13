define redis_multinode::instance (
  $instance_name    = $title,
  $role             = hiera("redis_multinode::${title}::role", "master"),
  $master_ip        = hiera("redis_multinode::${title}::master_ip", $ipaddress),
  $listen_reader    = hiera("redis_multinode::${title}::listen_reader", "6379"),
  $listen_writer    = hiera("redis_multinode::${title}::listen_writer", "6380"),
  $password         = hiera("redis_multinode::${title}::password", "changeme"),
  $slave_priority   = hiera("redis_multinode::${title}::slave_priority", "100"),
  $appendonly       = hiera("redis_multinode::${title}::appendonly", "yes"),
  $appendfsync      = hiera("redis_multinode::${title}::appendfsync", "everysec"),
  $maxmemory_policy = hiera("redis_multinode::${title}::maxmemory_policy", "volatile-lru"),
  $loglevel         = hiera("redis_multinode::${title}::loglevel", "notice"),
  # Careful with this.  It should always be a *majority* of your sentinels.
  # So if there are three nodes running sentinels, it should be set to 2.
  # If there are six, it should be 4.  If 20, then 11.
  $quorum           = hiera("redis_multinode::${title}::quorum", 2),
  $down_after_ms    = hiera("redis_multinode::${title}::down_after_ms", 15000),
)
{
  case $osfamily {
    debian: {
      $touch = "/usr/bin/touch"
    }
    redhat: {
      $touch = "/bin/touch"
    }
  }
  # We want to create the file and, if applicable, put the initial slaveof config in
  # (we don't want augeas managing that, since sentinel will be setting it on failover and managing the role from then on)
  exec { "create ${listen_reader}.conf":
    command   => $role ? {
      master  => "${touch} /etc/redis/${listen_reader}.conf",
      slave   => "/bin/echo \"slaveof ${master_ip} ${listen_reader}\" > /etc/redis/${listen_reader}.conf",
    },
    creates   => "/etc/redis/${listen_reader}.conf",
    require   => Class["redis_multinode::install"],
  }

  # Augeas is needed since we can't manage the entire file without stomping on sentinel's config changes.
  # Thankfully it's up to the task with the Redis lens.
  augeas { "config ${listen_reader}":
    lens      => "Redis.lns",
    incl      => "/etc/redis/${listen_reader}.conf",
    context   => "/files/etc/redis/${listen_reader}.conf",
    changes   => [
      "set #comment[1] '${instance_name}'",
      "set port '${listen_reader}'",
      "set pidfile '/var/run/redis-${listen_reader}.pid'",
      "set logfile '/var/log/redis/${listen_reader}.log'",
      "set dir '/var/redis/${listen_reader}'",
      "set slave-serve-stale-data 'yes'",
      "set slave-read-only 'yes'",
      "set daemonize 'yes'",
      "set timeout '1800'",
      "set tcp-keepalive '60'",
      "set loglevel '${loglevel}'",
      "set databases '16'",
      # Need to come up with a good way to pass this in as a param...
      "set save[1]/seconds '600'",
      "set save[1]/keys '1'",
      "set save[2]/seconds '300'",
      "set save[2]/keys '100'",
      "set save[3]/seconds '60'",
      "set save[3]/keys '10000'",
      "set stop-writes-on-bgsave-error 'no'",
      "set rdbcompression 'yes'",
      "set rdbchecksum 'yes'",
      "set dbfilename 'dump.rdb'",
      "set repl-ping-slave-period '10'",
      "set repl-timeout '60'",
      "set repl-disable-tcp-nodelay 'no'",
      "set repl-backlog-size '1mb'",
      "set repl-backlog-ttl '3600'",
      "set slave-priority '100'",
      "set maxmemory-policy '${maxmemory_policy}'",
      "set appendonly '${appendonly}'",
      "set appendfsync '${appendfsync}'",
      "set no-appendfsync-on-rewrite 'no'",
      "set auto-aof-rewrite-percentage '${slave_priority}'",
      "set auto-aof-rewrite-min-size '64mb'",
      "set lua-time-limit '5000'",
      "set slowlog-log-slower-than '10000'",
      "set slowlog-max-len '128'",
      "set hash-max-ziplist-entries '512'",
      "set hash-max-ziplist-value '64'",
      "set list-max-ziplist-entries '512'",
      "set list-max-ziplist-value '64'",
      "set set-max-intset-entries '512'",
      "set zset-max-ziplist-entries '128'",
      "set zset-max-ziplist-value '64'",
      "set activerehashing 'yes'",
      "set hz '10'",
      "set aof-rewrite-incremental-fsync 'yes'",
      "set requirepass '${password}'",
      "set masterauth '${password}'",
      #https://github.com/antirez/redis/issues/1434
      #"set min-slaves-to-write '1'",
      #"set min-slaves-max-lag '10'",
    ],
    require   => Exec["create ${listen_reader}.conf"],
    notify    => Service["redis_${listen_reader}"],
  }

  # Create the working directory for the instance which contains its persistence files
  file { "/var/redis/${listen_reader}":
    ensure    => directory,
  }

  # This feeds the config info over to the HAProxy config.
  file { "/var/redis/${listen_reader}/haproxy_port":
    content   => "${listen_writer}",
  }

  file { "/etc/init.d/redis_${listen_reader}":
    ensure    => present,
    content   => template('redis_multinode/redis_init.erb'),
    require   => [ Augeas["config ${listen_reader}"], File["/var/redis/${listen_reader}"], ],
    mode      => 755,
  }

  service { "redis_${listen_reader}":
    enable    => true,
    ensure    => running,
    require   => File["/etc/init.d/redis_${listen_reader}"],
    subscribe => Exec["compile and install redis"],
  }

  # We'll set the master node to a higher config epoch initially so that if there's a conflict in config it'll reconfig others
  $initial_epoch = $role ? {
    master  => '1',
    slave   => '0',
  }

  # The sentinel config file has other instances in it, and can change at any time due to failover or node join.
  # We'll just check and see if this instance is configured and add it if not - we can't manage the whole file.
  exec { "insert sentinel config ${listen_reader}":
    command   => "/bin/echo -e \"sentinel monitor ${instance_name} ${master_ip} ${listen_reader} ${quorum}\\nsentinel down-after-milliseconds ${instance_name} ${down_after_ms}\\nsentinel auth-pass ${instance_name} ${password}\\nsentinel config-epoch ${instance_name} ${initial_epoch}\" >> /etc/redis/sentinel.conf",
    unless    => "/bin/grep -F \"${instance_name}\" /etc/redis/sentinel.conf",
    notify    => Service["redis_sentinel"],
    require   => [ Service["redis_${listen_reader}"], Exec["create sentinel.conf"], ],
  }
  
  exec { "change quorum size ${listen_reader}":
    command   => "/usr/local/bin/redis-cli -p 26379 sentinel set ${instance_name} quorum ${quorum}",
    unless    => "/usr/local/bin/redis-cli -p 26379 sentinel master ${instance_name} | /bin/grep -A 1 quorum | /bin/grep ${quorum}",
    require   => Service["redis_sentinel"],
  }

  exec { "change failover timer ${listen_reader}":
    command   => "/usr/local/bin/redis-cli -p 26379 sentinel set ${instance_name} down-after-milliseconds ${down_after_ms}",
    unless    => "/usr/local/bin/redis-cli -p 26379 sentinel master ${instance_name} | /bin/grep -A 1 down-after-milliseconds | /bin/grep ${down_after_ms}",
    require   => Service["redis_sentinel"],
  }
}
