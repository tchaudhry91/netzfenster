#!/bin/sh
# Meta view: cycles through all viewports, one per 5-minute slot.
# Contract: prints one line per display row (delegates to the active viewport).
now=$(date +%s)
slot=$(( (now / 30) % 9 ))
case $slot in
  0) exec scripts/load_avg.sh ;;
  1) exec scripts/clock.sh ;;
  2) exec scripts/mem.sh ;;
  3) exec scripts/progress.sh ;;
  4) exec scripts/disk.sh ;;
  5) exec scripts/uptime.sh ;;
  6) exec scripts/cpu.sh ;;
  7) exec scripts/net.sh ;;
  8) exec scripts/procs.sh ;;
esac
