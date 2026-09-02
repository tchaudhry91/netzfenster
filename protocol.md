# Netzfenster Protocol

The wire format between the server (the "GPU") and a client (terminal first,
ESP32 later). Version 1.

## Overview

A client asks the server for a **frame** — the current state of a grid of
cells — and renders it. The client polls at the server-specified `refresh_ms`
interval. The server re-renders only when its data changes.

The unit of rendering is the **cell**, not the pixel. The server never thinks in
pixels; it lays out a grid of cells. The client rasterizes cells to pixels.

## The model

- A **grid** is `cols` × `rows` cells.
- A **cell** is `char + invert`:
  - `char` — an ASCII glyph (0x20–0x7E).
  - `invert` — a boolean; the monochrome stand-in for "highlight" (header row,
    selected item, cursor block).
- A **frame** is a full grid: every cell, every time. No diffs.

## Request

```
GET /frame?viewport=<name>&cols=<w>&rows=<h>
```

| Param      | Meaning                                              |
| ---------- | ---------------------------------------------------- |
| `viewport` | Which view logic to run (`planes`, `cluster`, …).    |
| `cols`     | Grid width in cells.                                 |
| `rows`     | Grid height in cells.                                |

The client derives `cols`/`rows` from its own pixel size and font (see
[Grid → pixel mapping](#grid--pixel-mapping)). The server renders to whatever
grid it is handed.

## Response

`Content-Type: application/json`.

### Schema

```json
{
  "version": 1,
  "viewport": "planes",
  "cols": 21,
  "rows": 8,
  "refresh_ms": 30000,
  "grid": {
    "rows": ["…", "…"],
    "invert": ["…", "…"]
  }
}
```

### Example

```json
{
  "version": 1,
  "viewport": "planes",
  "cols": 21,
  "rows": 8,
  "refresh_ms": 30000,
  "grid": {
    "rows": [
      "ADS-B  3 PLANES      ",
      "                    ",
      "  ██  ██  ██        ",
      "                    ",
      "                    ",
      "                    ",
      "                    ",
      "                    "
    ],
    "invert": [
      "111111111111111111111",
      "000000000000000000000",
      "000000000000000000000",
      "000000000000000000000",
      "000000000000000000000",
      "000000000000000000000",
      "000000000000000000000",
      "000000000000000000000"
    ]
  }
}
```

### Field reference

| Field           | Type     | Meaning                                                          |
| --------------- | -------- | ---------------------------------------------------------------- |
| `version`       | int      | Protocol version. Currently `1`.                                 |
| `viewport`      | string   | Echo of the requested viewport.                                  |
| `cols`          | int      | Grid width in cells. Must match the request.                      |
| `rows`          | int      | Grid height in cells. Must match the request.                     |
| `refresh_ms`    | int      | When the client should re-poll, in milliseconds.                  |
| `grid`          | object   | The frame content: a full grid of cells.                        |
| `grid.rows`     | string[] | Exactly `rows` strings, each exactly `cols` chars. `rows[i][j]` is the glyph at cell (col `j`, row `i`). |
| `grid.invert`   | string[] | Same shape as `rows`, of `'0'`/`'1'`. `'1'` → cell inverted. May be omitted (treated as all `'0'`). |

## Cell encoding

`rows[i][j]` is the character; `invert[i][j] == '1'` is the invert bit. A cell
is blank when its glyph is a space and it is not inverted.

## Grid → pixel mapping

The grid is a convention the client imposes on its pixel display. With a 6×8
font:

```
cols = floor(pixel_width  / 6)
rows = floor(pixel_height / 8)
```

| Display            | Pixels   | Grid   |
| ------------------ | -------- | ------ |
| 0.96" SSD1306      | 128×64   | 21×8   |
| 1.5" SSD1327       | 128×128  | 21×16  |
| Terminal (zell)    | —        | any    |

The server is display-agnostic: it renders to the grid it is asked for.

## Validation contract

A client MUST reject a response that violates any of:

- `grid.rows` has length ≠ `rows`, or any string length ≠ `cols`.
- `grid.invert` (if present) has length ≠ `rows`, or any string length ≠ `cols`, or contains a char other than `'0'`/`'1'`.

`invert` omitted → all cells not inverted.

## Versioning

- **Breaking change** (rename/remove a field, change a meaning) → bump `version`.
- **Additive change** (new optional field) → keep `version`, clients ignore
  unknown fields.
