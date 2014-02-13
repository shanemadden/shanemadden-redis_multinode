class redis_multinode (
  $version   = '2.8.5', # 2.8.5 is required for online reconfig of quorum size and timeout
  $use_github = false, # if this is true, $version should be a branch name on the git repo https://github.com/antirez/redis
)
{
  include redis_multinode::prereqs
  include redis_multinode::install
  include redis_multinode::haproxy
  include redis_multinode::sentinel

  $instances = hiera_array('redis_multinode::instances', [])
  redis_multinode::instance{ $instances: }
}
