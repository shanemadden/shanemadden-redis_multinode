#!/usr/bin/python
import redis
import os

r = redis.StrictRedis(host='localhost', port=26379, db=0)
changes = False
for instancedata in r.sentinel('masters'):
    # capture master ip and port from redis query:
    masterip = instancedata['ip']
    masterport = instancedata['port']

    # grab haproxy listener port from this instance's directory:
    writerportfile = open(('/var/redis/%s/haproxy_port' % masterport), 'r')
    writerport = writerportfile.read()
    writerportfile.close()

    try:
        configfile = open(('/etc/haproxy/cfg.d/%s.cfg' % masterport), 'r')
        config = configfile.read()
        configfile.close()
    except IOError:
        # probably doesn't exist, let's make sure we set it.
        config = ''

    # Build out what the config should look like given the current master of this instance:
    targetconfig = ('''
listen redis-%s
    bind :%s
    mode tcp
    balance roundrobin
    server %s-master %s:%s

''' % (masterport, writerport, masterport, masterip, masterport))

    # compare whether the read config matches what we think the config should be now.
    if not targetconfig == config:
        # the config changed, let's rewrite it
        # we'll also set the boolean flag that tells the script to reload haproxy at the end
        changes = True
        configfile = open('/etc/haproxy/cfg.d/%s.cfg' % masterport, 'w')

        configfile.write(targetconfig)
        configfile.close()

if changes:
    os.system('/bin/cat /etc/haproxy/cfg.d/*.cfg > /etc/haproxy/haproxy.cfg')
    os.system('/etc/init.d/haproxy reload > /dev/null 2>&1')
