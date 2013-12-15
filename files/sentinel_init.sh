#!/bin/sh
###############
# chkconfig: 2345 95 20
# description: redis_sentinel
### BEGIN INIT INFO
# Provides: redis_sentinel
# Required-Start: 
# Required-Stop: 
# Should-Start: 
# Should-Stop: 
# Short-Description: start and stop redis_sentinel
# Description: Redis daemon
### END INIT INFO

REDIS_PORT="26379"

EXEC=/usr/local/bin/redis-server
PIDFILE="/var/run/redis-sentinel.pid"
CONF="/etc/redis/sentinel.conf"

set -e

start()
{
    if [ -x $PIDFILE ]
    then
        echo "$PIDFILE exists, process is already running or crashed"
    else
        echo "Starting Redis Sentinel..."
        $EXEC $CONF --sentinel
    fi
}

stop()
{
    if [ ! -f $PIDFILE ]
    then
        echo "$PIDFILE does not exist, process is not running"
    else
        PID=$(cat $PIDFILE)
        echo "Stopping ..."
        kill ${PID} || /bin/true
        while [ -x /proc/${PID} ]
        do
            echo "Waiting for Sentinel to shutdown ..."
            sleep 1
        done
        echo "Redis Sentinel stopped"
    fi
}

restart()
{
    stop
    start
}

status()
{
    if [ ! -f $PIDFILE ]
    then
        echo "$PIDFILE does not exist, sentinel is not running"
        exit 3
    elif [ ! -x /proc/$(cat $PIDFILE) ]
    then
        echo "$PIDFILE exists, process is not running though"
        exit 1
    else
        echo "sentinel is running with PID $(cat $PIDFILE)"
        exit 0
    fi
}

case "$1" in
    start)
        start 
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $SCRIPTNAME {start|stop|restart|status}"
        ;;
esac
