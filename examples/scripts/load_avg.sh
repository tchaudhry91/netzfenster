#!/bin/sh
# Plugin: system load average (1m, 5m, 15m).
# Contract: prints one line per display row.
read one five fifteen rest < /proc/loadavg
echo "load 1m:  $one"
echo "load 5m:  $five"
echo "load 15m: $fifteen"
