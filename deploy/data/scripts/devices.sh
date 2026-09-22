#!/bin/sh
# Plugin: meta view — the state of every PERSONAL device, one frame each.
#
# Usage: devices.sh [rows]        (rows = the grid height, default 5)
#
# Why the row count is an argument: `writeText` (grid.zig) fills a Grid and hands
# the rest of the output to the next frame, so the page height IS the client's
# `rows`. The plugin is spawned with no way to see the request, so the height has
# to come in through the viewport's `cmd`:
#
#   ESP32 (21x5)   "cmd": "scripts/devices.sh 5"
#   terminal (21x8) "cmd": "scripts/devices.sh 8"
#
# Get this wrong and devices are spliced across frames instead of cycling whole.
# Each branch below prints exactly `rows` lines, none longer than `cols` (a line
# that wraps eats a row and shifts every later block). The rx/tx line is
# cumulative since boot, not a rate: rate() on these counters jumps by 1000x
# whenever an interface resets or a virtual one appears.
#
# Sources:
#   tailscale status --json   which devices exist, tailnet IP, online state
#   VictoriaMetrics           cpu / mem / disk / load / uptime / traffic
#   opsy/inventory_rules.yml  classify.personal_devices -> the regex below
#
# No credentials: vm.ts.tux-sudo.com answers on the tailnet unauthenticated.

rows=${1:-5}
VM=${NETZF_VM:-https://vm.ts.tux-sudo.com}
TMO=${NETZF_TIMEOUT:-5}

# opsy/inventory_rules.yml -> classify.personal_devices, as one ERE.
personal='^(qe[a-z0-9]+|dev|rpi4)$'

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM

# --- 1. who exists ---------------------------------------------------------
# .Self matters: on the Pi the Pi itself is Self, not a peer, so without it rpi4
# never gets a frame. `dev-tc` is the tailnet label for `dev` (opsy `rename:`).
tailscale status --json 2>/dev/null \
  | jq -r '([.Self] + (.Peer | to_entries | map(.value)))
           | .[]
           | [ (.HostName|ascii_downcase), .TailscaleIPs[0], .Online, .LastSeen ]
           | @tsv' \
  | sort > "$tmp/peers" || :

# --- 2. metrics, in ONE request --------------------------------------------
# `label_replace(...,"k",...)` tags each expression and PromQL `or` unions the
# results into a single vector, so this is one round trip instead of seven.
# `sum by(instance)` drops the labels that differ between expressions (device,
# mountpoint, ...) so each instance gives one value per k.
expr='
label_replace(sum by(instance)(100*(1-avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])))),"k","cpu","","")
or label_replace(sum by(instance)(100*(1-node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes)),"k","mem","","")
or label_replace(sum by(instance)(100*(1-node_filesystem_avail_bytes{mountpoint="/"}/node_filesystem_size_bytes{mountpoint="/"})),"k","disk","","")
or label_replace(sum by(instance)(node_load1),"k","load","","")
or label_replace(sum by(instance)(time()-node_boot_time_seconds),"k","up","","")
or label_replace(sum by(instance)(node_network_receive_bytes_total{device!~"lo|veth.*|docker.*|br-.*"}),"k","rx","","")
or label_replace(sum by(instance)(node_network_transmit_bytes_total{device!~"lo|veth.*|docker.*|br-.*"}),"k","tx","","")
'
curl -sS --max-time "$TMO" -G "$VM/api/v1/query" --data-urlencode "query=$expr" 2>/dev/null \
  | jq -r '.data.result[]? | [ .metric.instance, .metric.k, .value[1] ] | @tsv' \
  > "$tmp/metrics" || :

# --- 3. render -------------------------------------------------------------
awk -F'\t' -v personal="$personal" -v rows="$rows" '
  function bytes(b,   i) {                         # 12345 -> "12.3k"
    i = 1
    while (b >= 1000 && i < 5) { b /= 1000; i++ }
    return (i == 1) ? sprintf("%.0f", b) : sprintf("%.1f%s", b, substr("kMGT", i - 1, 1))
  }
  function dur(s,   d, h) {                        # seconds -> "75d 02h"
    d = int(s / 86400); h = int((s % 86400) / 3600)
    return (d > 0) ? d "d " sprintf("%02dh", h) : sprintf("%dh", h)
  }
  function pct(s) { return (s == "") ? " -" : sprintf("%2d", s + 0) }

  FILENAME == ARGV[1] {                            # peers: name ip online lastseen
    nm = $1
    if (nm == "dev-tc") nm = "dev"
    if (nm !~ personal || (nm in known)) next
    known[nm] = 1; name[++n] = nm
    ip[nm] = $2; online[nm] = $3
    last[nm] = substr($4, 1, 10)                   # -> "2026-09-17"
    next
  }
  { v[$1 "|" $2] = $3 }                            # metrics: instance k value

  function g(who, k) { return v[who "|" k] }

  END {
    for (pass = 1; pass <= 2; pass++)              # online group, then offline
      for (i = 1; i <= n; i++) {
        who = name[i]
        if ((online[who] == "true") != (pass == 1)) continue

        if (g(who, "cpu") != "") {                 # fresh scrape
          printf "%s  up %s\n", who, dur(g(who,"up") + 0);                 p = 1
          printf "cpu %s%%  mem %s%%\n", pct(g(who,"cpu")), pct(g(who,"mem")); p++
          printf "disk %s%%  load %.2f\n", pct(g(who,"disk")), g(who,"load") + 0; p++
          printf "rx %s tx %s\n", bytes(g(who,"rx") + 0), bytes(g(who,"tx") + 0); p++
          print "ip " ip[who];                                              p++
        } else {
          print who;                                                        p = 1
          if (online[who] == "true") { print "online, no scrape"; p++ }
          else { print "OFFLINE"; p++; print "seen " last[who]; p++ }
          print "ip " ip[who];                                              p++
        }
        while (p++ < rows) print ""                # pad the page out
      }
  }
' "$tmp/peers" "$tmp/metrics" | cut -c1-21
