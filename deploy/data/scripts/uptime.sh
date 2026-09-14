#!/bin/sh
# Plugin: uptime and current load.
# Contract: prints one line per display row.
up=$(uptime -p | sed 's/^up //')
echo "up: $up"
read one five fifteen rest < /proc/loadavg
echo "load: $one"
