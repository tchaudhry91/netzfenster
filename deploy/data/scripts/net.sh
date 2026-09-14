#!/bin/sh
# Plugin: primary IPv4 address.
# Contract: prints one line per display row.
ip=$(hostname -i 2>/dev/null | awk '{print $1}')
echo "NET"
echo "ip: ${ip:-none}"
