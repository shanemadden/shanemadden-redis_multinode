class redis_multinode::install {
  if $redis_multinode::use_github == true {
    # We're using github - cloning from github to the specified branch, then we'll compile from there.
    package { "git":
      ensure   => present,
    }

    vcsrepo { "/var/redis/redis_git":
      ensure   => latest,
      provider => git,
      source   => "https://github.com/antirez/redis.git",
      revision => $redis_multinode::version,
      require  => File["/var/redis"],
    }

    exec { "compile and install redis":
      command  => "/usr/bin/make distclean && /usr/bin/make && /usr/bin/make install",
      cwd      => "/var/redis/redis_git",
      unless   => "/usr/bin/[ -f /usr/local/bin/redis-server ] && /usr/local/bin/redis-server --version | grep -F \"sha=$(/usr/bin/git rev-parse HEAD | /bin/cut -c1-8)\"",
      require  => Vcsrepo["/var/redis/redis_git"],
    }
  } else {
    # Not using github - download tarball from releases.
    exec { "download redis tarball":
      command  => "/usr/bin/wget http://download.redis.io/releases/redis-${redis_multinode::version}.tar.gz",
      cwd      => "/var/redis/",
      creates  => "/var/redis/redis-${redis_multinode::version}.tar.gz",
      require  => [ Class["redis_multinode::prereqs"], File["/var/redis"], ],
    }

    exec { "extract redis tarball":
      command  => "/bin/tar xf redis-${redis_multinode::version}.tar.gz",
      cwd      => "/var/redis/",
      creates  => "/var/redis/redis-${redis_multinode::version}",
      require  => Exec["download redis tarball"],
    }

    exec { "compile and install redis":
      command  => "/usr/bin/make distclean && /usr/bin/make && /usr/bin/make install",
      cwd      => "/var/redis/redis-${redis_multinode::version}/",
      unless   => "/usr/bin/[ -f /usr/local/bin/redis-server ] && /usr/local/bin/redis-server --version | grep -F \"v=${redis_multinode::version}\"",
      require  => Exec["extract redis tarball"],
    }
  }
  
  file { [
    "/var/redis",
    "/etc/redis",
    "/var/log/redis",
    ]:
    ensure   => directory,
  }

  file { "/etc/logrotate.d/redis":
    ensure   => present,
    source   => "puppet:///modules/redis_multinode/redis.logrotate",
  }

  # setup for the script that manages the haproxy config..
  file { "/var/redis/check-masters.py":
    ensure   => present,
    source   => "puppet:///modules/redis_multinode/check-masters.py",
    mode     => 755,
    require  => File["/var/redis"],
  }
  
  # Run the master check every minute..
  cron { "redis-check-masters":
    command  => "/var/redis/check-masters.py > /dev/null 2>&1",
    user     => root,
    minute   => "*",
    require  => [ File["/var/redis/check-masters.py"], Class["redis_multinode::prereqs"], ],
  }
}
