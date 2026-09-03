#!/bin/sh
# Plugin: root filesystem usage.
# Contract: prints one line per display row.
df -h / | awk 'NR==2 {print "disk used: " $3; print "disk size: " $2; print "use: " $5}'
