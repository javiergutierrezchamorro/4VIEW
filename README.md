# 4VIEW and 4VIEW386

**The fast, tiny, Turbo Vision style text viewer for DOS. Open a file of any size. Instantly.**

Copyright (c) 2025-2026 Javier Gutiérrez Chamorro (Guti)

<img width="720" height="400" alt="image" src="https://github.com/user-attachments/assets/f7a8cf25-4ab6-48ee-9038-3d60d318400d" />

---

## What is 4VIEW?

4VIEW is a file viewer for DOS. You give it a file, or pipe something into it, and you get a clean, classic blue-and-cyan Turbo Vision screen where you can scroll, search, jump, inspect and read, with the keyboard or the mouse wheel. It never edits anything and never needs a temp file.

It is written entirely in hand-tuned assembly language and ships as a single `.COM` file in two flavours:

- **4VIEW**: for any 8088/8086 or better.
- **4VIEW386**: the same program with 32-bit string operations and immediate shifts, for 80386 and better.

Think of it as the spiritual successor of the legendary LIST.COM by Vernon D. Buerg: the same "just show me the file" philosophy, a modern feel, open source, and a fraction of the size.

## Why you will like it

- **Instant start, whatever the file size.** 4VIEW reads only what the screen needs. There is no pre-scan, no "loading" wait: the first page is on screen immediately, even for a multi-hundred-megabyte log.
- **Files up to 4 GiB.** Streaming and seeking through a fixed 32 KiB buffer. The file is never loaded into RAM, so a 10 KB file and a 3 GB file cost exactly the same memory.
- **Jump to the end without waiting.** `End` seeks straight to the tail of the file instead of reading everything from the top.
- **Works with pipes.** `TYPE file.txt | 4VIEW`, `DIR /S | 4VIEW`, the output of any command: you can even scroll back up through the stream.
- **Real search, LIST style.** Case-insensitive *Find*, case-sensitive *Scan*, forward and backward, repeat with a single key. Search time depends on the distance to the match, not on the file size.
- **Go to line N**, bookmark a spot and come back to it later.
- **Hex view built in.** Switch any file to a hex dump with an ASCII gutter. Files that look binary open directly in hex.
- **Word wrap** toggle for long lines, and **horizontal scrolling** when you prefer to keep them intact.
- **Info popup** with file name, size, date, line count and position.
- **Print** the file to `PRN`.
- **Mouse and wheel support** (INT 33h): click the scrollbar to jump, wheel or middle button to scroll.
- **Leaves no trace.** The original screen, cursor, video mode and keyboard typematic rate are restored when you exit.
- **Long file names** on volumes with DOS LFN support, with full-path title bar.
- **Open source and free.** Assemble it yourself with ASMC.

## Features at a glance

- Classic Turbo Vision look: blue content area with white text, cyan header and status bars with black text, vertical scrollbar, green pop-up windows
- Exact line counting, discovered on demand, with a live position bar while the file is being read
- Recent-line offset cache and view cache: scrolling up and down, and horizontal repaints, do almost no file I/O
- Unrolled, SWAR-style line scanners for speed on both 8086 and 386 builds
- Handles CR, LF and CRLF line endings
- Keyboard: arrows, PgUp/PgDn, Home/End, search, go to, hex, wrap, info, print
- Mouse: scrollbar click and wheel

## Keys & Mouse

| Action                         | Control                                    |
|--------------------------------|--------------------------------------------|
| Line up / down                 | ↑ / ↓  or mouse wheel                      |
| Page up / down                 | PgUp / PgDn                                |
| Start / End of file            | Home / End                                 |
| Jump                           | Click on scrollbar                         |
| Horizontal scroll              | ← / →  (Ctrl = 10 columns)                 |
| Find (case-insensitive)        | F                                          |
| Scan (case-sensitive)          | S                                          |
| Repeat search                  | A or F3                                    |
| Find / Scan backwards          | `` ` `` or `^` / `'` or `V`                |
| Go to line                     | G                                          |
| Hex view                       | Alt+H                                      |
| Toggle word wrap               | W                                          |
| File info                      | I                                          |
| Print                          | Ctrl+P                                     |
| Set bookmark / go to bookmark  | Ctrl+Y / Alt+Y                             |
| Help / About                   | F1 / F10                                   |
| Quit                           | ESC                                        |

## Usage

```
4VIEW [filename]
TYPE filename.txt | 4VIEW
4VIEW -h
```

File names containing spaces must be enclosed in double quotes: `4VIEW "my file.txt"`.

## Limits

4VIEW is designed so that the file size never matters. These are the real boundaries of the current version (3.13):

| Item                         | Limit                                                                                         |
|------------------------------|-----------------------------------------------------------------------------------------------|
| **File size**                | Up to **4 GiB − 1 byte** (4,294,967,295 bytes): 32-bit file offsets, the same ceiling as DOS itself |
| **Number of lines**          | **32-bit** line counters, up to 4,294,967,295 lines (in practice bounded by the file size). "Go to line" accepts up to 10 digits |
| **Memory used**              | **Constant**: a fixed ~52 KB of work buffers (32 KiB of it is the file read buffer), independent of the file size. No EMS, XMS or temp files |
| **Visible line length**      | **254 characters** kept per line, viewed through a 77-column window with horizontal scrolling. Longer lines still count as one line; the characters beyond 254 are not displayed |
| **Word wrap**                | Lines are split into rows of 77 characters                                                    |
| **Screen**                   | 80×25 text mode: 23 content rows, 77 columns                                                  |
| **Line endings**             | CR, LF and CRLF. VT and FF are shown as data                                                  |
| **Search pattern**           | Up to 31 characters                                                                           |
| **Bookmarks**                | One (Ctrl+Y sets it, Alt+Y returns to it)                                                     |
| **File name / path**         | Up to 64 characters (longer expanded paths are kept as typed). Long file names need LFN support in DOS |
| **Piped input (STDIN)**      | Unlimited stream length. Scrolling back is available for the most recent ~23 lines            |
| **Hex view**                 | 16 bytes per row, for real files only (it needs a seekable file, so it is not available on piped input). Files whose first 512 bytes are at least 5% control or non-ASCII characters open directly in hex |
| **Command line**             | One file name. The only option is `-h` (or `/?`) for help                                     |

## Requirements

### Hardware

| Component    | 4VIEW                       | 4VIEW386                         |
|--------------|-----------------------------|----------------------------------|
| **CPU**      | 8088 / 8086 or better       | **80386 or better**              |
| **RAM**      | One free 64 KB COM segment (about 52 KB are used for work buffers) | Same |
| **Video**    | MDA / Hercules (mode 7), or CGA / EGA / VGA 80×25 color text (modes 2 and 3) | Same |
| **Keyboard** | Any BIOS-compatible keyboard | Same                            |
| **Mouse**    | Optional (INT 33h driver). A wheel-aware driver such as CuteMouse is recommended for the wheel | Same |
| **Disk**     | None required. 4VIEW writes nothing to disk | Same                |

The 386 build checks the CPU at start-up and exits with a clear message on older machines instead of crashing.

If the screen is in any other mode (40 columns or graphics), 4VIEW switches to 80×25 text for the session and restores your original mode on exit.

### Software

- **DOS 2.0 or later**, FreeDOS, MS-DOS, PC DOS, DR-DOS, or a DOSBox / emulator session. Windows 9x DOS boxes also work.
- DOS 3.0 or later shows the full path of the file in the title bar (older versions simply keep the name as typed).
- Optional: DOS long file name support (INT 21h 71xx, as provided by Windows 9x or LFN drivers such as DOSLFN) for names beyond 8.3.
- Optional: a mouse driver (CuteMouse recommended for wheel support).

### To build from source (not needed to run)

- [ASMC](https://github.com/nidud/asmc) (the build is tested with ASMC 2.4x)
- [SMART.INC](https://github.com/javiergutierrezchamorro/SMART.INC) macros (version 4.03 or later recommended), placed next to `4VIEW.ASM` or on the include path

## Building with ASMC

```
ASMC -bin -Fo 4VIEW.COM 4VIEW.ASM
```

For 386+ machines there is a dedicated build with 32-bit string ops, native shifts and 32-bit arithmetic (the title and About box then say **4VIEW386**):

```
ASMC -3 -bin -Fo 4VIEW386.COM 4VIEW.ASM
```

`SMART.INC` from [its repository](https://github.com/javiergutierrezchamorro/SMART.INC) must be next to `4VIEW.ASM` or on the include path.

(The supplied `4VIEW.COM` is a pre-built binary with identical functionality.)

## Author

Javier Gutiérrez Chamorro (Guti)

## License

Free to use, modify and distribute. Attribution appreciated.

## Version history

**3.13** – Source cleanup and micro-optimizations on the stable 3.12 base; 32-bit multiply/divide for the progress gauge on 386 builds. No behavioral change.

**3.09 – 3.12** – Fixes for the 386 scrollbar/percentage, `End` and `Goto` positioning, search prompt handling and a scroll-up hang; search made proportional to the distance to the match; faster `End` line counting.

**3.00 – 3.04** – On-demand reader: no pre-scan of the file, the first screen appears instantly, files of any size, long file name support, flat block scan for `End`.

**2.x** – Hex view, word wrap, info popup, print, bookmarks, search, go to line; 32-bit line numbers (the 65,535-line limit is gone).

**1.10** – Performance and polish revision: buffered file engine with soft seeks, view cache and line-start ring (scrolling and horizontal repaints do near-zero file I/O), unrolled line scanners, length-byte slots (h-scroll without re-walks), 4VIEW386 build name, blinking load indicator. Assembles with ASMC and uses SMART.INC.

**1.00** – Initial release with mouse wheel, line cache, exact counters and Turbo Vision UI.
