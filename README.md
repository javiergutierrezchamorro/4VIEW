# 4View 1.00

**Turbo Vision style text file viewer for DOS**

Copyright (c) 2025 Javier Gutiérrez Chamorro (Guti)

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

## Building with ASMC

```
ASMC 4VIEW.ASM
```

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
| Quit                | ESC                      |

## Author

Javier Gutiérrez Chamorro (Guti)

## License

Free to use, modify and distribute. Attribution appreciated.

## Version

**1.00** – Initial release with mouse wheel, line cache, exact counters and Turbo Vision UI.
