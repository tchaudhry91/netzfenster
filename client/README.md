# netzfenster — terminal client

A terminal client for netzfenster: polls the server, renders the frame to the
terminal with ANSI escape codes.

> **LLM-generated, for testing only.** This client was written by an AI agent
> to exercise the server's request/response loop before any real hardware
> exists. It is *not* the target client — the ESP32/OLED firmware is. Treat it
> as a throwaway debugging tool, not a reference implementation.

## What it does

1. Polls `GET /frame?viewport=...` on an interval.
2. Parses the JSON frame sequence.
3. Renders it to the terminal (clear screen + reverse-video for inverted cells).
4. Cycles multiple frames at `frame_dwell_ms`.

## Build & run

```sh
zig build run -- <viewport> [server_addr] [rows] [cols]
```

| Arg           | Default            | Meaning                |
| ------------- | ------------------ | ---------------------- |
| `viewport`    | — (required)       | Which viewport to poll.|
| `server_addr` | `127.0.0.1:8989`   | The server to poll.    |
| `rows`        | `8`                | Grid height.           |
| `cols`        | `21`               | Grid width.            |

Example:

```sh
zig build run -- clock 127.0.0.1:8989 8 21
```

## Why it exists

The real client is ESP32 firmware (C + OLED). This terminal client exists so the
server and protocol can be developed and debugged on a laptop, without hardware.
Once the ESP32 client exists, this one can be retired.
