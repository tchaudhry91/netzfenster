#!/bin/sh
# Plugin: CPU usage percentage (sampled over 1 second).
# Contract: prints one line per display row.
set -- $(awk 'NR==1 {print $2+$3+$4+$5+$6+$7+$8+$9, $5+$6}' /proc/stat)
total1=$1; idle1=$2
sleep 1
set -- $(awk 'NR==1 {print $2+$3+$4+$5+$6+$7+$8+$9, $5+$6}' /proc/stat)
total2=$1; idle2=$2
total=$((total2 - total1))
idle=$((idle2 - idle1))
if [ "$total" -gt 0 ]; then
  pct=$(( (total - idle) * 100 / total ))
else
  pct=0
fi
echo "CPU"
echo "usage: ${pct}%"
