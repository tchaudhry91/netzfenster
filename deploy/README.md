# Deploying the netzfenster server

This is what's actually running on `rpi4` (Raspbian 11, aarch64, LAN IP
`192.168.29.28`, Tailscale `rpi4.ts.tux-sudo.com`).

The server binary is a **static musl build** — no runtime dependencies. The
same binary CI produces (`server-aarch64-linux-musl` artifact) is exactly
this.

## Cross-compile

```sh
cd server
zig build -Dtarget=aarch64-linux-musl -Doptimize=ReleaseSafe
```

Output: `server/zig-out/bin/server` (ELF aarch64, statically linked).

## Install on the Pi

```sh
# from the dev machine
scp server/zig-out/bin/server deploy/netzf.service rpi4.ts.tux-sudo.com:/tmp/
tar czf /tmp/netzf-data.tgz -C deploy/data .
scp /tmp/netzf-data.tgz rpi4.ts.tux-sudo.com:/tmp/

# on the Pi
ssh rpi4.ts.tux-sudo.com
sudo mkdir -p /opt/netzf/bin
sudo tar xzf /tmp/netzf-data.tgz -C /opt/netzf
sudo install -m 755 /tmp/server /opt/netzf/bin/server
sudo cp /tmp/netzf.service /etc/systemd/system/netzf.service
sudo systemctl daemon-reload
sudo systemctl enable --now netzf
```

## Verify

```sh
systemctl is-active netzf                      # active
curl -s -o /dev/null -w '%{http_code}\n' \
  'http://192.168.29.28:8989/frame?viewport=load_avg&rows=5&cols=21'   # 200
```

## Configuration

The server reads two env vars (set in the unit):

| Env                 | Default (unit)   | Meaning                                  |
|---------------------|------------------|------------------------------------------|
| `NETZF_HOME`        | `/opt/netzf`     | data dir: `<name>.json` + `scripts/`     |
| `NETZF_LISTEN_ADDR` | `0.0.0.0:8989`   | listen address                           |

## Updating

Replace the binary and bounce the service — the data dir (`deploy/data/`
in this repo) is never touched by an upgrade:

```sh
scp server/zig-out/bin/server rpi4.ts.tux-sudo.com:/tmp/server
ssh rpi4.ts.tux-sudo.com 'sudo install -m 755 /tmp/server /opt/netzf/bin/server && sudo systemctl restart netzf'
```

## Firmware side

The ESP32's server URL is a build-time config: `idf.py menuconfig` →
*Netzfenster Configuration → Netzfenster Server URL* → set to
`http://192.168.29.28:8989`.