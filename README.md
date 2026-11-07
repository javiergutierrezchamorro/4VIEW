# 4View 1.10

**Turbo Vision style text file viewer for DOS**

Copyright (c) 2025 Javier Gutiérrez Chamorro (Guti)

<img width="720" height="400" alt="image" src="https://github.com/user-attachments/assets/d8fa4162-b0cb-49f8-9d23-08b6b9995a40" />


---

## Description

Lightweight text viewer written in 16-bit assembly. Displays text files of **any size** (does not load the whole file into RAM).

Classic Turbo Vision look:
- Blue content area, white text
- Cyan header & status bars (black text)
- Vertical scrollbar
- Mouse + wheel support

## Features

- Arbitrary file size support (streaming + seeking)
- Exact line count (initial pass)
- Recent-line offset cache → real scroll-up works with pipes
- Mouse support (INT 33h)
  - Left click on scrollbar → jump
  - Mouse wheel / middle button → scroll
- Keyboard: ↑ ↓  PgUp PgDn  Home End  ESC
- Works with pipes: `TYPE file.txt | 4VIEW`

## Requirements

- DOS 2.0+ / FreeDOS / DOSBox
- 80×25 text mode
- Optional mouse driver (CuteMouse recommended for wheel)
- [SMART.INC](https://github.com/javiergutierrezchamorro/SMART.INC) macros (only to assemble, not to run)

## Building with ASMC

```
ASMC -bin -Fo 4VIEW.COM 4VIEW.ASM
```

For 386+ machines there is a dedicated build with 32-bit string ops and
immediate shifts (the title and About box then say **4VIEW386**):

```
ASMC -3 -bin -Fo 4VIEW386.COM 4VIEW.ASM
```

`SMART.INC` from [its repository](https://github.com/javiergutierrezchamorro/SMART.INC) must be next to `4VIEW.ASM` or on the include path.

(The supplied `4VIEW.COM` is a pre-built binary with identical functionality.)

## Usage

```
4VIEW [filename]
TYPE filename.txt | 4VIEW
4VIEW -h
```

## Keys & Mouse

| Action              | Control                  |
|---------------------|--------------------------|
| Line up / down      | ↑ / ↓  or mouse wheel    |
| Page up / down      | PgUp / PgDn              |
| Start / End         | Home / End               |
| Jump                | Click on scrollbar       |
| Horizontal scroll   | ← / →  (Ctrl = 10 cols)  |
| Help / About        | F1 / F10                 |
| Quit                | ESC                      |

## Author

Javier Gutiérrez Chamorro (Guti)

## License

Free to use, modify and distribute. Attribution appreciated.

## Version

**1.00** – Initial release with mouse wheel, line cache, exact counters and Turbo Vision UI.

**1.10** – Performance and polish revision: buffered file engine with soft seeks, view cache and line-start ring (scrolling and horizontal repaints do near-zero file I/O), unrolled line scanners, length-byte slots (h-scroll without re-walks), 4VIEW386 build name, blinking load indicator. Assembles with ASMC and uses SMART.INC.