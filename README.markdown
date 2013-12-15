redis_multinode
===============

This module is intended to deploy a group of systems running Redis instances, with replication and failover managed by Redis Sentinel.

Since most Redis client stacks don't have any mechanism for finding the master in a group like this, this module also configures HAProxy, with a listening port on each node which will proxy to the writable node.

So, for each instance, there will be one listening port which is the Redis listener (for instance, 6379) which will always be available for read-only operations, and may be able to accept write operations if that node's the master, as well as an HAProxy listener (for instance, 6380) which will track the writable node for the instance, on whichever node it resides.

## Usage ##

A note on the instance configuration - you'll be setting a mode for each system; master, or slave of a different system.  Note that this is just for the *initial setup* - if/when Sentinel fails your instance over to another node due to the master failing, the module makes no attempt to try to enfore which node holds master.

### Hiera ###

I use this with Hiera handling node classifications ([if you haven't looked at Hiera, you should!](http://docs.puppetlabs.com/hiera/1/)), so it's built to be pleasant if you do the same.  For instance, to set up a node group with two separate instances of Redis for two applications, you could do something like this.

common.yaml

    redis_multinode::test::listen_reader   : 6379
    redis_multinode::test::listen_writer   : 6380
    redis_multinode::test::password        : changeme
    redis_multinode::test::quorum          : 2

    redis_multinode::my_app::listen_reader : 6381
    redis_multinode::my_app::listen_writer : 6382
    redis_multinode::my_app::password      : 87W98XqulD
    redis_multinode::my_app::quorum        : 2

redis1.example.com.yaml

    classes:
      - redis_multinode

    redis_multinode::instances:
      - test
      - my_app

    redis_multinode::version               : 2.8.3
    redis_multinode::test::role            : master
    redis_multinode::my_app::role          : master

redis2.example.com.yaml (and redis3.example.com.yaml)

    classes:
      - redis_multinode

    redis_multinode::instances:
      - test
      - my_app

    redis_multinode::version               : 2.8.3
    redis_multinode::test::role            : slave
    redis_multinode::test::master_ip       : 10.0.50.10
    redis_multinode::my_app::role          : slave
    redis_multinode::my_app::master_ip     : 10.0.50.10

Note that since we have 3 nodes participating, the `quorum` is set to 2.  To avoid a split-brain scenario, the `quorum` setting must always be configured to a majority of your cluster nodes - so in a 10 node group, `quorum` should be 6.

### Standard Node Definitions ###

This module also works with standard node definitions.

    node 'redis1.example.com' {
      class { "redis_multinode":
        version       => "2.8.3",
      }
      redis_multinode::instance { "test":
        role          => master,
        listen_reader => 6379,
        listen_writer => 6380,
        password      => "changeme",
        quorum        => 2,
      }
      redis_multinode::instance { "my_app":
        role          => master,
        listen_reader => 6381,
        listen_writer => 6382,
        password      => "changeme",
        quorum        => 2,
      }
    }

    node 'redis2.example.com', 'redis3.example.com' {
      class { "redis_multinode":
        version       => "2.8.3",
      }
      redis_multinode::instance { "test":
        role          => slave,
        master_ip     => "10.0.50.10"
        listen_reader => 6379,
        listen_writer => 6380,
        password      => "changeme",
        quorum        => 2,
      }
      redis_multinode::instance { "my_app":
        role          => slave,
        master_ip     => "10.0.50.10"
        listen_reader => 6381,
        listen_writer => 6382,
        password      => "changeme",
        quorum        => 2,
      }
    }

## Important Notes ##

The listening ports configuration, as well as the password, should be the same for each node participating in a group for a given instance.. so in the examples above, if the `test` instance were only configured on one node of the three, you'd still want the ports and password for all nodes with `my_app` configured to match.

Since the master/slave relationship is handled by Sentinel, Puppet can't have complete control over the config files.  Because of this, changing the configuration of an instance (the resource title, the listening ports, or the password) is likely to break things - the Redis instance will be reconfigured but the Sentinel instances will end up either configured incorrectly or with duplicate configuration.

Tested on RHEL/CentOS 6 (requires EPEL to be enabled) and Ubuntu 13.10.
