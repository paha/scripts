#!/bin/bash
# to be executed by zabbix-agent

# disk utilization test (local partitions only)
# the first argument is the treshhold (% of utilization)

[ $(ps -e | grep -c $0) -gt 0 ] && {
	echo "ERROR getting disk utilization"
	exit 0
}

Treshhold=${1:?ERROR getting disk utilization}
FAILED=$(df -Pl -x tmpfs | awk "{gsub(/%/,\"\")}; \$5 > $Treshhold {print \$1}" 2>/dev/null | awk '!/Filesystem/')
[ -z "$FAILED" ] && echo OK || echo $FAILED
