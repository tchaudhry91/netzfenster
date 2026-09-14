#!/bin/sh
# Memory usage as an ASCII progress bar.
used=$(free -m | awk 'NR==2 {print $3}')
total=$(free -m | awk 'NR==2 {print $2}')
pct=$((used * 100 / total))
filled=$((pct * 14 / 100))
bar=""
i=0
while [ $i -lt $filled ]; do bar="${bar}#"; i=$((i+1)); done
while [ $i -lt 14 ]; do bar="${bar}-"; i=$((i+1)); done
echo "MEM"
echo "[${bar}] ${pct}%"
