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

## Open questions / decisions

- [ ] Protocol: JSON full-frame vs binary diff (start JSON, graduate to diff)
- [ ] Transport: HTTP polling vs WebSocket (start HTTP polling)
- [ ] Font: Adafruit `glcdfont` vs custom (custom = terminal aesthetic)
- [ ] Server language: Zig (reuse zell) vs Go vs Python
- [ ] Repo structure: `protocol/` + `server/` + `firmware/`
- [ ] Which view first: ADS-B plane counter (dump1090 already working)

## The "aha"

This is a real tiny system — client, server, protocol, three layers — each small
enough to hold in your head. It reuses zell conceptually. It's infinitely
extensible. A dumb terminal you built yourself, rendering whatever your servers
tell it, over WiFi, in a 21-character-wide monospace grid.
