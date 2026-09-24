# netzfenster — server

The "GPU" of netzfenster: computes a grid of cells and serves frame sequences
over HTTP. A dumb client (terminal first, ESP32/OLED later) renders them.

> **Handcoded for learning.** Every line of this server was written by hand,
> deliberately, as a Zig learning project. No framework, no magic — the accept
> loop, the HTTP parsing, the query parsing, the memory management, all of it
> is explicit. See [`../README.md`](../README.md) for the project overview and
> [`../AGENTS.md`](../AGENTS.md) for the working agreement.

## What it does

1. Listens for HTTP requests.
2. Runs a **plugin** (a shell command) to fetch data.
3. Writes the plugin's output into a grid of cells.
4. Serializes the grid as a frame sequence and responds.

## Build & run

```sh
zig build run
```

Requires Zig 0.16.0.

## Configuration

Environment variables:

| Var                 | Default            | Meaning                              |
| ------------------- | ------------------ | ------------------------------------ |
| `NETZF_HOME`        | `/opt/netzf`       | Data dir: viewport JSONs + scripts.  |
| `NETZF_LISTEN_ADDR` | `127.0.0.1:8989`   | Address to listen on.                |

## The endpoint

```
GET /frame?viewport=<name>&rows=<h>&cols=<w>
```

Returns a JSON frame sequence. See the protocol section of the
[`../README.md`](../README.md#protocol) for the full wire format.

Errors: `400` (bad query / out-of-range dimensions), `405` (non-GET),
`500` (viewport run failure).

## Plugins

A plugin is any shell command. It prints plain-text lines to stdout — one line
per row. The server writes those lines into the grid, wrapping long lines with
a 2-space indent and paginating into multiple frames when the output exceeds
`rows`.

Viewports are configured as JSON files in `$NETZF_HOME`:

```json
{
  "cmd": "scripts/load_avg.sh",
  "refresh_ms": 60000
}
```

`cmd` is run via `sh -c` with `$NETZF_HOME` as the working directory. Example
plugins live in [`../examples/`](../examples/).

## Layout

```
src/
├── main.zig    ← HTTP server: accept loop, handler, query parsing, guards
├── root.zig    ← serializeViewPort glue + re-exports
├── grid.zig    ← Cell + Grid (writeText wrapping/pagination)
├── frame.zig   ← FrameSequence (the wire object)
└── view.zig    ← ViewPort (config + plugin runner)
```

## Tests

```sh
zig build test
```
