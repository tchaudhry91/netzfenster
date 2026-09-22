# netzfenster — case design log

> Working notes for the enclosure. The builder designs it in Onshape; this file
> records measurements, decisions, and print results so the loop survives between
> sessions. Not a spec.

**Designer:** tchaudhry (all CAD, by hand)
**CAD tool:** Onshape (free plan)
**Printer:** Bambu Lab A1 Mini, eSUN PLA+ Black, 0.4 mm nozzle
**Status:** measuring the soldered assembly

---

## The parts being enclosed

| Part | Notes |
| --- | --- |
| ESP32-S3 DevKit N16R8 | dual-core LX7 @ 240 MHz, 16 MB flash, 8 MB PSRAM, USB-C |
| SSD1306 OLED 0.96" | 128×64 monochrome, **7-pin SPI module** (not I2C) |

### Soldered harness (OLED ↔ ESP32), 3-wire SPI — no CS

| OLED pin | ESP32-S3 |
| --- | --- |
| SCLK / D0 | GPIO 11 |
| MOSI / D1 | GPIO 12 |
| DC | GPIO 9 |
| RES | GPIO 8 |
| VCC | 3V3 |
| GND | GND |

6 wires total, 28 AWG silicone.

---

## Measurements

All taken with the digital caliper (150 mm, 0.01 mm) **on the soldered assembly**,
not from datasheets.

**Method: max dimensions (max sprawl).** Every figure below is the outermost
bounding-box extent of that axis — including pin-header tails, antenna overhang,
solder blobs. This is deliberately the conservative number: if the case clears
the sprawl, it clears the part. Do **not** mix these with PCB-edge figures later.

### ESP32-S3 DevKit

| Dimension | Value | Date | Notes |
| --- | --- | --- | --- |
| Length | **63.17 mm** | 2026-09-22 | which axis is still open (see questions) |
| Width | **31.92 mm** | 2026-09-22 | max sprawl |
| Height | **31.09 mm** | 2026-09-22 | max sprawl, **includes the OLED** |

_Still to measure:_ PCB thickness, header (pin) height above PCB, tallest
component (RF shield can) height, USB-C port position from nearest edges + port
height above PCB, button positions.

### SSD1306 0.96" OLED module

_Still to measure:_ PCB outer L×W, PCB thickness, active-area L×W, mounting hole
diameter + hole spacing (X and Y), position of active area relative to PCB edges,
height of the pin-header/solder side.

---

## Physical arrangement (builder's plan)

- **Two printed pieces**, joined by **friction-fit pillars** — no screws. Mass is
  low (board + tiny OLED), so a press/slip fit is enough. To be validated by test
  prints.
- **OLED is perpendicular to the ESP32.** In plan (top) view the ESP32 reads as
  the full rectangular **base**, and the OLED collapses to a **line** (its edge =
  material thickness). In right-side view it inverts: the **full OLED face** is
  visible and the ESP32 is a line.

```
   TOP VIEW                          RIGHT SIDE VIEW
   ┌───────────────────────────┐     ┌───────┐
   │  ESP32 (full outline)     │     │       │
   │                           │     │ OLED  │
   │───────────────────────────│ ←   │ full  │  ← ESP32 = line
   │  ^ OLED edge-on = a line  │     │ face  │
   └───────────────────────────┘     └───────┘
```

_Reading confirmed by the builder? The "line" in top view is what pins this down
as edge-on/perpendicular, not a flat stack._

> Design implication to watch: the OLED being vertical means the **print
> orientation** and the **friction pillars** have to cope with a tall, thin,
> lever-y part. Also: what holds the OLED itself — does it slot into a groove in
> the two-piece shell?

---

## Open decisions

- [x] **Arrangement** — two pieces, OLED perpendicular to the ESP32 (edge-on in top
      view). Friction-fit pillars instead of screws.
- [ ] **How the OLED is held** — screw posts behind a window vs a pocket it drops into from behind. *(now: does it slot into a groove?)*
- [ ] **USB-C face** — which side, and clearance for the cable overmold (not just the connector).
- [ ] **Buttons** — expose BOOT/RST or keep internal.
- [ ] **Wire routing / strain relief** — trap the harness so it can't tug the solder joints.
- [ ] **Battery provisioning** — v2 (LiPo + TP4056 + MT3608 + switch) is unbuilt; leave room or ignore for now?

## Standing fit parameters (to carry into Onshape Variables)

| Name | Value | Source |
| --- | --- | --- |
| `clearance` | 0.25 mm | general mating clearance (0.2–0.3 band) |
| `friction` | **TBD** | friction/slip-fit interference — **not the same number as `clearance`**. Needs its own test print (pillar diameter vs hole). 
| `pilot` | 2.8 mm | ST2.9 self-tap bite, **through** 3 mm plate — blind-post number still untested |
| `clearance_hole` | 3.0 mm+ | ST2.9 passes freely |
| screw | ST2.9 × 13 mm SS304 self-tapping | dictates post depth (13 mm total) |

_Caveat carried forward from the tolerance test: the 2.8 mm figure is proven in a
**through-hole**, not a blind post. Blind posts trap displaced plastic and split
more easily — expect to go slightly larger. A blind screw-post test is still
queued._

---

## Design log

### 2026-09-22 — started

- Created this file.
- Measured ESP32 **max sprawl**: length **63.17 mm**, width **31.92 mm**,
  height **31.09 mm** (height includes the OLED).
- Adopted "max dimensions (bounding box)" as the measurement convention for all
  component figures.
- Settled the arrangement: two pieces, OLED perpendicular to the ESP32, joined by
  friction-fit pillars (no screws).

---

## Questions for the builder

1. The 63.17 mm length — which axis is it? Along the USB-C direction, or across?
   And is it the PCB edge or including the pin headers/antenna overhang?
2. Which exact devkit variant? (DevKitC-1 vs a clone changes the antenna and
   button layout.)
