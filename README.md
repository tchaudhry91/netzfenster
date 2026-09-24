# netzfenster

A **network framebuffer**.

A tiny ESP32 + OLED renders whatever a remote server tells it. The ESP32 is a
dumb renderer — a monitor with a WiFi antenna. All the intelligence lives on a
more powerful machine (a Pi, a laptop, a server) that computes a grid of cells
and serves it over HTTP.

*Netzfenster* is German for "network window" (*Netz* = network, *Fenster* =
window). The network is the soul of the project, not the pixels.

## Architecture

```
┌─────────────────────┐      ┌──────────────────┐      ┌──────────────┐
│  server (the "GPU")  │      │  ESP32-S3        │      │  OLED        │
│                      │ WiFi │  (the renderer)  │ SPI  │  (the screen)│
│  computes the cell   │ ───► │  holds framebuffer│ ───► │  dumb pixels │
│  grid, serves it     │      │  renders + pushes│      │              │
└─────────────────────┘      └──────────────────┘      └──────────────┘
```

- **server** — computes the cell grid, serves it over HTTP. The "GPU".
- **client** — fetches the grid, renders it. A terminal client exists for
  development; the ESP32/OLED firmware is the real target.
- **OLED** — dumb pixels.

The server never thinks in pixels. It lays out a grid of cells; the client
rasterizes cells to pixels. The unit of rendering is the **cell**, not the pixel.

## Repo layout

| Path        | What it is                                                            |
| ----------- | --------------------------------------------------------------------- |
| `server/`   | The Zig HTTP server that serves frame sequences. See [`server/README.md`](server/README.md). |
| `client/`   | A throwaway terminal client for testing without hardware.             |
| `firmware/` | ESP32-S3 firmware (C, ESP-IDF): WiFi → HTTP → JSON → OLED.            |
| `deploy/`   | systemd unit + data dir + scripts for the running Pi deployment.      |
| `examples/` | Example viewports and plugin scripts.                                 |

The server was written by hand as a Zig learning project — no framework, the
accept loop, HTTP parsing, and memory management are all explicit. See
[`AGENTS.md`](AGENTS.md).

## Quickstart

### 1. Run the server

```sh
cd server
zig build run
```

Requires Zig 0.16.0. By default it listens on `127.0.0.1:8989` and reads its data
dir from `NETZF_HOME` (default `/opt/netzf`). For a local run, point it at the
example/deploy data:

```sh
NETZF_HOME=../deploy/data NETZF_LISTEN_ADDR=127.0.0.1:8989 zig build run
```

### 2. Ask it for a frame

```sh
curl 'http://127.0.0.1:8989/frame?viewport=load_avg&rows=5&cols=21'
```

### 3. Or render it in your terminal

```sh
cd client
zig build run -- load_avg 127.0.0.1:8989 5 21
```

### 4. Firmware

The ESP32 server URL and WiFi credentials are build-time config. See
[`firmware/`](firmware/) and run `idf.py menuconfig` →
*Netzfenster Configuration*. Credentials live in `sdkconfig`, which is
gitignored.

## Configuration

The server reads two environment variables:

| Var                 | Default            | Meaning                             |
| ------------------- | ------------------ | ----------------------------------- |
| `NETZF_HOME`        | `/opt/netzf`       | Data dir: viewport JSONs + scripts. |
| `NETZF_LISTEN_ADDR` | `127.0.0.1:8989`   | Address to listen on.               |

A **viewport** is a JSON file in `$NETZF_HOME`, named `<viewport>.json`:

```json
{
  "cmd": "scripts/load_avg.sh",
  "refresh_ms": 60000
}
```

A **plugin** is any shell command (`cmd`), run via `sh -c` with `$NETZF_HOME` as
the working directory. It prints plain-text lines to stdout — one line per row.
The server writes those lines into the grid, wrapping long lines with a 2-space
indent and paginating into multiple frames when the output exceeds `rows`.

## Protocol

The wire format between the server (the "GPU") and a client. Version 1.

A client asks the server for a **frame sequence** — one or more frames — and
renders them. A single frame is a static display; multiple frames are cycled at
`frame_dwell_ms`. The client re-polls at `refresh_ms`.

### Model

- A **grid** is `cols` × `rows` cells.
- A **cell** is `char + invert`:
  - `char` — an ASCII glyph (0x20–0x7E).
  - `invert` — a boolean; the monochrome stand-in for "highlight" (header row,
    selected item, cursor block).
- A **frame** is a full grid: every cell, every time. No diffs.
- A **sequence** is an ordered list of frames.

### Request

```
GET /frame?viewport=<name>&cols=<w>&rows=<h>
```

| Param      | Meaning                                           |
| ---------- | ------------------------------------------------- |
| `viewport` | Which view logic to run (`load_avg`, `cpu`, …).   |
| `cols`     | Grid width in cells.                              |
| `rows`     | Grid height in cells.                             |

Errors: `400` (bad query / out-of-range dimensions), `405` (non-GET),
`500` (viewport run failure).

### Response

`Content-Type: application/json`.

```json
{
  "version": 1,
  "viewport": "load_avg",
  "cols": 21,
  "rows": 5,
  "refresh_ms": 60000,
  "frame_dwell_ms": 3000,
  "frames": [
    {
      "rows": [
        "load 1m:  0.42      ",
        "load 5m:  0.31      ",
        "load 15m: 0.28      ",
        "                    ",
        "                    "
      ],
      "invert": [
        "111111111111111111111",
        "000000000000000000000",
        "000000000000000000000",
        "000000000000000000000",
        "000000000000000000000"
      ]
    }
  ]
}
```

#### Field reference

| Field             | Type     | Meaning                                                          |
| ----------------- | -------- | ---------------------------------------------------------------- |
| `version`         | int      | Protocol version. Currently `1`.                                 |
| `viewport`        | string   | Echo of the requested viewport.                                  |
| `cols`            | int      | Grid width in cells. Must match the request.                     |
| `rows`            | int      | Grid height in cells. Must match the request.                    |
| `refresh_ms`      | int      | When the client should re-poll, in milliseconds.                 |
| `frame_dwell_ms`  | int      | How long each frame is shown before advancing, in milliseconds. Ignored when there is one frame. |
| `frames`          | array    | Non-empty list of frame objects, in display order.               |
| `frames[].rows`   | string[] | Exactly `rows` strings, each exactly `cols` chars. `rows[i][j]` is the glyph at cell (col `j`, row `i`). |
| `frames[].invert` | string[] | Same shape as `rows`, of `'0'`/`'1'`. `'1'` → cell inverted. May be omitted (treated as all `'0'`). |

### Cell encoding

`rows[i][j]` is the character; `invert[i][j] == '1'` is the invert bit. A cell
is blank when its glyph is a space and it is not inverted.

### Grid → pixel mapping

The grid is a convention the client imposes on its pixel display. With a 6×8
font:

```
cols = floor(pixel_width  / 6)
rows = floor(pixel_height / 8)
```

| Display                 | Pixels | Grid  |
| ----------------------- | ------ | ----- |
| 0.96" SSD1306           | 128×64 | 21×8  |
| 1.5" SSD1327            | 128×128| 21×16 |
| Terminal (`netzf-client`) | —    | any   |

The server is display-agnostic: it renders to the grid it is asked for.

### Validation contract

A client MUST reject a response that violates any of:

- `frames` is empty.
- `frames[].rows` has length ≠ `rows`, or any string length ≠ `cols`.
- `frames[].invert` (if present) has length ≠ `rows`, or any string length ≠ `cols`, or contains a char other than `'0'`/`'1'`.

`invert` omitted → all cells not inverted.

### Versioning

- **Breaking change** (rename/remove a field, change a meaning) → bump `version`.
- **Additive change** (new optional field) → keep `version`, clients ignore
  unknown fields.

## Deploy

See [`deploy/README.md`](deploy/README.md) for the systemd unit and install
steps. The server cross-compiles to a static musl binary for aarch64/x86_64; CI
builds both on every push and attaches them to tagged releases.

## License

MIT — see [`LICENSE`](LICENSE).
