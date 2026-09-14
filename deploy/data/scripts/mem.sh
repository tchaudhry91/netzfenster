#!/bin/sh
# Plugin: memory usage (MB).
free -m | awk 'NR==2 {printf "mem used: %s/%sM\n", $3, $2}'
free -m | awk 'NR==2 {printf "mem free: %sM\n", $4}'
