#!/bin/sh
# Plugin: running process count.
# Contract: prints one line per display row.
count=$(ps -e --no-headers 2>/dev/null | wc -l)
echo "PROCS"
echo "count: ${count}"
