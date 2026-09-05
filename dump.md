# netzfenster — project dump

> Working notes. This is a brain dump of the design discussion, not a spec.
> Continue the conversation here.

## What this is

A **network framebuffer**. A tiny ESP32 + OLED that renders whatever a remote
server tells it. The ESP32 is a dumb renderer — a "monitor with a WiFi antenna."
All the intelligence lives on a more powerful machine (Pi / server) that computes
a grid of cells and serves it over the network.

**Netzfenster** = German for "network window" (*Netz* = network, *Fenster* = window).
The network is the soul of the project, not the pixels.

## The three layers

```
┌─────────────────────┐      ┌──────────────────┐      ┌─────────────┐
│  Pi / server         │      │  ESP32-S3        │      │  OLED       │
│  (the "GPU")         │ WiFi │  (the renderer)  │ SPI  │  (the screen)│
│                      │ ───► │                  │ ───► │             │
│  computes the cell   │      │  holds framebuffer│     │  dumb pixels│
│  grid, serves it     │      │  renders + pushes│      │             │
└─────────────────────┘      └──────────────────┘      └─────────────┘
```

- **Server** = the "GPU". Computes the cell grid, serves it over HTTP/WebSocket.
- **ESP32** = the renderer. Fetches the grid, renders to a framebuffer, pushes to OLED.
- **OLED** = dumb pixels.

## The zell mapping

[zell](https://github.com/tchaudhry/zell) is the existing Zig terminal
cell-rendering library: a `Grid` of `Cell`s, double-buffered, with a `flush()`
that diffs the back buffer against the front and emits minimal output to a
`writer`.

The insight: **zell's `writer` is the seam.** Swap "ANSI terminal writer" for
"network socket writer" and zell becomes a framebuffer server.

The `Cell` type collapses for monochrome OLED (no 256-color fg/bg):

```zig
pub const Cell = packed struct {
    char: u8,        // ASCII (u21 later if unicode)
    invert: bool,    // "highlight" — the monochrome stand-in for color
};
```

21 cols × 8 rows = **168 cells**. A full frame is ~340 bytes. Trivial.

## The protocol

Two options:

- **Full frame** — send the whole grid every time. ~340 bytes. Fine for v0.
- **Diff-based (the zell way)** — send only *changed* cells, exactly like
  `flush()`. Server keeps a front/back buffer, diffs, emits `(x, y, char, invert)`
  tuples. The ESP32 applies them and redraws.

Plan: full-frame JSON first (debuggable), then graduate to a binary diff protocol.

## The ESP32 side (~200-400 lines of C)

1. Connect WiFi (the S3 has WiFi 4 built in — that's the whole point of the chip)
2. Loop: HTTP GET the endpoint → parse the cell grid → render → push to OLED
3. Render: a 6×8 bitmap font, blit each glyph into a 128×64 framebuffer (1 KB),
   push to the SSD1306 over I2C/SPI

No FreeRTOS complexity, no sensor drivers, no state machines. A fetch-and-draw loop.

## The server side (where the flavour lives)

A small program (Zig / Go / Python) that:

1. Maintains a grid (reuse zell's `Grid`/`Cell` types — or port them)
2. Runs **views** — each view is a function that draws to the grid
3. Serves the grid over HTTP/WebSocket

**Every future idea is just a new view function. The ESP32 never changes.**

## The plan

- **v0** — ESP32 renders a *hardcoded* grid (no WiFi). Confirms font + framebuffer + OLED.
- **v1** — server serves full-frame JSON over HTTP; ESP32 polls ~250ms and renders.
- **v2** — binary diff protocol (the zell-like satisfaction).
- **v3** — views: ADS-B plane counter, cluster status, terminal, chip vitals, etc.

## Hardware

- ESP32-S3 DevKit N16R8 ×3 (16MB flash, 8MB PSRAM, dual-core LX7 @ 240 MHz)
- 0.96" OLED (128×64, SSD1306, monochrome) ×4
- Waveshare 1.5" OLED (128×128) ×1
- BME280, PMS7003 sensors (use only if needed)
- Breadboard + jumper wires

## Language decision

- **C directly** for the first blink + first sensor read (zero friction, all docs are C)
- **Zig via esp-zig + `@cImport`** as the "flavour" upgrade once the toolchain works
- **Rust (esp-hal)** as the "if I really have to" fallback

## Emulator ecosystem

- **Wokwi** (wokwi.com) — runs *real* compiled firmware (Xtensa emulator), virtual
  sensors/OLEDs, `diagram.json` wiring. The "test without wiring" answer.
- **QEMU (espressif fork)** — boots firmware, but no WiFi/BT, patchy peripherals. CI-oriented.
- **Host tests (`linux` target)** — run pure logic on the host machine.

## Server decisions (2026-08-31)

- **Language: Zig** (confirmed). The grid library is a zell port; one language end-to-end.
- **Plugin system**: data fetching is shelled out to tiny programs (plugins). The
  server runs a plugin, captures stdout, parses it. The server doesn't do the
  fetching itself — it's a renderer + scheduler.
- **Multiple viewports**: the endpoint takes a viewport param (e.g.
  `/frame?viewport=planes`). Each viewport is a separate grid + view logic.
- **Tiny video model** (superseded — see session 2 below): the server pre-renders a *sequence* of frames (a seamless
  animation loop, like a GIF) and sends them all in one response. The client
  loops the frames locally at a fixed rate. Refresh interval is large (~1 minute).
  Movement is pre-rendered server-side and played back client-side — smooth
  animation without frequent polling. The diff/delta protocol is dead (full-frame
  sequences are small enough). The frame rate is server-specified (frame duration
  in the response).
- **Terminal client (debugging flow)**: a small Zig program that polls the server
  and renders the frame to the terminal using zell. It's the *reference client* —
  the ESP32 firmware is a port of it to C + OLED. Develop and debug entirely in
  the terminal.

## Server decisions (session 2 — 2026-08-31)

- **Single-frame model** (supersedes the tiny video model): the server serves
  one frame per response; the client polls at `refresh_ms`. No `fps`, no loop,
  no pre-rendered sequences. Static views only for now. A 21×8 frame is ~340
  bytes, so even a 1s poll is trivial on WiFi.
- **Plugin contract (Path A)**: a plugin is a script that prints plain-text
  lines to stdout — one line per row. The server writes the lines to a grid and
  wraps it in a `Frame`. No JSON, no delimiter, no animation. The plugin *is*
  the view; edit the script, no recompile.
- **Cycling**: server-side, via a time-dependent `cycle` viewport. The server
  holds a list of sub-views + a dwell time; on each poll it computes
  `index = (now / dwell) % len(cycle)` and renders that sub-view. The client
  polls one viewport and stays dumb. The schedule lives on the server.
- **Naming**: `Cell` → `Grid` → `Frame` (the wire object: metadata + one grid).

## Server decisions (session 3 — 2026-09-03)

- **File structure**: `server/src/` split into `grid.zig` (Cell + Grid),
  `frame.zig` (FrameSequence), `view.zig` (ViewPort). `root.zig` re-exports.
  The plugin runner merged into `ViewPort.run`.
- **ViewPort config**: each viewport is a JSON file
  (`examples/viewports/<name>.json`) with `cmd` (a shell command string) and
  `refresh_ms`. `ViewPort.init` reads + parses it; `ViewPort.run` shells out
  via `sh -c <cmd>` with `cwd` = the viewports' base dir.
- **Memory: request-scoped arena.** Each request spins up an `ArenaAllocator`;
  everything (config, stdout, grid, frames, JSON) allocates from it and dies
  with the request. No per-type `deinit` methods. `parseFromSliceLeaky` is the
  parse entry point (allocates directly from the arena).
- **Plugin contract (refined)**: a plugin is any command string run via
  `sh -c`. It prints plain-text lines to stdout (one per row). The server
  writes them to a grid via `writeText` (wraps long lines with a 2-space
  indent, returns a resume index for pagination).

## Server decisions (session 4 — 2026-09-05)

- **HTTP server**: `std.http.Server` (single-connection handler) + a manual
  accept loop over `std.Io.net`. `listen` once, then `accept → handle → close`
  forever. One request per connection for now (no keep-alive reuse).
- **Handler**: `GET /frame?viewport=<name>&rows=<n>&cols=<n>` → parse query →
  `serializeViewPort` → JSON response. Errors: 400 (bad query/dimensions),
  405 (non-GET, `keep_alive = false`), 500 (viewport run failure).
- **Dimension guards**: `rows` 1..=255, `cols` 3..=255 (the 2-space wrap indent
  means `cols < 3` breaks wrapping). Validated in `parseFrameRequest` before
  `@intCast` to `u8`.
- **Config via env vars**: `NETZF_HOME` (data dir, default `/opt/netzf`) and
  `NETZF_LISTEN_ADDR` (default `127.0.0.1:8989`). Viewport JSONs live directly
  in the data dir (`<name>.json`), scripts in `<data_dir>/scripts/`.
- **Logging**: `std.log` with scoped loggers (`.server`, `.http`). Startup +
  per-request logs (method, target, status).

## Open questions / decisions

- [x] Transport: HTTP polling (done — `GET /frame`)
- [ ] Font: Adafruit `glcdfont` vs custom (custom = terminal aesthetic)
- [ ] Which view first: ADS-B plane counter (dump1090 already working)
- [x] Pagination: `writeText` resume index splits long output into frames
- [ ] Cycle viewport: list of sub-views + dwell time (deferred)
- [ ] Terminal client (reference client, zell-based)

## The "aha"

This is a real tiny system — client, server, protocol, three layers — each small
enough to hold in your head. It reuses zell conceptually. It's infinitely
extensible. A dumb terminal you built yourself, rendering whatever your servers
tell it, over WiFi, in a 21-character-wide monospace grid.
