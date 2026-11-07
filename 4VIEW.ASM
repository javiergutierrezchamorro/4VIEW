;------------------------------------------------------------------------------
; 4VIEW 1.10 - Turbo Vision style text viewer for DOS (ASMC)
; (c) 2025-2026 Javier Gutierrez Chamorro (Guti)
; Reviewed & optimized revision 1.10 (slot length bytes: the hPos
; walk is gone, h-scroll hit paints pure; count scanner unrolled to
; 8 bytes; 4VIEW386 build name; on top of the 1.09 view cache +
; line-start ring work)
;
; Assemble with ASMC (flat COM, single segment):
;     ASMC -bin -Fo 4VIEW.COM 4VIEW.ASM          (8088/8086, default)
; 386+ build (immediate shifts + 32-bit string ops; the title bar and
; About say "4VIEW386", fix 68):
;     ASMC -3 -bin -Fo 4VIEW386.COM 4VIEW.ASM
; (with JWasm the equivalents are: JWASM -bin -Fo=4VIEW.COM 4VIEW.ASM and
;  JWASM -3 -bin -Fo=4VIEW386.COM 4VIEW.ASM; SMART.INC must be next to
;  4VIEW.ASM or on the include path)
; The classic two-step flow also works (single segment, no .data):
;     ASMC -c 4VIEW.ASM  +  LINK16 /TINY 4VIEW.OBJ,4VIEW.COM;
;
; Revision 1.01 fixes:
;  1. Single-segment image: data declared in .code. With a separate .data
;     segment, ASMC/JWasm "-bin" emits wrong offsets (black screen, wild
;     execution) and plain "ASMC file.asm" needs an external link step.
;  2. Pure 8086 instruction set: no .386 forms (mov dword ptr reg/imm,
;     shl/shr reg,imm>1) that fail to assemble by default.
;  3. RdLine wrote text with STOSB while callers (DrwCnt) had ES=B800h:
;     line text landed on the video page instead of lBuf -> empty content
;     area + garbage in mid-screen. RdLine now stores via mov [di],al.
;  4. DrwSt built stBuf after setting ES=B800h: Cpy/U2A wrote the status
;     text into video memory -> blank status bar. It now builds the
;     buffer with ES=DS first, then paints.
;  5. No parameters used to "view" the console (blocking on keyboard):
;     stdin is now checked with IOCTL; only a pipe/redirection views.
;     Otherwise the help screen is shown.
;  6. Buffered input engine (4 KiB): 1-byte INT 21h reads made big files
;     take minutes (a 385 KB file needed 385.063 DOS calls; now ~190).
;  7. CR at end of line no longer swallows the byte that follows it
;     (peeked byte is pushed back with an unget slot).
;  8. ScrUp cache miss now rescans exactly: it seeks back, resyncs to a
;     line boundary and counts lines, refilling the position cache.
;     (Previously it seeked ~100 bytes back showing a chopped line.)
;  9. Scrollbar click maps thumb row to line exactly; math stays 32-bit
;     (16-bit overflowed with more than ~3.000 lines).
; 10. totLines saturates at 65.535 instead of wrapping.
; 11. Video mode is validated (mode >3 forces mode 3) and the video
;     segment is taken from the BIOS data area (B000h for mono, B800h
;     otherwise). Desktop is cleared to Turbo Vision blue, not black.
; 12. Filenames up to 64 chars (path included), optional "quotes", and
;     unknown options show help instead of being used as a filename.
;
; Revision 1.02 changes (maximum speed on a real 8086 + requested UI):
; 13. MUL/DIV replaced by shifts everywhere the math allows it.
; 14. RdLine fetches bytes inline from bBuf in the common case.
; 15. DrwCnt writes the line text and pads only the remainder.
; 16. Up/Down repaint ONLY the new line (REP MOVSW scroll + one row).
; 17. Keys that cannot change the position trigger no redraw at all.
; 18. mov reg,0 -> xor reg,reg everywhere; Init zeroes the state block
;     with one REP STOSB; no redundant screen clear.
; 19. Title bar (row 1) shows the path and name of the file being viewed.
; 20. Status bar moved down to row 25; the view window shows 23 lines.
; 21. F1 opens a pop-up window (green background, white letters) with
;     exactly the same help shown when 4VIEW runs without parameters.
; 22. On startup 4VIEW saves the whole text page and the cursor; on exit
;     everything is restored exactly as it was.
; 23. Unsigned compares so files with more than 32.767 lines scroll.
;
; Revision 1.03 changes (ASMC high level + direct BIOS keyboard):
; 24. ASMC high level control flow: .SWITCH PASCAL/.CASE/.DEFAULT (Main),
;     .FOR/.ENDF (PgUp/PgDn), .WHILE/.ENDW, .REPEAT/.UNTIL, .BREAK .IF,
;     .IF/.ELSEIF chains. (.STATIC/.INLINE are .CLASS method declarations
;     and do not apply to this procedural COM image; the .INLINE function
;     feature IS used: KeyAvail is a PROTO asmcall { ... } expanded at
;     every call site.)
; 25. No INT 16h any more: the keyboard is polled directly in the BIOS
;     data area at segment 0040h (ring head 001Ah, tail 001Ch, buffer
;     001Eh-003Dh), wrap-around included.
; 26. INT 28h (DOS idle) whenever 4VIEW waits for a keystroke.
; 27. Copyright is 2025-2026 (header, help and About).
; 28. The command line help (-h, /?, no parameters) prints and exits
;     without waiting for a key.
; 29. F10 opens an About pop-up (green background, white letters) with
;     the copyright, the version, the build date and time (@Date/@Time),
;     the CPU target and the ASMC version (__ASMC__).
; 30. The interface is painted BEFORE the file is loaded; the status bar
;     shows "Loading <full path>..." while the file is opened/scanned
;     (full path via INT 21h AH=60h Truename, DOS 3+).
; 31. The last "mov reg,0" became "xor reg,reg"; the End key clamps with
;     an unsigned compare.
; 32. The product name is always 4VIEW; unknown keys cause no repaint.
;
; Revision 1.04 changes (About fix + SMART.INC + 32-bit ops + 8086 speed):
; 33. THE ABOUT (AND F1) WINDOW WAS BLACK: AdvRow expanded to
;     "mov ax,bp" and the pop-up draws cells with STOSW taking the
;     attribute from AH - after the first row advance AH held BP's high
;     byte (0), so every row below the top border was painted black on
;     black. AdvRow now recomputes the 156-2*BP advance in CX (dead or
;     stack-saved at every call site): no helper clobbers AX and no
;     memory operand is read (the save loop runs with DS=video), so the
;     attribute set once survives the whole draw (PopLine re-arms it
;     defensively). PopUp computes its corner offset once (popOff).
; 34. The 386+ build is selected by the assembler itself:
;         USE386 equ (@Cpu AND 1000b)
;     ASMC's Masm-compatible @Cpu has bit 3 (M_386) set only when 386
;     code is generated, so "ASMC -3 -bin ..." is all it takes; the
;     -DUSE386=1 switch and the .386 directive are gone.
; 35. SMART.INC v2.0 is included and drives the 8086/386 split:
;     shl/shr with immediate counts (the private SHLN/SHRN macros are
;     deleted), FastMul for curLine*(LINES_VIS-1) in DrwBar and
;     curLine*100 in DrwSt (both were MUL or a 26-instruction shift
;     chain), multi-operand push/pop and testflag for the button/device
;     bits. Because RENAMEKEYWORD hides the shl/shr operators on the
;     8086, the cell words are precomputed equates (A_CONT or ' ' ...).
; 36. 32-bit string operations wherever the count allows, -3 build only:
;     REP MOVSD/STOSD for the screen save/restore, the desktop clear,
;     both single-line scrolls, the pop-up save/restore rows and the
;     line cache shift; the 8086 build keeps REP MOVSW/STOSW. BLKCP/
;     BLKFIL centralize it, with MOVZX guarding ECX's high word (a
;     stale high word would make REP copy megabytes of garbage).
; 37. RdLine no longer adds to curPos per byte: curPos = bBase+bIdx is
;     an invariant now, materialized once per line (RdLine, SkipLine)
;     or re-anchored by Seek - four instructions per LINE instead of
;     two memory adds per BYTE. The CRLF peek also runs inline from
;     bBuf (no GetByte/UngetByte round trip per line any more). The
;     whole-file scan of CountLines is about twice as fast on an 8086.
; 38. FullPath locates the path length with REPNE SCASB and copies it
;     with the widest MOVSW/MOVSD of the build; DrwCnt no longer clears
;     the 77 cells before rewriting a line (write + pad tail only);
;     PaintStat and DrwHdr pad instead of clearing; DrwClr is ONE
;     contiguous fill over rows 1..23 (they are adjacent in the page);
;     the three copies of the "draw lBuf + pad" loop became WrCntRow.
; 39. Dead state removed (eofF was written in five places and never
;     read); Home/End on the first/last page no longer repaint on
;     enhanced keyboards (the E0h ASCII of extended keys leaked into
;     the "moved" flag); Done's save/restore of ES (already clobbered
;     two lines before) dropped; redundant vSeg stores dropped.
;
; Revision 1.05 changes (386 desktop fill fix + maximum speed on 8086):
; 40. THE 386 BUILD CLEARED THE DESKTOP AS BLUE/BLACK VERTICAL STRIPES:
;     BLKFIL's REP STOSD writes TWO cells per dword (the low and the
;     high word of EAX), but only AX was loaded with the cell word - the
;     second cell of every pair took its character and attribute from
;     the stale high word (exactly the screenshot bug: striped screen
;     while the status bar said "Loading ..."). BLKFIL now duplicates
;     the cell into both halves of EAX (PUSH AX/PUSH AX/POP EAX).
;     BLKCP/BLKFIL/CpyN also use the 386 immediate shift (SHR ECX,2) and
;     CpyN does the MOVZX before the split, one instruction less.
; 41. RdLine's per-byte loop rebuilt: the build mode is decided ONCE
;     per line (the old loop re-tested isFile and hFull with memory
;     compares on EVERY byte), SI walks bBuf with LODSB (12 cycles,
;     no effective address, no bIdx adds), and CX is preloaded with
;     min(77, bytes left in the block) so the end-of-block test is
;     gone from the loop as well: ~62 cycles per byte on an 8086
;     instead of ~171 (2.7x). CountLines (whole-file scan), DrwCnt,
;     ScrDn and the ScrUp rescan all run through here.
; 42. FillBuf no longer seeks (INT 21h AH=42h dropped): the DOS file
;     pointer equals bBase at every entry (open: 0; Seek moves the
;     pointer AND sets bBase=curPos; FillBuf itself advances bBase by
;     the bLen bytes just read), so the seek was one wasted DOS call
;     per block. BUFSZ grew 4096 -> 16384: a 385 KB file now loads
;     with 24 reads instead of 94 reads + 94 seeks.
; 43. SkipLine is gone: ScrUp's exact rescan calls RdLine, which stops
;     at CR/CRLF/LF exactly like the viewer's line semantics (the old
;     SkipLine waited for an LF and swept CR-only files whole).
; 44. ScrUp on STDIN: a pipe cannot be re-read, so scrolling up now
;     reports "no move" instead of replaying the all-zero offset cache
;     (this also removes the only way into the rescan retry with
;     tmpPos=0, which looped forever).
; 45. ParseCmd shows help for ANY option directly: the -h/? letter
;     check was dead code, both paths did STC.
; 46. Version 1.05 (title, help and About); DrwCnt reloads the row base
;     once per row instead of twice.
;
; Revision 1.06 changes (horizontal scroll + no-DOS re-anchoring +
; STDIN ring + wheel/Truename fixes):
; 47. HORIZONTAL SCROLL: Left/Right move the window one column
;     (Ctrl+Left/Right ten columns), hPos is the window start, lBuf
;     now holds up to 255 chars (LBUFCAP) instead of 77, WrCntRow
;     paints [hPos..hPos+77) of each line, Right clamps at HPOSMAX,
;     Home also resets hPos, and the status bar shows the column
;     ("C<n>") whenever hPos>0. The F1 help documents the new keys.
; 48. SeekSoft: re-anchoring the reader inside the buffered 16 KiB
;     block only rewinds bIdx - no AH=42h and no refill. 1.05 called
;     the real Seek per Up line, which zeroed bLen and forced RdLine
;     to refill 16 KiB: one PgUp inside a block did 23 DOS seeks plus
;     up to 23*16 KiB = 368 KiB of re-reading. Now the same PgUp does
;     ZERO DOS calls unless a block boundary is crossed; DrwUp1/
;     DrwDn1/DrwCnt/GoLine/CountLines/Home re-anchor through it too.
; 49. CountLines runs RdLine in count mode (cntMode): the pre-scan does
;     not store the text at all (bp=1 from the entry), ~45 instead of
;     ~61 8086 cycles per byte on the pass that dominates load time.
;     The trailing line without EOL is still counted exactly: the
;     scan compares curPos with the saved line start (tmpPos), so the
;     no-store mode cannot lose it.
; 50. STDIN (pipes/redirection) WAS BROKEN SINCE 1.05: the totLines
;     estimate froze ScrDn after the first line down, DrwDn1's
;     22-line rescan swallowed 23 lines per Down (the view showed every
;     24th line), and PgDn+Draw lost whole pages. A ring with the last
;     RINGN lines (rBuf, 23*256 bytes) now backs the view: line j lives
;     in slot j mod RINGN, DrwCnt paints the ring without re-reading,
;     DrwDn1 paints the slot ScrDn just appended, End streams to the
;     end of the pipe (any key aborts), and Home/Up/PgUp/scrollbar
;     clicks are honest no-ops on a pipe. ScrDn streams without the
;     limit check (EOF decides) and saturates curLine at 65.534.
; 51. FullPath: INT 21h AH=60h needs AL=00h - AL still held the file
;     handle's low byte, so Truename ALWAYS failed and the title never
;     showed the full path. mov ax,6000h fixes it; a zero-length
;     expansion (or DOS 2.x) keeps the name as typed.
; 52. CuteMouse wheel order: wheel down is reported as middle+right
;     (mask 6), which the old bit-2 test caught first - scrolling DOWN
;     scrolled UP. Mask 6 is tested first now; the right button alone
;     scrolls one line down (the old "middle" test was dead code:
;     bit 2 never reached it because the wheel-up test ate it).
; 53. DrwDn1's 22-line rescan needs no push/pop any more (RdLine
;     preserves CX through its uses list); WrCntRow takes DS:SI as the
;     line pointer so the ring slots paint through the same code;
;     version 1.06.
;
; Revision 1.07 changes (word-scan + first-view capture + cleanup):
; 54. WORD-AT-A-TIME CONSUME-ONLY SCANNER: RdLine's count-mode and
;     >capacity loops now eat TWO bytes per iteration. Both CR and LF
;     fall in the unsigned window (b-10)<=3, so each half of the word
;     is tested with one SUB+CMP pair; a hit is re-checked exactly
;     (10=LF, 13=CR, 11/12 VT/FF are plain data). P1's CRLF partner is
;     the ALREADY LOADED AH, so the common CRLF needs no reload; the
;     ten exit cases leave SI on the next line's first byte and the
;     once-per-line bIdx sync is unchanged. ~29 instead of ~45 8086
;     cycles per byte: the 385 KB pre-scan drops from ~1.39 s to
;     ~0.88 s of CPU at 12.5 MHz (0.71 s on the 1.05 loops).
; 55. FIRST-VIEW CAPTURE: CountLines runs its first RINGN lines in
;     store mode and RingAppends them - the pre-scan already parses
;     lines 0..22, so the ring doubles as the initial view buffer.
;     ringView marks it and DrwCnt paints the ring whenever the top
;     line is line 0: the initial Draw AND Home now cost ZERO file
;     I/O (1.06 seeked to BOF, re-read 16 KiB and parsed 23 lines
;     each time).
; 56. RingPaint split out of DrwCnt (one painter, three callers:
;     STDIN, the captured first view, and Home); UngetByte inlined at
;     its two call sites (the proc call cost more than the body); the
;     dead savLine save/restore removed from DrwCnt (nothing inside
;     ever touches curLine).
; 57. End on STDIN executes INT 28h inside the stream loop, so TSRs
;     and multitaskers breathe while long pipes drain.
; 58. Version 1.07.
;
; Revision 1.08 fixes (maximum 8086 performance, load and paint):
; 59. COUNT/CONSUME SCANNER UNROLLED TO FOUR BYTES: two LODSW with the
;     same (b-10)<=3 window tests per iteration. The P1/P2 pair
;     handlers (@@candlo/@@candhi) serve P3/P4 too - the second LODSW
;     leaves SI past the pair and AL/AH in exactly the handler
;     contract - so unrolling costs loop-body bytes, not new exit
;     cases. ~24.25 cycles/byte (1.07: ~28.5), the amortized LOOP now
;     spreads over four bytes.
; 60. STORE SCANNER (DISPLAY PATH) TWO BYTES PER LODSW + STOSB: RdLine
;     sets ES=DS once per call (push/pop around the fast path) so the
;     data halves store with STOSB (11 cycles) instead of MOV [DI],AL
;     + INC DI (16). CR/LF tests per half: CMP 13/CMP 10 (no window,
;     VT/FF are plain data here and the SUB window would need a
;     restore). ~44.5 cycles/byte (1.07: ~61). The @@rcap capacity
;     recheck collapsed into the round check @@sloop; the old
;     single-byte @@cr/@@lf handlers and their GetByte block merged
;     with the @@crhi peek shared with the count scanner.
; 61. WrCntRow PAINT UNROLLED BY TWO + WORD HPOS SKIP: the hPos skip
;     reads LODSW pairs (~23.5 vs ~37 cycles/char), the paint loop
;     stores two cells per iteration (~38.5 vs ~47 cycles/cell) and
;     the REP STOSW pad counts the remaining cells with one MUL-free
;     2*CX(+1) expression. Full repaint of a 77x23 window: ~2.7 ms
;     less on the paint side alone @ 12.5 MHz.
; 62. Version 1.08.
;
; Revision 1.09 fixes:
; 63. VIEW CACHE (vCache): DrwCnt parses every row straight into a
;     23x256 cache (line j lives in slot j mod 23, the ring's own
;     discipline) instead of lBuf - the parse is the copy. wDest in
;     RdLine selects the store target (STOSB follows DI, so slot
;     indirection costs nothing); a hit (curLine == vcTop) repaints
;     the slots through RingPaint with paintBuf=vCache: Left/Right
;     h-scroll and popup close now do ZERO reads, seeks and parses
;     (1.08: 23 parses + 77-skip walk per row). RingPaint is
;     parameterized on paintBuf; wDest/paintBuf are pointers and are
;     deliberately outside the Init-cleared block.
; 64. LINE-START RING (vPos, 32 entries, line j -> entry j and 31)
;     recorded by every cache fill: DrwDn1 with a valid cache
;     (vcTop == curLine-1) reads the new bottom line's start from
;     vPos and parses ONE line into the slot the old top just left
;     (mod 23 they are the same slot) - a Down cost 23 parses in
;     1.08, it costs 1 now; the entry below the view is re-recorded
;     so Down chains stay hot. DrwUp1's hot path (vcTop == curLine+1)
;     parses the new top into the slot the old bottom left (vSlot
;     tracks line mod 23) and DrwUp1 records the new top's vPos
;     entry, so Up/Down zig-zags never go cold either. 24-25 live
;     entries < 32, so vPos entries never alias mid-chain. The entry
;     cursor rides BX/SI/DI (whichever each path has free): DX cannot
;     index memory on the 8086.
; 65. Version 1.09.
;
; Revision 1.10 fixes:
; 66. SLOT LENGTH BYTES: a 256-byte slot (lBuf, ring, vCache) now
;     holds LBUFCAP=254 chars + the NUL + the line's length at
;     slot+255, written once by RdLine at its single exit (a word
;     SUB + a byte store per line) and carried by RingAppend into
;     the ring. WrCntRow reads it and jumps straight to the window
;     start with one ADD (slot+hPos) or pads the whole row when the
;     line ends left of the window: the 1.08 LODSW skip walk, its
;     odd-column case and its NUL-backtrack (@@sl/@@sh) are deleted,
;     no paint can ever read stale slot bytes, and HPOSMAX drops to
;     177 (one column less of scroll range, invisible past the text).
;     hPos=77 on a cache hit: ~41K cycles less per repaint.
; 67. COUNT SCANNER UNROLLED TO EIGHT BYTES: four LODSW pairs per
;     iteration amortize LOOP over 8 bytes (~22.1 vs ~24.25 cycles/
;     byte, -9%): the 385 KB pre-scan drops ~65 ms @ 12.5 MHz. The
;     shared @@candlo/@@candhi handlers serve all eight halves; the
;     byte tail now covers 0..7 residues.
; 68. BUILD NAME: every user-visible string (title bar, About) says
;     4VIEW386 on the -3 build and 4VIEW on the 8086 build.
; 69. Version 1.10.
; 70. LOADING DOTS BLINK: the "..." of the "Loading <file>..." status
;     bar is repainted with the blink bit (attribute or 80h) set right
;     after PaintStat, so the load state is visible on slow machines.
;     Init also force-enables the BIOS blink state (INT 10h AX=1103h
;     BX=0001h, a no-op on PC/XT BIOSes): with blink disabled by an
;     earlier program, bit 7 renders as a bright background instead
;     of flashing and the marker would not blink at all.
; 71. VIDEO MODE RESTORED ON EXIT: Init forces mode 3 for every mode
;     that is not 2/3/7 (the 40-column modes 0/1 corrupted the 80x25
;     layout as well), remembers the user's mode, and Done sets it
;     back. Before, running 4VIEW from any non-text mode left the
;     session stuck in mode 3 after exit. The forced path skips the
;     saved-screen restore: the mode set at entry already cleared the
;     original page, there is nothing left to put back.
; 72. HLL PASS ON THE COLD LOOPS: DrwFrm/DrwBar paint loops use
;     .REPEAT/.UNTILCXZ, the pop-up save/restore row loops
;     .REPEAT/.UNTILZ, and PopLine pads its tail with one REP STOSW -
;     identical or better code, all of it outside the hot paths. The
;     hand-written flow of the hot text loops (WrTxt, WrCntRow, RdLine
;     scanners) stays on purpose.
; 73. SMART.INC V2.3 LEVERAGE PASS: the remaining constant-count shifts
;     written as 1-bit chains use the count form (shl ax,2 in the vPos
;     index math, shr cx,3 in the count scanner's /8, shr cx,2 in
;     CpyN's 386 path): byte-identical code on 8086 and ONE native
;     instruction on the -3 build. vSlot's zero-extension uses movzx
;     (mov al,x/xor ah,ah on 8086, native on 386), and ReadKey/PopUp
;     use the multi-operand push/pop. Nothing else in v2.3 applies:
;     FastIMul targets signed 16-bit constant multiplies (4VIEW's are
;     32-bit, already FastMul 22/100), setfield/getfield need packed
;     bit fields (4VIEW has none) and clrflag/flipflag/maskflag need
;     single-bit state (4VIEW's flags are whole bytes, better served
;     by mov).
;------------------------------------------------------------------------------
option dotname
.model tiny
.stack 256

;------------------------------------------------------------------------------
; CPU target of this build. ASMC's Masm-compatible @Cpu has bit 3 (1000b,
; M_386) set only when 386 code is being generated, so the -3 switch alone
; selects every 386-specific part below (fix 34). -DUSE386=1 is gone.
;------------------------------------------------------------------------------
USE386  equ (@Cpu AND 1000b)

include smart.inc               ; shl/shr imm, movzx, FastMul, push/pop
                                ; multi, setflag/testflag (Guti, v2.3).
                                ; Include AFTER the CPU is selected: @Cpu is read
                                ; here (8086: shifts expand 1 bit at a
                                ; time, MOVZX/MOVSX are emulated; -3: the
                                ; native forms pass straight through).

.code
org 100h

VERMAJ      equ 1                       ; product version 1.10
VMIN        equ 10
LINES_VIS   equ 23                      ; content rows 1..23 (title row 0,
CACHE_SZ    equ 48                      ; status row 24)
BUFSZ       equ 16384                   ; 16 KiB: 24 reads per 385 KB (fix 42)
LINEWID     equ 77                      ; painted columns of a line
LBUFCAP     equ 254                     ; chars kept per line: the 256-byte
                                        ; slot is chars + NUL + the line's
                                        ; length byte at 255 (fix 66)
HPOSMAX     equ LBUFCAP-LINEWID         ; last useful horizontal window
                                        ; (177 < 256: WrCntRow compares
                                        ; hPos's low byte, fix 66)
RINGN       equ LINES_VIS               ; ring: the visible window
SLOTSZ      equ 256                     ; slot bytes: LBUFCAP chars + NUL
                                        ; + length byte; 256 keeps the
                                        ; AH-trick slot addressing alive
VPOSN       equ 32                      ; vPos entries (line j -> j and 31)
ATTR_CONT   equ 1Fh
ATTR_HDR    equ 30h
ATTR_STAT   equ 30h
ATTR_SCRL   equ 19h
ATTR_THMB   equ 1Fh
ATTR_POP    equ 2Fh                     ; pop-ups: white letters on green
; Cell words: attribute in the high byte. Precomputed because SMART.INC's
; RENAMEKEYWORD hides the shl/shr OPERATORS on the 8086 build (fix 35).
A_CONT      equ ATTR_CONT*256
A_HDR       equ ATTR_HDR*256
A_STAT      equ ATTR_STAT*256
A_SCRL      equ ATTR_SCRL*256
A_THMB      equ ATTR_THMB*256
A_POP       equ ATTR_POP*256
HLP_W       equ 46                      ; help text width inside the borders
HLP_N       equ 19                      ; help lines (helpTab)
ABT_W       equ 36                      ; about text width inside the borders
ABT_N       equ 7                       ; about lines (aboutTab)
WWIN        equ HLP_W+2                 ; widest window incl. borders
HLP_H       equ HLP_N+4                 ; borders + one blank row top/bottom

;------------------------------------------------------------------------------
; BLKCP/BLKFIL - block copy (DS:SI -> ES:DI) / fill (AX -> ES:DI) with
; CX = byte count. The -3 build uses the 32-bit REP MOVS/STOS forms; the
; 8086 build the word forms. ECX zero-extended first: REP reads the full
; ECX, and a stale high word (real 386 real mode keeps whatever was
; there) would make it copy megabytes of garbage (fix 36). BLKFIL must
; ALSO widen the fill value - and to the DOUBLED cell, not to a zero-
; extended word: one STOSD writes TWO cells (the low word and the high
; word of EAX), so the fill value has to be AX*65536+AX. Loading AX only
; left the second cell of every pair to the stale high word - the 1.04
; 386 build painted the desktop as blue/black vertical stripes (fix 40,
; the "Loading ..." screenshot). PUSH AX/PUSH AX/POP EAX duplicates the
; cell word into both halves without touching any other register.
;------------------------------------------------------------------------------
BLKCP   macro
        if USE386
        movzx   ecx,cx
        shr     ecx,2                   ; 386: immediate shift counts
        rep     movsd
        else
        shr     cx,1
        rep     movsw
        endif
        endm

BLKFIL  macro
        if USE386
        push    ax
        push    ax
        pop     eax                     ; EAX = cell | cell<<16 (fix 40)
        movzx   ecx,cx
        shr     ecx,2
        rep     stosd
        else
        shr     cx,1
        rep     stosw
        endif
        endm

;------------------------------------------------------------------------------
; Entry point (COM: CS=DS=ES=SS=PSP already; kept EXE-safe anyway)
;------------------------------------------------------------------------------
.startup
        push cs
        pop ds                          ; DS=CS for PSP access in any build
        push ds
        pop es                          ; ES=DS for string ops
        cld

        call ParseCmd
        .if (carry?)
                call ShowHelp
                jmp @@quit
        .endif
        .if (!isFile)
                ; No filename: view STDIN only when piped/redirected.
                xor bx,bx
                mov ax,4400h            ; IOCTL: get device info
                int 21h
                jc @@dohelp
                testflag dl,7           ; bits 0-2: console input/output
                jz @@dostdin            ; none set: file or pipe
@@dohelp:       call ShowHelp
                jmp @@quit
@@dostdin:
        .endif
        call Init
        call Main
        call Done
@@quit:
.exit 0

;------------------------------------------------------------------------------
; KeyAvail - inline function (ASMC's .INLINE function feature: a PROTO
; with an asmcall body, expanded at every call site instead of called).
; ZF=1 when the BIOS keyboard ring at 0040h is empty, ZF=0 when a key
; waits. The trailing pop ds does not touch the flags, so the result
; reaches the caller's .untilnz/.jnz directly (fixes 24/25/26).
; Clobbers AX.
;------------------------------------------------------------------------------
KeyAvail proto asmcall {
        push ds
        mov ax,0040h
        mov ds,ax
        mov ax,ds:[001Ah]               ; ring head
        cmp ax,ds:[001Ch]               ; head == tail: buffer empty
        pop ds
        }

;------------------------------------------------------------------------------
; ParseCmd - parse the command tail at PSP:80h
;  CF=1 -> show help (-h, /?, unknown option)
;  else isFile=1 and fName=ASCIZ name, or isFile=0 for STDIN mode
;------------------------------------------------------------------------------
ParseCmd proc
        mov si,81h
        .while (byte ptr [si]==' ' || byte ptr [si]==9)
                inc si
        .endw
        mov al,[si]
        .if (al==0Dh)
                mov byte ptr isFile,0   ; no parameter: STDIN mode
                clc
                ret
        .endif
        .if (al=='-' || al=='/')
                inc si
                stc                     ; -h, /? or any other option:
                ret                     ; help (fix 45: dead code dropped)
        .endif
        mov di,offset fName
        .if (byte ptr [si]=='"')        ; quoted name
                inc si
                mov cx,64
                .while (cx)
                        lodsb
                        .break .if (al=='"' || al==0Dh)
                        stosb
                        dec cx
                .endw
        .else
                mov cx,64
                .while (cx)
                        mov al,[si]
                        .break .if (al==0Dh || al==' ' || al==9)
                        inc si
                        stosb
                        dec cx
                .endw
        .endif
        mov byte ptr [di],0
        mov byte ptr isFile,1
        clc
        ret
ParseCmd endp

;------------------------------------------------------------------------------
; Init - zero state, save screen+cursor, set video, paint the static
; chrome FIRST (fix 30), then open the file, resolve its full path,
; count the lines ("Loading <full path>..." on the status bar) and
; start the mouse.
;------------------------------------------------------------------------------
Init proc
        ; zero the whole state block in one pass (fix 18)
        push ds
        pop es
        mov di,offset zStart
        mov cx,offset zEnd - offset zStart
        xor al,al
        rep stosb

        ; validate the video mode (BIOS data 0040:0049) and pick the
        ; video segment in the same pass: B000h for mono (mode 7),
        ; B800h otherwise (declared so, never touched elsewhere)
        push es
        mov ax,0040h
        mov es,ax
        mov bl,es:[49h]
        mov svMode,bl                  ; the mode at entry (fix 71)
        .if (bl!=2 && bl!=3 && bl!=7)  ; not an 80x25 text mode: modes 0/1
                mov ax,0003h           ; are 40-column (the 80x25 layout
                int 10h                ; corrupted them too, fix 71), 4+
                mov bl,3               ; are graphics. Force mode 3 and
                mov svForced,1         ; remember it for Done (fix 71)
        .endif
        .if (bl==7)
                mov word ptr vSeg,0B000h
        .endif
        pop es
        ; blink ON (fix 70): the loading "..." carries attribute bit 7,
        ; which only blinks while the BIOS blink state is enabled - a
        ; previous program may have switched to "bright backgrounds"
        ; (INT 10h AX=1003h/BL=0), which turns B0h into a steady bright
        ; cyan. AX=1103h BX=0001h re-enables it on EGA/VGA; the PC/XT
        ; BIOSes range-check AH and IRET on 10h+, so it is a no-op on
        ; CGA/MDA machines (where nothing could have disabled it).
        mov ax,1103h
        mov bx,0001h
        int 10h

        ; save cursor (shape, position, page) and the whole text screen
        ; BEFORE anything is painted, so Done can put it all back (fix 22)
        mov ah,0Fh
        int 10h                         ; AL=mode, BH=active page
        mov svPage,bh
        mov ah,03h
        int 10h                         ; CX=shape, DX=position
        mov svShape,cx
        mov svCurs,dx
        push ds
        mov ax,vSeg
        mov ds,ax
        xor si,si
        mov di,offset svScr
        mov cx,4000
        BLKCP                           ; video page -> svScr (fix 36)
        pop ds

        ; hide cursor before the (possibly long) load
        mov ah,1
        mov cx,2000h
        int 10h

        ; static chrome first (fix 30): title, desktop, frame, scrollbar
        call DrwHdr
        call DrwClr
        call DrwFrm
        call DrwBar
        mov si,offset fName
        .if (!isFile)
                mov si,offset sSTDIN
        .endif
        call StatLoad                   ; "Loading <name>..." right away

        .if (isFile)
                mov dx,offset fName
                mov ax,3D00h
                int 21h
                .if (carry?)
                        call Done       ; restore the user's screen
                        mov dx,offset sErr
                        mov ah,9
                        int 21h
                        mov ax,4C01h
                        int 21h
                .endif
                mov hFile,ax
                call FullPath           ; fName = fully qualified path
                call DrwHdr             ; title now shows the full path
                mov si,offset fName
                call StatLoad           ; "Loading <full path>..." (fix 30)
                call CountLines         ; also captures view #1 (fix 55)
        .endif

        ; mouse
        xor ax,ax
        int 33h
        .if (ax)
                mov mPres,1
                mov ax,1
                int 33h
        .endif
        ret
Init endp

;------------------------------------------------------------------------------
; CpyN - copy CX bytes DS:SI -> ES:DI, any count, with the widest string
; ops of the build (MOVSD on 386+, MOVSW on 8086). Clobbers AX CX.
;------------------------------------------------------------------------------
CpyN proc
        if USE386
        push cx
        shr cx,2
        movzx ecx,cx            ; REP reads ECX: no stale high word (36)
        rep movsd
        pop cx
        and cx,3
        rep movsb               ; the 0-3 trailing bytes
        else
        push ax
        mov ax,cx
        shr cx,1
        rep movsw
        jnc @F
        movsb                   ; odd length: the last byte
@@:     pop ax
        endif
        ret
CpyN endp

;------------------------------------------------------------------------------
; FullPath - replace fName with the fully qualified path (INT 21h AH=60h
; Truename, DOS 3+). Keeps the name as typed when DOS rejects the call
; (DOS 2.x) or the expansion does not fit the 64-char fName. The result
; is located with REPNE SCASB and copied with the widest MOVSW/MOVSD of
; the build - about twice the 1.03 byte loop on an 8086 (fix 38).
; FIX 51: Truename needs AL=00h; 1.05 called it with AL holding the low
; byte of the just-opened file handle, so DOS answered "invalid function"
; every time and the title NEVER showed the full path. AX=6000h.
;------------------------------------------------------------------------------
FullPath proc
        push ds
        pop es                          ; ES=DS: tBuf is a data buffer (the
                                        ; chrome procs leave ES=vSeg!)
        mov si,offset fName
        mov di,offset tBuf
        mov ax,6000h                    ; Truename with AL=00h (fix 51:
        int 21h                         ; mov ah,60h kept the handle's
        jc @@keep                       ; low byte in AL and always failed)
        mov di,offset tBuf
        mov cx,128                      ; scan the whole scratch buffer
        xor al,al
        repne scasb                     ; DI = one past the NUL
        jne @@keep                      ; no NUL: keep the name as typed
        mov cx,di
        sub cx,offset tBuf+1            ; CX = path length
        .if (cx>64)                     ; fName holds 64 chars + NUL
                mov cx,64
        .endif
        .if (cx)                        ; zero length: keep as typed
                mov si,offset tBuf
                mov di,offset fName
                call CpyN
                mov byte ptr [di],0
        .endif
@@keep: ret
FullPath endp

;------------------------------------------------------------------------------
; StatLoad - status bar: "Loading <SI>..." while the file is loaded.
; DS:SI = ASCIZ middle string (fName or sSTDIN). The trailing "..."
; is repainted with the blink bit set (fix 70): the pre-scan of a big
; file can take seconds, and a blinking marker says "busy, not hung".
;------------------------------------------------------------------------------
StatLoad proc
        push ds
        pop es                          ; ES=DS: stBuf is a data buffer
        mov di,offset stBuf
        push si
        mov si,offset sLoad
        call Cpy
        pop si
        call Cpy
        mov ax,di                       ; AX = offset of "..." in stBuf
        push ax                         ; (fix 70)
        mov si,offset sDots
        call Cpy
        mov byte ptr [di],0
        call PaintStat
        pop ax                          ; repaint the dots with the blink
        mov si,ax                       ; bit: PaintStat wrote them with
        add si,offset stBuf            ; the plain status color
        shl ax,1                       ; char offset -> page byte offset
        mov es,vSeg
        mov di,24*160+2
        add di,ax
        mov ah,ATTR_STAT or 80h        ; blink attribute (bit 7)
        .while (byte ptr [si])
                lodsb
                stosw
        .endw
        ret
StatLoad endp

;------------------------------------------------------------------------------
; SeekSoft - re-anchor the buffered reader at curPos WITHOUT touching DOS
; when curPos still lies inside the buffered 16 KiB block: only bIdx is
; rewound and the block is reused (fix 48). This is the hot path of
; Up/PgUp/repaints: 1.05 called the real Seek per line, which zeroed bLen
; and forced RdLine to refill 16 KiB - one PgUp inside a block made 23
; DOS seeks plus up to 23*16 KiB = 368 KiB of useless re-reading. The
; unget slot is cleared: its byte always sits at curPos and is re-read
; from the buffer, so the bIdx/cursor invariant stays exact. Three cases:
;   - inside the block: bIdx = curPos-bBase, no DOS call at all;
;   - exactly at the block end: empty the block (bLen=0/bIdx=0), the
;     DOS pointer already is there, the next read refills forward;
;   - outside: fall through to Seek (INT 21h AH=42h).
; Clobbers AX DX (CX on the DOS fallback).
;------------------------------------------------------------------------------
SeekSoft proc
        .if (!isFile)
                ret
        .endif
        mov hFull,0
        mov ax,word ptr curPos
        mov dx,word ptr curPos+2
        sub ax,word ptr bBase
        sbb dx,word ptr bBase+2
        jc @@hard                       ; curPos < bBase
        or dx,dx
        jnz @@hard                      ; farther than 64 KiB before it
        cmp ax,bLen
        je @@empty                      ; exactly the block end
        jae @@hard                      ; past the block
        mov bIdx,ax                     ; inside: rewind bIdx, no DOS
        ret
@@empty:
        xor ax,ax
        mov bIdx,ax
        mov bLen,ax                     ; consumed: refill forward
        ret
@@hard:
        jmp Seek
SeekSoft endp

;------------------------------------------------------------------------------
; CountLines - pre-scan the whole file (buffered: fast). The speed of
; this pass is RdLine's: inline fetch, no per-byte curPos adds, no
; per-line unget round trip (fixes 14/37). Since 1.06 RdLine runs here
; in count mode (no text stores); since 1.07 (fix 54) the consume-only
; loop eats two bytes per iteration (~29 cycles/byte).
; NEW (fix 55): the first RINGN lines run in STORE mode and are
; RingAppended - the pre-scan already parses lines 0..22, so the ring
; doubles as the initial view: DrwCnt paints it without touching the
; file again (see ringView). The trailing line without EOL still counts
; exactly: at EOF the scan compares curPos with the saved line start
; (tmpPos), which the no-store mode would leave in an empty lBuf.
;------------------------------------------------------------------------------
CountLines proc
        mov totLines,0
        mov word ptr curPos,0
        mov word ptr curPos+2,0
        call SeekSoft
        .while (1)
                mov ax,word ptr curPos  ; tmpPos = start of this line
                mov word ptr tmpPos,ax
                mov ax,word ptr curPos+2
                mov word ptr tmpPos+2,ax
                call RdLine
                .if (al)                ; ended on CR/LF: line read
                        .if (totLines < RINGN)
                                call RingAppend   ; capture view #1 (55)
                        .elseif (totLines == RINGN)
                                mov cntMode,1    ; view full: count-only
                        .endif
                        .break .if (totLines==0FFFFh)   ; saturate (10)
                        inc totLines
                .else
                        ; EOF: count a trailing partial line exactly
                        mov ax,word ptr curPos
                        mov dx,word ptr curPos+2
                        sub ax,word ptr tmpPos
                        sbb dx,word ptr tmpPos+2
                        .if (ax || dx)  ; bytes were consumed: partial
                                .break .if (totLines==0FFFFh)
                                inc totLines
                        .endif
                        .break
                .endif
        .endw
        mov cntMode,0
        mov ringView,1                  ; the ring holds view #1 (55)
        mov word ptr curPos,0
        mov word ptr curPos+2,0
        mov curLine,0
        mov cCnt,0
        call SeekSoft
        ret
CountLines endp

;------------------------------------------------------------------------------
; FillStdin - prime the STDIN ring with the first view: read up to
; LINES_VIS lines from the pipe and append each one to the ring (fix 50).
;------------------------------------------------------------------------------
FillStdin proc
        mov cx,LINES_VIS
        .repeat
                call RdLine
                .break .if (!al)
                call RingAppend
        .untilcxz
        ret
FillStdin endp

;------------------------------------------------------------------------------
; RingAppend - add the line just read into lBuf as the newest ring slot,
; advance rIdx (wrapping at RINGN). Line j lives in slot j mod RINGN, so
; the visible window is always the last RINGN appended lines (fix 50;
; in file mode the ring is written once, here or in CountLines).
; Copies up to and including the NUL (consumers stop at the NUL, stale
; bytes after it in a reused slot are invisible). Clobbers AX SI DI;
; preserves CX.
;------------------------------------------------------------------------------
RingAppend proc uses cx
        push ds
        pop es                          ; ES=DS (callers may hold ES=video)
        mov ax,rIdx
        mov ah,al
        xor al,al                       ; AX = rIdx*256 without shl ax,8
        mov di,offset rBuf
        add di,ax
        mov al,byte ptr lBuf[255]       ; the length byte travels with
        mov byte ptr [di+255],al        ; the line into the ring (fix 66)
        mov si,offset lBuf
@@c:    lodsb
        stosb
        or al,al
        jnz @@c
        inc rIdx
        .if (rIdx >= RINGN)
                mov rIdx,0
        .endif
        ret
RingAppend endp

;------------------------------------------------------------------------------
; RingPaint - paint a 23-slot buffer as the content window (fix 56, split
; out of DrwCnt): row i shows line curLine+i, which lives in slot
; (curLine+i) mod RINGN (line j is slot j mod RINGN by construction);
; the walk starts at slot curLine mod RINGN and wraps once. The buffer
; base comes from paintBuf (fix 63): rBuf for STDIN and the captured
; first view (ringView, curLine==0 - the initial Draw and Home do no
; file I/O at all, fix 55), vCache for h-scroll/pop-up repaints of an
; already-parsed view (fix 63).
;------------------------------------------------------------------------------
RingPaint proc uses ax bx cx dx si di bp
        mov es,vSeg
        mov ax,curLine
        xor dx,dx
        mov bx,RINGN
        div bx                          ; DX = curLine mod RINGN
        mov ax,dx
        mov ah,al
        xor al,al                       ; AX = slot*256 (no shl ax,8)
        mov si,paintBuf
        add si,ax
        mov di,160+2
        mov cx,LINES_VIS
        .repeat
                mov bp,di
                push cx
                push si
                call WrCntRow
                pop si
                add si,SLOTSZ
                mov ax,paintBuf
                add ax,RINGN*SLOTSZ
                cmp si,ax
                jb @@k
                mov si,paintBuf         ; wrap to the oldest slot
@@k:            mov di,bp
                add di,160
                pop cx
        .untilcxz
        ret
RingPaint endp

;------------------------------------------------------------------------------
; Main - key dispatch. Left/Right/Ctrl+Left/Ctrl+Right scroll the
; horizontal window (fix 47); STDIN streams forward only (fix 50).
;------------------------------------------------------------------------------
Main proc
        .if (!isFile)
                call FillStdin          ; prime the ring with view #1
        .endif
        call Draw
@@lp:   .if (mPres)
                call MousePoll
        .endif
        ; wait for a keystroke: DOS idle + mouse polling until the
        ; BIOS ring (0040h) holds a key (fixes 25/26)
        .repeat
                int 28h                 ; DOS idle: TSRs/multitaskers run
                .if (mPres)
                        call MousePoll  ; wheel/click while we wait
                .endif
                KeyAvail()              ; ZF=1: ring empty
        .untilnz
        call ReadKey                    ; pop the keystroke from 0040h
        mov keyScan,ah                  ; handlers clobber AX
        mov byte ptr moved,0            ; flag: "something moved"
        .switch pascal ah
        .case 01h                       ; ESC
                jmp @@quitmain
        .case 48h                       ; Up
                call ScrUp              ; AL=1 only if it really moved
        .case 50h                       ; Down
                call ScrDn
        .case 49h                       ; PgUp
                .for (cx=LINES_VIS: cx: cx--)
                        push cx
                        call ScrUp
                        or moved,al
                        pop cx
                .endf
        .case 51h                       ; PgDn
                .for (cx=LINES_VIS: cx: cx--)
                        push cx
                        call ScrDn
                        or moved,al
                        pop cx
                .endf
        .case 47h                       ; Home
                xor al,al               ; enhanced keyboards deliver AL=E0h
                .if (isFile)            ; for extended keys: force "no move"
                        .if (curLine || hPos)
                                mov curLine,0   ; so nothing moved is really
                                mov hPos,0      ; nothing moved (fix 39)
                                mov word ptr curPos,0
                                mov word ptr curPos+2,0
                                mov cCnt,0
                                call SeekSoft
                                mov al,1
                        .endif
                .endif
        .case 4Fh                       ; End
                .if (isFile)
                        mov ax,totLines
                        cmp ax,LINES_VIS ; unsigned clamp (fix 31: 1.02 used
                        ja @F           ; a signed .if here and jumped to
                        xor ax,ax       ; the TOP on >32.767-line files)
                        jmp @@endset
@@:                     sub ax,LINES_VIS
@@endset:               mov dx,ax       ; target line to DX first: the
                        xor ax,ax       ; "no move" reset above (fix 39,
                        .if (dx!=curLine)   ; extended keys arrive with AL=E0h)
                                mov curLine,dx  ; must not eat the line number
                                call GoLine
                                mov al,1
                        .endif
                .else
                        ; STDIN: stream forward to the end of the pipe;
                        ; any queued key aborts the stream (fix 50) and
                        ; INT 28h keeps TSRs running while it drains (57)
                        xor bx,bx
                        .repeat
                                call ScrDn
                                .break .if (!al)
                                inc bx
                                int 28h
                                KeyAvail()
                        .untilnz
                        .if (bx)
                                mov al,1
                        .else
                                xor al,al
                        .endif
                .endif
        .case 3Bh                       ; F1
                mov bx,offset helpTab
                mov cx,HLP_N
                mov dx,HLP_W
                call PopUp
        .case 44h                       ; F10
                mov bx,offset aboutTab
                mov cx,ABT_N
                mov dx,ABT_W
                call PopUp
        .case 4Bh                       ; Left: one column left (fix 47)
                xor al,al
                .if (hPos)
                        dec hPos
                        mov al,1
                .endif
        .case 4Dh                       ; Right: one column right (47)
                mov ax,hPos
                .if (ax < HPOSMAX)
                        inc hPos
                        mov al,1
                .else
                        xor al,al
                .endif
        .case 73h                       ; Ctrl+Left: ten columns (47)
                xor al,al
                .if (hPos > 10)
                        sub hPos,10
                        mov al,1
                .elseif (hPos)
                        mov hPos,0
                        mov al,1
                .endif
        .case 74h                       ; Ctrl+Right: ten columns (47)
                mov ax,hPos
                .if (ax < HPOSMAX-10)
                        add hPos,10
                        mov al,1
                .elseif (ax < HPOSMAX)
                        mov hPos,HPOSMAX
                        mov al,1
                .else
                        xor al,al
                .endif
        .default
                xor al,al               ; unknown key: no repaint (fix 32)
        .endsw
        or moved,al
        jz @@lp                         ; fix 17: nothing changed -> no repaint
        mov al,keyScan
        .if (al==48h)
                call DrwUp1             ; single line up: scroll + 1 row
        .elseif (al==50h)
                call DrwDn1             ; single line down: scroll + 1 row
        .else
                call Draw               ; page/Home/End/popups: full repaint
        .endif
        jmp @@lp
@@quitmain:
        ret
Main endp

;------------------------------------------------------------------------------
; MousePoll - poll INT 33h and act on the wheel, the right button and
; left clicks on the scrollbar. Called from the main idle loop so the
; mouse keeps working while 4VIEW waits for keys.
; FIX 52: CuteMouse reports wheel up as the middle button (bit 2) and
; wheel down as MIDDLE+RIGHT (mask 6). 1.05 tested bit 2 first, so the
; wheel down was caught by the wheel-up branch and scrolled UP. Mask 6
; is tested first; the right button alone scrolls one line down (the
; old "middle" test was dead code: bit 2 never reached it).
;------------------------------------------------------------------------------
MousePoll proc
        mov ax,3
        int 33h                         ; BX buttons, CX x*8, DX y*8
        testflag bl,6                   ; wheel down = middle+right
        jnz @@wdn
        testflag bl,4                   ; wheel up = middle button
        jnz @@wup
        testflag bl,2                   ; right button: one line down
        jnz @@wdn
        testflag bl,0                   ; left click on scrollbar
        jz @@done
        shr cx,3                        ; /8 -> column (one SHR on 386+)
        shr dx,3                        ; /8 -> row
        .if (cx==78 && dx>=1 && dx<=LINES_VIS && isFile)
                                        ; the thumb needs a seekable file:
                                        ; a pipe has no line N (fix 50)
                sub dx,1                ; thumb row 0..LINES_VIS-1
                mov ax,totLines
                or ax,ax
                jz @@done
                cmp ax,LINES_VIS        ; unsigned: whole file on screen?
                jbe @@done
                mov bx,totLines
                sub bx,LINES_VIS        ; bx = tot-LINES_VIS
                mov ax,dx               ; ax = clicked thumb row
                mul bx                  ; dx:ax = row*(tot-LINES_VIS)
                mov bx,LINES_VIS-1
                div bx                  ; exact inverse of DrwBar.
                                        ; MUL/DIV kept: variable
                                        ; divisor, once per click
                cmp ax,totLines         ; unsigned clamp (fix 23)
                jb @@clp
                mov ax,totLines
                dec ax
@@clp:          mov curLine,ax
                call GoLine
                call Draw
@@wr:           KeyAvail()              ; ESC/keys abort the wait if the
                jnz @@wrdone            ; button sticks (BIOS ring, 25)
                int 28h                 ; DOS idle (26)
                mov ax,3
                int 33h
                testflag bl,0
                jz @@wr
@@wrdone:
        .endif
@@done: ret
@@wup:  call ScrUp
        or al,al
        jz @@done
        call DrwUp1                     ; one line: partial repaint
        jmp @@done
@@wdn:  call ScrDn
        or al,al
        jz @@done
        call DrwDn1
        jmp @@done
MousePoll endp

;------------------------------------------------------------------------------
; ReadKey - AX = keystroke (AL=ASCII, AH=scan) taken straight from the
; BIOS ring at 0040h, exactly what INT 16h AX=00h returned (fix 25).
; Waits here while the ring is empty and executes INT 28h on every poll
; so TSRs and multitaskers can run (fix 26); with a key already queued
; it is taken immediately, without an idle call. Used by the pop-ups.
;------------------------------------------------------------------------------
ReadKey proc
        push ds, bx                     ; SMART.INC multi push
        mov ax,0040h
        mov ds,ax
        .while (1)
                mov bx,ds:[001Ah]       ; ring head
                cmp bx,ds:[001Ch]       ; head == tail: ring empty
                .break .ifnz            ; a key waits: take it, and no
                int 28h                 ; idle call is needed (fix 26)
        .endw
        mov ax,[bx]                     ; the queued keystroke word
        add bx,2
        cmp bx,003Eh                    ; past the end of the ring?
        jb @F
        mov bx,001Eh                    ; wrap around to the ring start
@@:     mov ds:[001Ah],bx               ; advance the head
        pop bx, ds                     ; SMART.INC multi pop
        ret
ReadKey endp

;------------------------------------------------------------------------------
; ScrUp - one line back: cache hit walks the cache; cache miss rescans
; exactly from a safe distance and rebuilds the cache.
; Returns AL=1 if the view moved, AL=0 if nothing changed (fix 17).
; The re-anchoring goes through SeekSoft (fix 48): staying inside the
; buffered block costs no DOS call at all.
;------------------------------------------------------------------------------
ScrUp proc
        xor al,al
        .if (curLine==0)
                ret                     ; on the first line already
        .endif
        .if (!isFile)
                ret                     ; a pipe cannot be re-read: "no
        .endif                          ; move" (fix 44: the old cache walk
                                        ; replayed zeros and the rescan
                                        ; fallback hung on tmpPos=0)
        .if (cCnt)
                dec curLine
                dec cCnt
                mov bx,cCnt
                shl bx,2                ; *4 (SMART.INC: 1-bit steps on 8086)
                mov ax,word ptr cache[bx]
                mov dx,word ptr cache[bx+2]
                mov word ptr curPos,ax
                mov word ptr curPos+2,dx
                call SeekSoft           ; inside the block: no DOS (fix 48)
                mov al,1
                ret
        .endif

        ; --- slow path: exact rescan (fix 8) ---
        mov ax,word ptr curPos
        mov word ptr tmpPos,ax
        mov ax,word ptr curPos+2
        mov word ptr tmpPos+2,ax
        mov word ptr backAmt,512
        mov word ptr backAmt+2,0
@@again:
        ; curPos = tmpPos - backAmt  (saturate at 0)
        mov ax,word ptr tmpPos
        mov dx,word ptr tmpPos+2
        sub ax,word ptr backAmt
        sbb dx,word ptr backAmt+2
        jnc @@nob
        xor ax,ax
        xor dx,dx
@@nob:  mov word ptr curPos,ax
        mov word ptr curPos+2,dx
        call SeekSoft                   ; usually still inside the block (48)
        .if (word ptr curPos || word ptr curPos+2)
                call RdLine             ; drop the partial line (fix 43:
        .endif                          ; RdLine stops at CR/LF exactly
                                        ; like the viewer's lines)
        xor di,di                       ; lines scanned
@@scan: ; until curPos >= tmpPos
        mov ax,word ptr curPos
        mov dx,word ptr curPos+2
        cmp dx,word ptr tmpPos+2
        ja @@scanend
        jb @@doit
        cmp ax,word ptr tmpPos
        jae @@scanend
@@doit: call CachePos                   ; remember each line start
        call RdLine
        or al,al
        jz @@scanend                    ; EOF safety
        inc di
        jmp @@scan
@@scanend:
        or di,di
        jnz @@moved
        ; landed exactly on a line start: step back further and retry
        mov ax,word ptr backAmt+2
        or ax,ax
        jnz @@from0
        cmp word ptr backAmt,4096
        jae @@from0
        shl word ptr backAmt,1          ; back *= 2
        rcl word ptr backAmt+2,1
        jmp @@again
@@from0:
        mov ax,word ptr tmpPos          ; rescan from BOF
        mov word ptr backAmt,ax
        mov ax,word ptr tmpPos+2
        mov word ptr backAmt+2,ax
        jmp @@again
@@moved:
        dec curLine                     ; rescan lands exactly one line up:
                                        ; the last cached entry IS line A-1
        ; curPos = last cached line start (the new current line)
        mov bx,cCnt
        dec bx
        shl bx,2
        mov ax,word ptr cache[bx]
        mov dx,word ptr cache[bx+2]
        mov word ptr curPos,ax
        mov word ptr curPos+2,dx
        dec cCnt                        ; drop it: last entry must again be
        call SeekSoft                   ; the line BEFORE curLine (ScrDn rule)
        mov al,1
        ret
ScrUp endp

;------------------------------------------------------------------------------
; ScrDn - one line forward.
; File mode: the totLines limit decides (EOF check inside RdLine).
; STDIN mode (fix 50): the pipe length is unknown, so NO limit check
; runs - RdLine's EOF decides - and every line read is appended to the
; ring so the view can be repainted without re-reading the pipe. The
; totLines estimate grows to curLine+LINES_VIS (lines known to exist);
; curLine saturates at 65.534 top lines.
; Returns AL=1 if the view moved, AL=0 if nothing changed (fix 17).
;------------------------------------------------------------------------------
ScrDn proc
        xor al,al
        .if (isFile)
                mov ax,curLine
                add ax,LINES_VIS
                jc @@s                  ; wrapped: definitely at the end
                cmp ax,totLines         ; unsigned: bottom reached (fix 23)
                jae @@s
                call CachePos
                call RdLine
                or al,al
                jz @@s
                inc curLine
                mov al,1
                ret
        .else
                call RdLine             ; EOF decides (the estimate of 1.05
                or al,al                ; froze the pipe after line one)
                jz @@s
                call RingAppend         ; newest slot = this line (fix 50)
                mov ax,curLine
                inc ax
                jz @@s                  ; 65.535 top lines: stop safely
                mov curLine,ax
                add ax,LINES_VIS
                cmp ax,totLines
                jbe @@sk
                mov totLines,ax         ; lines known to exist so far
@@sk:           mov al,1
                ret
        .endif
@@s:    xor al,al               ; bottom/wrapped/no line: AL=0 (entry AL was
        ret                     ; clobbered - don't leak it)
ScrDn endp

;------------------------------------------------------------------------------
; DrwUp1 - paint one line UP without a full redraw: move the content
; down one row with one REP (backward, overlap-safe) and draw only the
; new top row. The new top line text is re-read from curPos (cheap:
; buffered, and the restore goes through SeekSoft, fix 48). 32-bit
; REP MOVSD on the -3 build (fix 36). With a valid view cache
; (vcTop == curLine+1, fix 64) the line is parsed into the slot the
; old bottom line just left and the cache slides up one; otherwise
; the cache is invalidated and the line goes to lBuf as before.
; vPos always gets the new top line's start, so a Down right after
; an Up is still hot.
;------------------------------------------------------------------------------
DrwUp1 proc
        push es
        mov ax,vSeg
        mov es,ax
        push ds
        mov ds,ax                       ; DS=ES=video for the scroll
        std                             ; rows 1..22 -> 2..23 (overlap!)
        if USE386
        mov si,160+(LINES_VIS-1)*160-4  ; last dword of rows 1..22
        mov di,320+(LINES_VIS-1)*160-4
        mov ecx,(LINES_VIS-1)*160/4
        rep movsd
        else
        mov si,160+(LINES_VIS-1)*160-2  ; last word of rows 1..22
        mov di,320+(LINES_VIS-1)*160-2
        mov cx,(LINES_VIS-1)*160/2
        rep movsw
        endif
        cld
        pop ds
        ; fetch the new top line: RdLine advances curPos, so save it
        mov ax,word ptr curPos
        mov word ptr savPos,ax
        mov ax,word ptr curPos+2
        mov word ptr savPos+2,ax
        mov bx,curLine
        and bx,31
        shl bx,2                       ; BX = (curLine and 31)*4: vPos
        mov ax,word ptr curPos          ; entry (DX is not indexable on
        mov word ptr vPos[bx],ax        ; 8086, fix 64)
        mov ax,word ptr curPos+2
        mov word ptr vPos[bx+2],ax
        .if (vcValid && vcTop==curLine+1)
                ; hot (fix 64): the new top line takes the slot the old
                ; bottom line (vcTop+22, slots are line mod 23) just left
                .if (vSlot)
                        dec vSlot
                .else
                        mov vSlot,LINES_VIS-1
                .endif
                mov ah,vSlot
                xor al,al               ; AX = slot*256: vSlot is a byte,
                mov bx,offset vCache    ; the 8-bit load keeps sizes legal
                add bx,ax
                mov wDest,bx           ; parse the line into the slot
                call RdLine
                mov si,bx
                mov ax,curLine
                mov vcTop,ax            ; the cache slid up one
        .else
                mov vcValid,0           ; the slots no longer match the
                call RdLine             ; view: parse the top into lBuf
                mov si,offset lBuf
        .endif
        mov wDest,offset lBuf
        mov ax,word ptr savPos
        mov word ptr curPos,ax
        mov ax,word ptr savPos+2
        mov word ptr curPos+2,ax
        call SeekSoft                   ; resync: soft, no refill (fix 48)
        mov di,160+2                    ; draw the line on row 1 (ES=video
        call WrCntRow                   ; was kept by RdLine/Seek, fix 38)
        call DrwBar
        call DrwSt
        pop es
        ret
DrwUp1 endp

;------------------------------------------------------------------------------
; DrwDn1 - paint one line DOWN without a full redraw: move the content
; up one row with one REP and draw only the new bottom row.
; File mode (fix 64): with a valid cache (vcTop == curLine-1) the new
; bottom line's start comes from vPos and ONE parse fills the slot
; the old top line just left (line mod 23: 22 = -1) - 23 parses became
; 1. Cold, the 23 rows are parsed straight into the cache slots (fix
; 63) while vPos records every start, so the next Down is hot; the
; restore goes through SeekSoft either way (fix 48).
; STDIN mode (fix 50): ScrDn just appended the new bottom line to the
; ring - paint that slot, nothing is re-read from the pipe.
;------------------------------------------------------------------------------
DrwDn1 proc
        push es
        mov ax,vSeg
        mov es,ax
        push ds
        mov ds,ax                       ; DS=ES=video for the scroll
        cld                             ; rows 2..23 -> 1..22 (si > di)
        if USE386
        mov si,320                      ; full rows from col 0: borders copy
        mov di,160                      ; onto themselves; DrwBar repaints
        mov ecx,(LINES_VIS-1)*160/4     ; column 78
        rep movsd
        else
        mov si,320
        mov di,160
        mov cx,(LINES_VIS-1)*160/2
        rep movsw
        endif
        pop ds
        .if (isFile)
                ; the scan below advances curPos: save it first
                mov ax,word ptr curPos
                mov word ptr savPos,ax
                mov ax,word ptr curPos+2
                mov word ptr savPos+2,ax
                .if (vcValid && vcTop==curLine-1)
                        ; hot (fix 64): vPos knows where the new bottom
                        ; line starts - ONE parse, zero extra reads. The
                        ; new bottom (line curLine+22) lands in the slot
                        ; the old top (line curLine-1) just left: slots
                        ; are line mod 23 and 22 = -1 (mod 23)
                        mov ax,curLine
                        add ax,LINES_VIS-1
                        and ax,31
                        shl ax,2                ; vPos: bottom line (64)
                        mov si,ax               ; SI indexes (no [DX] on
                        mov ax,word ptr vPos[si] ; 8086, fix 64)
                        mov word ptr curPos,ax
                        mov ax,word ptr vPos[si+2]
                        mov word ptr curPos+2,ax
                        call SeekSoft           ; usually inside the block
                        mov ah,vSlot
                        xor al,al               ; AX = slot*256 (8-bit
                        mov bx,offset vCache    ; load: vSlot is a byte)
                        add bx,ax
                        mov wDest,bx           ; parse into the freed slot
                        call RdLine
                        mov si,bx
                        ; the line below the new view (the next Down's
                        ; hot read) starts where RdLine stopped (64)
                        mov ax,curLine
                        add ax,LINES_VIS
                        and ax,31
                        shl ax,2
                        mov di,ax               ; DI indexes: SI already
                        mov ax,word ptr curPos   ; holds the paint slot
                        mov word ptr vPos[di],ax
                        mov ax,word ptr curPos+2
                        mov word ptr vPos[di+2],ax
                        mov ax,curLine
                        mov vcTop,ax            ; the cache slid down one
                        inc vSlot
                        .if (vSlot >= LINES_VIS)
                                mov vSlot,0
                        .endif
                .else
                        ; cold: rebuild the cache for this view (fix 63)
                        mov ax,curLine
                        xor dx,dx
                        mov bx,LINES_VIS
                        div bx                  ; vSlot = curLine mod 23
                        mov vSlot,dl
                        mov ax,dx
                        mov ah,al
                        xor al,al               ; AX = slot*256
                        mov bx,offset vCache
                        add bx,ax
                        mov ax,curLine
                        and ax,31
                        shl ax,2                ; vPos: row 0 (64)
                        mov di,ax               ; DI indexes (no [DX] on
                        mov cx,LINES_VIS        ; 8086, fix 64)
@@fl:           mov wDest,bx           ; parse row i straight into slot
                        mov ax,word ptr curPos  ; vPos: row i's start (64)
                        mov word ptr vPos[di],ax
                        mov ax,word ptr curPos+2
                        mov word ptr vPos[di+2],ax
                        call RdLine
                        add bx,SLOTSZ
                        .if (bx >= offset vCache+LINES_VIS*SLOTSZ)
                                mov bx,offset vCache
                        .endif
                        add di,4
                        .if (di >= VPOSN*4)
                                xor di,di
                        .endif
                        loop @@fl
                        movzx ax,vSlot         ; AX = vSlot: the bottom
                        add ax,LINES_VIS-1     ; row's slot is vSlot+22,
                                                ; mod 23 (sizes stay legal)
                        .if (ax >= LINES_VIS)
                                sub ax,LINES_VIS
                        .endif
                        mov ah,al
                        xor al,al
                        mov si,offset vCache
                        add si,ax
                        mov ax,curLine          ; vPos: the line below
                        add ax,LINES_VIS        ; the view (next Down 64)
                        and ax,31
                        shl ax,2
                        mov di,ax               ; DI indexes (fix 64)
                        mov ax,word ptr curPos
                        mov word ptr vPos[di],ax
                        mov ax,word ptr curPos+2
                        mov word ptr vPos[di+2],ax
                        mov ax,curLine
                        mov vcTop,ax
                        mov vcValid,1
                .endif
                mov wDest,offset lBuf
                ; restore curPos and resync the buffer with it
                mov ax,word ptr savPos
                mov word ptr curPos,ax
                mov ax,word ptr savPos+2
                mov word ptr curPos+2,ax
                call SeekSoft
                ; fall through: SI = the new bottom line's slot
        .else
                ; ring: the slot ScrDn just filled is the new bottom row
                mov ax,rIdx
                dec ax
                jns @@ri
                mov ax,RINGN-1
@@ri:           mov ah,al
                xor al,al               ; AX = slot*256 without shl ax,8
                mov si,offset rBuf
                add si,ax
        .endif
        mov di,LINES_VIS*160+2          ; draw on the bottom row (fix 38)
        call WrCntRow
        call DrwBar
        call DrwSt
        pop es
        ret
DrwDn1 endp

;------------------------------------------------------------------------------
; WrCntRow - paint one line on a content row. DS:SI = slot base (lBuf,
; an rBuf ring slot or a vCache view slot), DI = byte offset of the
; row's column 1 in the video page (ES = video segment). The slot's
; LENGTH BYTE at slot+255 (fix 66: every slot is LBUFCAP chars + NUL
; + its length, written once by RdLine and carried by RingAppend)
; replaces the hPos skip walk: when the line reaches the window its
; start is one ADD away, and a line that ends left of it pads the
; whole row with one REP STOSW - stale slot bytes are never touched
; and the 1.08 NUL-backtrack cases are gone (fixes 15/38/61/66). The
; paint loop is unrolled by two cells per iteration; the pad count
; comes from the pair counter CX (2*CX / 2*CX+1). Clobbers AX CX SI DI.
;------------------------------------------------------------------------------
WrCntRow proc
        mov ah,ATTR_CONT
        mov al,byte ptr [si+255]        ; the line's length (fix 66)
        .if (al <= byte ptr hPos)       ; the line ends left of the
                mov ax,A_CONT or ' '    ; window: pad the whole row
                mov cx,LINEWID          ; (HPOSMAX < 256: the low byte
                rep stosw               ; of hPos decides, fix 66)
                ret
        .endif
        add si,hPos                     ; window start: one ADD, no walk
        mov cx,38                       ; 38 pairs + the 77th char (61)
@@p:    lodsb
        or al,al
        jz @@o1
        stosw
        lodsb
        or al,al
        jz @@o2
        stosw
        loop @@p
        lodsb                           ; the 77th char
        or al,al
        jz @@o3
        stosw
        xor ax,ax                       ; row full: no pad at all
        jmp @@pd
@@o3:   mov ax,1                        ; NUL at char 77: pad one cell
        jmp @@pd
@@o2:   mov ax,cx                       ; NUL at the pair's 2nd char:
        add ax,ax                       ; pad 2*CX cells
        jmp @@pd
@@o1:   mov ax,cx                       ; NUL at the pair's 1st char:
        add ax,ax                       ; pad 2*CX+1 cells
        inc ax
@@pd:   mov cx,ax
        mov ax,A_CONT or ' '
        rep stosw
        ret
WrCntRow endp

;------------------------------------------------------------------------------
; CachePos - remember curPos (start of current line) in the ring cache
;------------------------------------------------------------------------------
CachePos proc
        mov bx,cCnt
        .if (bx>=CACHE_SZ)
                ; shift left, drop oldest (ES must be DS here: string op)
                push si, di, cx, es, ds
                pop es
                mov si,offset cache+4
                mov di,offset cache
                mov cx,(CACHE_SZ-1)*4           ; bytes to move
                BLKCP                           ; widest copy (fix 36)
                pop es, cx, di, si
                mov bx,CACHE_SZ-1
        .endif
        shl bx,2                                ; *4
        mov ax,word ptr curPos
        mov dx,word ptr curPos+2
        mov word ptr cache[bx],ax
        mov word ptr cache[bx+2],dx
        .if (cCnt<CACHE_SZ)
                inc cCnt
        .endif
        ret
CachePos endp

;------------------------------------------------------------------------------
; GoLine - position on line curLine from BOF (rebuilding the cache)
;------------------------------------------------------------------------------
GoLine proc
        .if (curLine==0)
                mov word ptr curPos,0
                mov word ptr curPos+2,0
                mov cCnt,0
                call SeekSoft
                ret
        .endif
        mov word ptr curPos,0
        mov word ptr curPos+2,0
        mov cCnt,0
        call SeekSoft
        mov cx,curLine
        .while (cx)
                push cx
                call CachePos           ; record THIS line start first
                call RdLine             ; then advance (keeps cache
                pop cx                  ; consistent with ScrDn flow)
                .break .if (!al)
                dec cx
        .endw
        ret
GoLine endp

;------------------------------------------------------------------------------
; Buffered input engine (fixes 6, 7 and 42)
;------------------------------------------------------------------------------
; FillBuf - refill bBuf from the file (INT 21h AH=3Fh, BUFSZ bytes) and
; set bLen/bIdx. NEW in 1.05: no AH=42h seek any more - the DOS file
; pointer equals bBase at every entry (open: 0; Seek moves the pointer
; AND sets bBase=curPos; FillBuf itself advances bBase by the bLen bytes
; just read), so the seek was one wasted DOS call per block (fix 42).
; Keeps bx/cx/dx: RdLine's refill path holds the fetch cursor, the loop
; count and the exit flag across the call.
FillBuf proc uses bx cx dx
        mov bx,hFile
        mov ah,3Fh
        mov dx,offset bBuf
        mov cx,BUFSZ
        int 21h
        mov bLen,ax
        mov bIdx,0
        ret
FillBuf endp

; GetByte - AL = next byte, CF=1 on EOF. Consumed bytes advance bIdx;
; curPos is NOT updated here any more: curPos = bBase+bIdx is kept as an
; invariant and materialized by the callers (RdLine, fix 37).
GetByte proc
        .if (hFull)
                mov al,hByte
                mov hFull,0
                clc
                ret
        .endif
        .if (isFile)
                mov bx,bIdx
                .if (bx>=bLen)
                        mov ax,bLen
                        add word ptr bBase,ax
                        adc word ptr bBase+2,0
                        call FillBuf
                        .if (!bLen)
                                stc
                                ret
                        .endif
                        xor bx,bx
                .endif
                mov al,bBuf[bx]
                inc bIdx
        .else
                ; STDIN (pipe/redirect): sequential read from handle 0
                xor bx,bx
                mov ah,3Fh
                mov dx,offset cBuf
                push cx
                mov cx,1
                int 21h
                pop cx
                jc @@eof
                or ax,ax
                jz @@eof
                mov al,cBuf
        .endif
        clc
        ret
@@eof:  stc
        ret
GetByte endp

;------------------------------------------------------------------------------
; RdLine - read one line into lBuf (ASCIZ, up to LBUFCAP chars, fix 47)
; Returns AL=1 line read, AL=0 EOF. ES is saved and restored around the
; call (fix 60): the fast path runs with ES=DS so the data halves store
; through STOSB. bIdx is synced once per line (and before every escape
; to the slow path), so curPos = bBase+bIdx and FillBuf stay exact.
; The STORE scanner (display, fix 60) works in rounds of min(bytes
; left, capacity left) chars; its pair loop eats two bytes per LODSW:
;
;     LODSW / CMP AL,13 / CMP AL,10 / STOSB / MOV AL,AH /
;     CMP AL,13 / CMP AL,10 / STOSB / LOOP
;
; ~44.5 cycles per byte on an 8086 (1.07: ~61). VT/FF are plain data
; here (stored as characters), so the halves test CR/LF directly with
; two CMPs - cheaper than the 1.07 SUB window, which would force an
; extra restore before every STOSB.
;
; CONSUME scanner (fix 49+54+59): with cntMode set (CountLines), the
; line is not stored at all. The scanner eats FOUR bytes per iteration
; - both CR and LF fall in the unsigned window (b-10)<=3, so each half
; of each LODSW needs one SUB+CMP; hits are re-checked exactly (10=LF,
; 13=CR, 11/12 VT/FF are plain data). The two LODSW of an iteration
; leave SI past the pair and AL/AH exactly in the P1/P2 handler
; contract, so all four halves share @@candlo/@@candhi:
;   P1/P3 LF     : dec si (the partner opens the next line), dx=1
;   P1/P3 CR+LF  : si already right, dx=1
;   P1/P3 CR else: dec si, dx=1
;   P2/P4 LF/CR  : si already right; a CR peeks via GetByte (block
;                  edge and EOF included) and ungets a non-LF inline
;   VT/FF halves : plain data, the pair is consumed
; Tail bytes of a round (0..3, more only after VT-heavy rounds):
; single-byte checks with the same exits. ~24.25 cycles per byte (1.07:
; ~28.5, 1.05: ~62); CountLines reads the WHOLE file through here, so
; the load pass inherits the gain, and the >LBUFCAP tails of display
; lines run through the same scanner. The load pass costs one DOS read
; per 16 KiB (FillBuf) plus this scan; BUFSZ stays at 16 KiB on purpose
; - 32 KiB would halve the 24 DOS reads of a 385 KB file but grow the
; COM by 16 KiB for a few ms.
;------------------------------------------------------------------------------
RdLine proc uses bx cx dx si di bp
        push es
        push ds
        pop es                          ; ES = DS: the store loop uses
        mov di,wDest                    ; STOSB (fixes 60/63); the caller's
        mov cx,LBUFCAP                  ; ES is restored at the single exit
                                        ; wDest = lBuf unless DrwCnt aims
                                        ; a view-cache slot at it (fix 63)
        mov byte ptr [di],0
        xor dx,dx                       ; exit reason: 0 = EOF, 1 = EOL
        cmp isFile,0
        je @@slowin                     ; pipe/redirection: byte reads
        cmp hFull,0
        jne @@slowin                    ; a byte waits in the unget slot

        ; --- fast path: straight from bBuf (fix 41) ---
        xor bp,bp                       ; 0: storing, 1: consume-only
        .if (cntMode)                   ; 1.06: count pass stores nothing
                mov bp,1                ; (fix 49), EOF sniffing moved out
        .endif
        mov si,offset bBuf
        add si,bIdx
        mov bx,bLen
        add bx,offset bBuf              ; BX = end of the valid data
        or bp,bp
        jnz @@full                      ; count mode: consume-only now

; --- store scanner (fix 60): two bytes per LODSW, STOSB with ES=DS ---
; A round covers min(bytes left, capacity left) chars. The pair loop
; eats two per iteration (~44.5 cycles/byte: 89 per pair) and every
; exit lands SI on the next line's first byte, so the shared
; @@donef/@@dones exits still sync bIdx only once per line. CR is
; tested first (DOS files end CRLF); the CR-only and CRLF cases reuse
; the partner byte already loaded in AH / at [SI-1], and a CR at the
; block edge goes through the shared @@crhi GetByte peek.
@@sloop: mov ax,bx
        sub ax,si                       ; bytes left in the block
        jz @@refill                     ; block consumed: refill
        mov cx,wDest
        add cx,LBUFCAP                  ; target end: lBuf or a vCache
        sub cx,di                       ; slot (fix 63): capacity left
        jz @@sful                       ; full line: consume the rest
        cmp ax,cx
        jbe @@sn
        mov ax,cx
@@sn:   shr ax,1                        ; AX = words of this round
        mov cx,ax
        jcxz @@st                       ; one odd byte: tail check
@@sp:   lodsw                           ; P1 = AL, P2 = AH
        cmp al,13
        je @@c1
        cmp al,10
        je @@l1
        stosb                           ; P1 is data
        mov al,ah
        cmp al,13
        je @@c2
        cmp al,10
        je @@l2
        stosb                           ; P2 is data
        loop @@sp
        jmp @@sloop                     ; round over: re-check the ends
@@st:   lodsb                           ; the odd tail byte
        cmp al,13
        je @@stc
        cmp al,10
        je @@stl
        stosb
        jmp @@sloop
@@stl:  mov dx,1                        ; LF: consumed
        jmp @@donef
@@stc:  cmp si,bx                       ; CR: peek the next byte
        jae @@crhi                      ; block edge / EOF: GetByte
        cmp byte ptr [si],10
        je @@stce
        mov dx,1                        ; CR only
        jmp @@donef
@@stce: inc si                          ; CRLF: eat it
        mov dx,1
        jmp @@donef
@@c1:   cmp byte ptr [si-1],10          ; P1 CR: P2 is already loaded
        je @@c1e
        dec si                          ; CR only: P2 opens the next line
        mov dx,1
        jmp @@donef
@@c1e:  mov dx,1                        ; CRLF: both consumed
        jmp @@donef
@@l1:   dec si                          ; P1 LF: P2 opens the next line
        mov dx,1
        jmp @@donef
@@c2:   cmp si,bx                       ; P2 CR: peek the next byte
        jae @@crhi                      ; block edge / EOF: GetByte
        cmp byte ptr [si],10
        je @@c2e
        mov dx,1                        ; CR only: SI already right
        jmp @@donef
@@c2e:  inc si                          ; CRLF: eat it
        mov dx,1
        jmp @@donef
@@l2:   mov dx,1                        ; P2 LF: consumed
        jmp @@donef
@@sful: mov ax,bx
        sub ax,si
        mov bp,1                        ; lBuf full: consume the rest
        ; fall through to the consume-only scanner

; --- consume-only scanner: count mode and >capacity tails (fix 54) ---
; Entry: AX = bytes left in the block, SI = first byte, BX = block end.
; The line is not stored, so a "data" half needs no action at all.
@@full: mov cx,ax
        shr cx,3                        ; CX = 8-byte units (fix 67:
        jz @@t4                         ; unroll-8 halves the LOOP toll)
@@f8:   lodsw                           ; P1 = AL, P2 = AH
        sub al,10
        cmp al,3                        ; P1 in 0Ah..0Dh?
        jbe @@candlo
        sub ah,10
        cmp ah,3                        ; P2 in 0Ah..0Dh?
        jbe @@candhi
        lodsw                           ; P3/P4: the same pair contract
        sub al,10                       ; (AL = P-10, AH = the partner
        cmp al,3                        ; byte, SI past the pair), so the
        jbe @@candlo                    ; shared @@candlo/@@candhi
        sub ah,10                       ; handlers serve all eight halves
        cmp ah,3
        jbe @@candhi
        lodsw                           ; P5/P6
        sub al,10
        cmp al,3
        jbe @@candlo
        sub ah,10
        cmp ah,3
        jbe @@candhi
        lodsw                           ; P7/P8
        sub al,10
        cmp al,3
        jbe @@candlo
        sub ah,10
        cmp ah,3
        jbe @@candhi
@@next: loop @@f8
@@t4:   mov ax,bx
        sub ax,si                       ; 0..7 bytes (a VT-heavy round can
        jz @@refill                     ; leave more): byte tail
        mov cx,ax
@@t4b:  lodsb
        sub al,10
        cmp al,3
        ja @@t4n                        ; data: consumed
        cmp al,3
        je @@cr4                        ; CR: the peek decides the eat
        or al,al
        jz @@lfx                        ; LF: the line ends here
@@t4n:  loop @@t4b                       ; VT/FF: plain data
        jmp @@refill
@@cr4:  cmp si,bx
        jae @@crhi                      ; block edge / EOF: GetByte peek
        cmp byte ptr [si],10
        je @@cr4e
        mov dx,1                        ; CR only
        jmp @@donef
@@cr4e: inc si                          ; CRLF: eat it
        mov dx,1
        jmp @@donef
@@candlo:                               ; AL = P1-10 (0..3), AH = P2 orig
        cmp al,3
        je @@crlo                       ; CR at P1: AH decides the CRLF eat
        or al,al
        jz @@lflo                       ; LF at P1: P2 opens the next line
        sub ah,10                       ; VT/FF at P1: data, test P2 too
        cmp ah,3
        jbe @@candhi
        jmp @@next
@@candhi:                               ; AH = P2-10 (0..3), P1 was data
        cmp ah,3
        je @@crhi                       ; CR at P2: next byte via GetByte
        or ah,ah
        jz @@lfx                        ; LF at P2: consumed with the pair
        jmp @@next                      ; VT/FF: both were data
@@crlo:                                 ; CR at si-2; AH = the byte after
        cmp ah,10
        je @@clok                       ; CRLF: both consumed, si is right
        dec si                          ; CR only: AH's byte is the next line
@@clok: mov dx,1
        jmp @@donef
@@lflo:                                 ; LF at si-2: P2 unconsumed
        dec si
@@lfx:  mov dx,1
        jmp @@donef
@@crhi:                                 ; CR at si-1 (P2 or the odd tail)
        mov ax,si
        sub ax,offset bBuf
        mov bIdx,ax                     ; sync for the peek/boundary/EOF
        call GetByte
        jc @@crd2
        cmp al,10
        je @@crd2
        mov hByte,al                    ; not LF: push it back (inline,
        mov hFull,1                     ; fix 56: no UngetByte call)
@@crd2: mov dx,1
        jmp @@dones

@@donef:                                ; fast exit: bIdx = SI-bBuf once
        mov ax,si
        sub ax,offset bBuf
        mov bIdx,ax
        ; fall through
@@eof:                                  ; EOF from @@refill: bIdx=0 there
@@dones:                                ; slow exit: bIdx is already exact
        mov byte ptr [di],0
        mov ax,di                        ; the slot's length byte (66):
        sub ax,wDest                     ; AX = chars of this line, stored
        mov bx,wDest                     ; at [slot+255]: WrCntRow jumps
        mov byte ptr [bx+255],al        ; to the window start with one ADD
        mov ax,word ptr bBase           ; curPos = bBase+bIdx, once per
        add ax,bIdx                     ; line (fix 37)
        mov word ptr curPos,ax
        mov ax,word ptr bBase+2
        adc ax,0
        mov word ptr curPos+2,ax
        or dx,dx
        jz @@eores
        mov ax,1                        ; ended on CR/LF: line read
        jmp @@ret0
@@eores:
        xor ax,ax                       ; EOF: a partial line still counts
        cmp di,wDest                    ; nothing stored = no partial line
        je @@ret0                       ; (one CMP, right for any wDest and
        inc ax                          ; for the store-less count mode)
@@ret0: pop es                          ; restore the caller's ES (60)
        ret
@@refill:
        mov ax,si
        sub ax,offset bBuf
        mov bIdx,ax                     ; consumed bytes of the old block
        mov ax,bLen
        add word ptr bBase,ax
        adc word ptr bBase+2,0
        call FillBuf                    ; file pointer == bBase (fix 42)
        or ax,ax
        jz @@eof
        mov si,offset bBuf
        mov bx,bLen
        add bx,offset bBuf
        mov ax,bx
        sub ax,si                       ; bytes of the fresh block
        or bp,bp                        ; a consume-only line is running?
        jnz @@full
        jmp @@sloop                     ; display: the round check
                                        ; recomputes bytes and capacity
@@slowin:                               ; STDIN / unget slot, byte per byte
        call GetByte
        jc @@dones                      ; EOF (DX=0: partial lines count)
        cmp al,10
        je @@slf
        cmp al,13
        je @@scr                        ; CR: peek the next byte (the
        jcxz @@ssk                      ; unget slot may hold it again)
        mov [di],al
        inc di
        dec cx
@@ssk:  jmp @@slowin
@@slf:  mov dx,1
        jmp @@dones
@@scr:  call GetByte                    ; block edge / EOF / STDIN safe
        jc @@scrd
        cmp al,10
        je @@scrd                       ; CRLF: both consumed
        mov hByte,al                    ; fix 7: keep the byte (inline,
        mov hFull,1                     ; fix 56)
@@scrd: mov dx,1
        jmp @@dones
RdLine endp

;------------------------------------------------------------------------------
; Seek - position file at curPos and invalidate the buffer. Re-anchors
; the curPos = bBase+bIdx invariant (fix 37). Only the hard path of
; SeekSoft lands here; interactive code calls SeekSoft (fix 48).
;------------------------------------------------------------------------------
Seek proc
        .if (!isFile)
                ret
        .endif
        mov bx,hFile
        mov ax,4200h
        mov cx,word ptr curPos+2
        mov dx,word ptr curPos
        int 21h
        mov hFull,0
        mov ax,word ptr curPos
        mov word ptr bBase,ax
        mov ax,word ptr curPos+2
        mov word ptr bBase+2,ax
        mov bLen,0
        mov bIdx,0
        ret
Seek endp

;------------------------------------------------------------------------------
; Draw - dynamic parts only. The title bar and the frame never change,
; they are painted once by Init (fix 18). The first paint costs no file
; I/O: DrwCnt uses the ring for STDIN and for the captured view of
; lines 0..22 (fixes 50/55).
;------------------------------------------------------------------------------
Draw proc
        .if (mPres)
                mov ax,2
                int 33h
        .endif
        call DrwCnt
        call DrwBar
        call DrwSt
        .if (mPres)
                mov ax,1
                int 33h
        .endif
        ret
Draw endp
;------------------------------------------------------------------------------
; WrTxt - write the ASCIZ string DS:SI at ES:DI, attribute in AH.
; SI and DI advance past the terminator.
;------------------------------------------------------------------------------
WrTxt proc
@@t:    lodsb
        or al,al
        jz @@d
        stosw
        jmp @@t
@@d:    ret
WrTxt endp

;------------------------------------------------------------------------------
; DrwHdr - title bar: "4VIEW[386] 1.10 - <path\name>" (or STDIN). Painted by
; Init and repainted once the full path is resolved (fix 30). Writes
; title + path and pads the rest of the bar - no full-row clear (38).
;------------------------------------------------------------------------------
DrwHdr proc uses ax cx di si
        mov es,vSeg
        xor di,di
        mov ah,ATTR_HDR
        mov si,offset sHdr1
        call WrTxt
        mov si,offset fName
        .if (!isFile)
                mov si,offset sSTDIN
        .endif
        call WrTxt
        mov ax,A_HDR or ' '
        mov cx,160
        sub cx,di               ; rest of the row in bytes (even)
        shr cx,1
        rep stosw
        ret
DrwHdr endp

;------------------------------------------------------------------------------
; DrwClr - clear the 23 content rows to the desktop color. Needed as a
; separate pass now that the chrome is painted before the file is
; loaded (fix 30). Rows 1..23 are adjacent in the page, so this is ONE
; fill of 3680 bytes instead of 23 row fills (fix 38).
;------------------------------------------------------------------------------
DrwClr proc uses ax cx di
        mov es,vSeg
        mov di,160
        mov ax,A_CONT or ' '
        mov cx,LINES_VIS*160
        BLKFIL
        ret
DrwClr endp

;------------------------------------------------------------------------------
; DrwFrm - left/right borders of the content window (rows 1..23).
; Painted once. Column 78 belongs to DrwBar; there is no bottom border
; any more: the status bar now sits on row 25 (fix 20).
;------------------------------------------------------------------------------
DrwFrm proc uses ax cx di
        mov es,vSeg
        mov cx,LINES_VIS
        mov di,160
        mov ax,A_CONT or 0BAh
        .repeat                         ; one pass, painted at Init (72)
                mov es:[di],ax
                mov es:[di+158],ax
                add di,160
        .untilcxz
        ret
DrwFrm endp

;------------------------------------------------------------------------------
; DrwCnt - repaint the 23 content lines.
; The ring backs the view in three cases (fixes 50/55/56): STDIN (a
; pipe cannot be re-read) and the captured first view of a file (the
; top line is line 0 and CountLines stored lines 0..22 while scanning).
; Both paint through RingPaint with ZERO file access - the initial
; Draw and Home do no seek, no read and no line parse.
; Cache hit (fix 63): the view cache already holds this view's 23
; lines (curLine == vcTop) - RingPaint on vCache, zero file access:
; Left/Right h-scroll and popups repaint for free.
; File mode otherwise (fix 63): every row is parsed straight into its
; vCache slot (wDest), vPos records each start (fix 64) and the view
; becomes the cached one. No MUL (fix 13), BP carries the row base and
; advances by 160. Each line is written once and only the unused tail
; is padded - EOF rows are cleared explicitly.
;------------------------------------------------------------------------------
DrwCnt proc uses ax bx cx dx si di bp
        .if (!isFile || (ringView && !curLine))
                call RingPaint
                ret
        .endif
        .if (vcValid && curLine==vcTop)
                ; view-cache hit (fix 63): the same 23 lines are parsed
                ; already (Left/Right, pop-up close) - paint the slots,
                ; zero seeks, reads and line parses
                mov paintBuf,offset vCache
                call RingPaint
                mov paintBuf,offset rBuf
                ret
        .endif
        mov es,vSeg
        mov ax,word ptr curPos
        mov dx,word ptr curPos+2
        mov word ptr savPos,ax
        mov word ptr savPos+2,dx
        call SeekSoft                   ; inside the block: no DOS
        mov ax,curLine                  ; vSlot = curLine mod 23: line
        xor dx,dx                       ; curLine+i lands in slot vSlot+i
        mov bx,LINES_VIS                ; (the ring discipline, fix 63)
        div bx
        mov vSlot,dl
        mov ax,dx
        mov ah,al
        xor al,al                       ; AX = slot*256 (no shl ax,8)
        mov bx,offset vCache
        add bx,ax                       ; BX = slot cursor of row 0
        mov ax,curLine
        and ax,31
        shl ax,2                        ; AX = (curLine and 31)*4
        mov dx,ax                       ; DX = vPos entry of row 0
        mov di,160+2                    ; row 1, column 1
        mov cx,LINES_VIS
        .repeat
                mov bp,di               ; BP = content start of this row
                push cx
                mov wDest,bx           ; parse row i straight into its
                                        ; cache slot: no copy pass (63)
                mov si,dx               ; SI indexes the entry (no [DX]
                mov ax,word ptr curPos  ; on 8086, fix 64): vPos gets
                mov word ptr vPos[si],ax ; row i's line start (64)
                mov ax,word ptr curPos+2
                mov word ptr vPos[si+2],ax
                call RdLine             ; keeps DI on the row start (uses)
                or al,al
                jz @@e
                mov si,bx
                call WrCntRow           ; text + pad the tail (fix 38)
                jmp @@n
@@e:            mov ax,A_CONT or ' '    ; EOF: empty row (fix 46: one
                mov cx,LINEWID          ; row-base reload less per row)
                rep stosw
@@n:            mov di,bp               ; both paths rejoin here: STOSW
                add di,160              ; left DI mid-row (fix 46b)
                add bx,SLOTSZ
                .if (bx >= offset vCache+LINES_VIS*SLOTSZ)
                        mov bx,offset vCache
                .endif
                add dx,4
                .if (dx >= VPOSN*4)
                        xor dx,dx
                .endif
                pop cx
        .untilcxz
        ; vPos entry of the line AFTER the bottom row (the next Down's
        ; fast path): curPos is on it now, DX already points there (64)
        mov si,dx                       ; SI indexes (no [DX] on 8086)
        mov ax,word ptr curPos
        mov word ptr vPos[si],ax
        mov ax,word ptr curPos+2
        mov word ptr vPos[si+2],ax
        mov ax,curLine
        mov vcTop,ax                    ; the cache now holds this view
        mov vcValid,1
        mov wDest,offset lBuf           ; everyone else parses to lBuf
        mov ax,word ptr savPos
        mov dx,word ptr savPos+2
        mov word ptr curPos,ax
        mov word ptr curPos+2,dx
        call SeekSoft
        ret
DrwCnt endp

;------------------------------------------------------------------------------
; DrwBar - scrollbar. The only MUL/DIV left divide by VARIABLES (thumb
; mapping is the exact inverse of the click handler) and run once per
; frame; the *160 offsets use shifts (fix 13) and curLine*(LINES_VIS-1)
; is FastMul 22 (shifts and adds, fix 35).
;------------------------------------------------------------------------------
DrwBar proc uses ax bx cx di
        mov es,vSeg
        mov cx,LINES_VIS
        mov di,160+156
        mov ax,A_SCRL or 0B0h
        .repeat                         ; the rail: one pass per frame (72)
                mov es:[di],ax
                add di,160
        .untilcxz
        mov ax,totLines
        or ax,ax
        jz @@d
        cmp ax,LINES_VIS        ; unsigned: whole file on screen? The
        jbe @@f                 ; signed 1.02 .if failed at the 65.535
        mov ax,curLine          ; saturation point (fix 23)
        FastMul 22              ; DX:AX = curLine*22, no MUL (fix 35)
        mov bx,totLines
        sub bx,LINES_VIS
        jz @@d
        div bx                          ; variable divisor: DIV stays
        .if (ax>=LINES_VIS)
                mov ax,LINES_VIS-1
        .endif
        ; DI = AX*160 without MUL: (AX<<7)+(AX<<5)  (fix 13)
        mov di,ax
        shl di,5                        ; *32
        mov bx,di
        shl bx,2                        ; *128
        add di,bx                       ; *160
        add di,160+156
        mov ax,A_THMB or 0DBh
        mov es:[di],ax
        jmp @@d
@@f:    mov cx,LINES_VIS                ; file fits the window: full thumb
        mov di,160+156
        mov ax,A_THMB or 0DBh
        .repeat
                mov es:[di],ax
                add di,160
        .untilcxz
@@d:    ret
DrwBar endp

;------------------------------------------------------------------------------
; DrwSt - status bar on row 25 (fix 20). Builds stBuf with ES=DS first
; (fix 4), then PaintStat paints it. curLine*100 is FastMul 100 (fix
; 35: was a 26-instruction SHL/RCL chain); only the final DIV by the
; variable totLines remains (fix 13). 1.06 (fix 47): when the horizontal
; window has moved, the column "C<n>" is appended before the key hints.
;------------------------------------------------------------------------------
DrwSt proc uses ax bx cx dx si di
        push ds
        pop es                          ; ES=DS: stBuf is a data buffer
        mov di,offset stBuf
        mov si,offset sLn
        call Cpy
        mov ax,curLine
        inc ax
        call U2A
        mov al,'/'
        stosb
        mov ax,totLines
        .if (!ax && !isFile)            ; STDIN: running total estimate
                mov ax,curLine
                add ax,LINES_VIS
        .endif
        call U2A
        mov ax,'  '
        stosw
        mov ax,totLines
        or ax,ax
        jz @@np
        mov ax,curLine
        FastMul 100                     ; DX:AX = curLine*100 (fix 35)
        mov bx,totLines
        div bx                          ; variable divisor: DIV stays
        call U2A
        mov al,'%'
        stosb
@@np:   .if (hPos)                      ; horizontal window moved (47)
                mov al,'C'
                stosb
                mov al,' '
                stosb
                mov ax,hPos
                inc ax
                call U2A
        .endif
        mov si,offset sKey
        call Cpy
        mov byte ptr [di],0
        call PaintStat
        ret
DrwSt endp

;------------------------------------------------------------------------------
; PaintStat - paint stBuf on row 25: text first, then pad the rest of
; the row (no separate clear, fix 38). (Split out of DrwSt so StatLoad
; can show "Loading ..." with the same look, fix 30.)
;------------------------------------------------------------------------------
PaintStat proc uses ax cx di si
        mov es,vSeg
        mov di,24*160
        mov ax,A_STAT or ' '
        stosw                   ; column 0: 1.03 cleared the whole row, the
        mov si,offset stBuf     ; pad below only reaches what follows the
        mov di,24*160+2         ; text - write the corner explicitly (38)
        mov ah,ATTR_STAT
        call WrTxt
        mov ax,A_STAT or ' '
        mov cx,25*160
        sub cx,di               ; rest of the row in bytes (even)
        shr cx,1
        rep stosw
        ret
PaintStat endp

;------------------------------------------------------------------------------
; AdvRow - advance a row pointer to the next pop-up row. The advance
; 156-2*BP (BP = text width) is recomputed into CX on every use: CX is
; dead or stack-saved at every call site, and the macro reads NO memory
; operand, so it is independent of DS - the save loop runs with DS
; pointing at the VIDEO page (1.04 draft loaded rowAdv from memory there
; and picked up the advance from the screen contents). 1.03's version
; did "mov ax,bp" and destroyed the cell attribute in AH, so the whole
; box below the top border came out black on black (fix 33).
;------------------------------------------------------------------------------
AdvRow  macro reg
        mov cx,156
        sub cx,bp
        sub cx,bp
        add reg,cx
        endm

;------------------------------------------------------------------------------
; PopUp - generic pop-up box: green background, white letters (fix 21),
; double-line border, used by F1 (help) and F10 (about, fix 29). The
; region under the window is saved and put back afterwards, so the view
; is not disturbed and no redraw is needed. The window is centered; its
; corner offset is computed once (popOff) and reused by the save, draw
; and restore passes.
; Input: BX = offset of the line table, CX = line count, DX = text
; width in columns. Waits for a key with ReadKey (BIOS ring at 0040h,
; INT 28h while idle, fixes 25/26). Returns AL=0: no repaint needed.
; BP carries the text width across the subroutines because DS points
; to video while the region is saved.
;------------------------------------------------------------------------------
PopUp proc uses bx cx dx si di bp
        mov bp,dx                       ; BP = text width
        mov popLines,cx
        mov ax,78
        sub ax,bp
        shr ax,1                        ; (80-(w+2))/2
        mov popCol,ax
        mov ax,21
        sub ax,cx
        shr ax,1                        ; (25-(lines+4))/2
        mov popRow,ax
        ; DI = popRow*160 + popCol*2: byte offset of the window corner
        mov di,popRow
        shl di,5                        ; *32
        mov ax,di
        shl ax,2                        ; *128
        add di,ax                       ; *160
        mov ax,popCol
        shl ax,1
        add di,ax
        mov popOff,di
        .if (mPres)
                mov ax,2
                int 33h                 ; hide the mouse over the window
        .endif
        ; save the region under the window (DS=video, ES=data). BP
        ; carries the width and DX the row count; everything read from
        ; the data segment is loaded BEFORE DS is switched to video -
        ; popOff included (1.04 regression: reading it after the switch
        ; fetched the variable from the VIDEO page), and AdvRow must not
        ; touch memory for the same reason.
        mov dx,popLines
        add dx,4                        ; rows = lines + 4
        mov si,popOff
        push es, ds                     ; SMART.INC multi push
        mov ax,vSeg
        mov ds,ax
        mov ax,ss                       ; data segment (COM: SS==DS)
        mov es,ax
        mov di,offset popSave
        .repeat                         ; one row per pass (72)
                mov cx,bp
                add cx,2
                add cx,cx               ; row size in bytes
                BLKCP                   ; widest copy of the build (36)
                AdvRow si
                dec dx
        .untilz
        pop ds
        ; draw the window (ES=video). AH carries ATTR_POP through the
        ; whole draw: nothing clobbers AX any more (fix 33).
        mov ax,vSeg
        mov es,ax
        mov di,popOff
        mov ax,A_POP or 0C9h
        stosw
        mov al,0CDh
        mov cx,bp
        rep stosw
        mov al,0BBh
        stosw
        AdvRow di
        xor si,si                       ; blank row
        call PopLine
        mov cx,popLines                 ; BX still holds the line table
@@ln:   push cx
        mov si,[bx]
        call PopLine
        add bx,2
        pop cx
        loop @@ln
        xor si,si                       ; blank row
        call PopLine
        mov al,0C8h
        stosw
        mov al,0CDh
        mov cx,bp
        rep stosw
        mov al,0BCh
        stosw
        ; wait for any key (BIOS ring, INT 28h while idle)
        call ReadKey
        ; restore the saved region (DS=data, ES=video)
        mov ax,vSeg
        mov es,ax
        mov di,popOff
        mov si,offset popSave
        mov dx,popLines
        add dx,4
        .repeat                         ; one row per pass (72)
                mov cx,bp
                add cx,2
                add cx,cx
                BLKCP
                AdvRow di
                dec dx
        .untilz
        .if (mPres)
                mov ax,1
                int 33h
        .endif
        pop es
        xor al,al                       ; screen unchanged: no redraw
        ret
PopUp endp

;------------------------------------------------------------------------------
; PopLine - one window row: 0BAh + text padded to BP chars + 0BAh.
; DS:SI = ASCIZ line, SI=0 -> blank row. DI = video pointer, advanced
; to the next row. AH is re-armed here so the attribute can never be
; lost to a future helper clobber (fix 33).
;------------------------------------------------------------------------------
PopLine proc
        mov ah,ATTR_POP
        mov al,0BAh
        stosw
        mov cx,bp                       ; text width (passed in BP)
        or si,si
        jz @@pad
@@c:    lodsb
        or al,al
        jz @@pad
        stosw
        loop @@c
        jcxz @@cl                       ; exactly BP chars: row done
@@pad:  mov ax,A_POP or ' '
        rep stosw                       ; the remaining cells in one REP
@@cl:   mov al,0BAh
        stosw
        AdvRow di
        ret
PopLine endp

;------------------------------------------------------------------------------
; Done - close the file and put the screen and the cursor back exactly
; as they were when 4VIEW started (fix 22). When Init forced mode 3
; (fix 71) the user's mode is set back instead of the text-page copy:
; the original page content is unrecoverable either way, the mode set
; at entry already cleared it. The handle is closed only
; when the file was really opened: the open-error path runs Done with
; isFile=1 and hFile=0, and closing handle 0 would kill STDIN (fix 30).
;------------------------------------------------------------------------------
Done proc
        .if (mPres)
                mov ax,2
                int 33h                 ; hide the mouse sprite first
        .endif
        .if (svForced)                  ; the mode was forced at entry (71)
                xor ah,ah               ; put the user back in their mode
                mov al,svMode
                int 10h
        .else
                mov es,vSeg
                mov si,offset svScr
                xor di,di
                mov cx,4000
                BLKCP                   ; original screen back (fix 36)
        .endif
        mov ah,1
        mov cx,svShape
        int 10h                         ; original cursor shape
        mov ah,2
        mov bh,svPage
        mov dx,svCurs
        int 10h                         ; original cursor position
        .if (hFile)
                mov bx,hFile
                mov ah,3Eh
                int 21h
        .endif
        ret
Done endp

;------------------------------------------------------------------------------
; ShowHelp - the help shown without parameters (-h, /?, no file). The
; same helpTab lines the F1 window draws (fix 21). It prints and exits
; WITHOUT waiting for a key (fix 28).
;------------------------------------------------------------------------------
ShowHelp proc
        mov bx,offset helpTab
        mov cx,HLP_N
        .while (cx)
                push cx
                mov si,[bx]
                .while (byte ptr [si])
                        lodsb
                        mov dl,al
                        mov ah,2
                        int 21h
                .endw
                mov dl,13
                mov ah,2
                int 21h
                mov dl,10
                mov ah,2
                int 21h
                add bx,2
                pop cx
                dec cx
        .endw
        ret
ShowHelp endp

;------------------------------------------------------------------------------
Cpy proc
        .while (byte ptr [si])
                lodsb
                stosb
        .endw
        ret
Cpy endp

;------------------------------------------------------------------------------
; U2A - unsigned AX -> decimal ASCIZ at ES:DI. Division by 10 is done
; with shifts and adds (q = ((x>>1)+(x>>2) + corrections) >> 3, exact
; for the whole 16-bit range): on a real 8086 SHL costs ~2 cycles while
; DIV costs ~185 (fix 13). The >>8 step copies AH into AL instead of
; eight one-bit shifts (fix 38).
;------------------------------------------------------------------------------
U2A proc uses bx cx dx si
        mov bx,ax                       ; BX = value
        xor cx,cx                       ; digit count
@@d:    mov ax,bx
        shr ax,1
        mov si,ax
        shr ax,1
        add si,ax                       ; (x>>1)+(x>>2)
        mov ax,si
        shr ax,4
        add si,ax
        mov ax,si
        mov al,ah                       ; AX = SI>>8 without 8 shifts
        xor ah,ah
        add si,ax
        shr si,3                        ; approximate quotient
        mov ax,si
        shl ax,1
        mov dx,ax                       ; 2q
        shl ax,1
        shl ax,1                        ; 8q
        add ax,dx                       ; 10q
        mov dx,ax
        mov ax,bx
        sub ax,dx                       ; remainder candidate
@@c:    cmp ax,10
        jb @@ok
        sub ax,10
        inc si                          ; correct the quotient
        jmp @@c
@@ok:   mov bx,si                       ; quotient for the next digit
        push ax
        inc cx
        mov ax,bx
        or ax,ax
        jnz @@d
@@o:    pop dx
        add dl,'0'
        mov al,dl
        stosb
        loop @@o
        ret
U2A endp

;------------------------------------------------------------------------------
; Data - inside the code segment so "-bin"/COM output is self-contained.
; zStart..zEnd is cleared by Init with a single REP STOSB.
;------------------------------------------------------------------------------
zStart          label byte
hFile           dw 0
mPres           db 0
curPos          dd 0
savPos          dd 0
tmpPos          dd 0
backAmt         dd 0
curLine         dw 0
totLines        dw 0
cCnt            dw 0
hFull           db 0
hByte           db 0
bBase           dd 0
bLen            dw 0
bIdx            dw 0
keyScan         db 0
moved           db 0
hPos            dw 0                    ; horizontal window start (fix 47)
rIdx            dw 0                    ; next ring slot (fixes 50/55)
cntMode         db 0                    ; RdLine consume-only pass (49)
ringView        db 0                    ; ring holds lines 0..22 (55)
vSlot           db 0                    ; view cache: top row's slot (63)
vcTop           dw 0                    ; view cache: top line number (63)
vcValid         db 0                    ; slots hold lines vcTop..+22 (63)
popRow          dw 0
popCol          dw 0
popLines        dw 0
popOff          dw 0            ; pop-up corner offset, reused 3x (fix 33)
zEnd            label byte
isFile          db 0            ; set by ParseCmd: NEVER zeroed by Init
wDest           dw offset lBuf ; RdLine store target (63): pointers,
paintBuf        dw offset rBuf  ; MUST NOT be cleared by Init (fix 63)
vSeg            dw 0B800h       ; Init sets B000h for mono (mode 7)
svPage          db 0
svMode          db 0                    ; video mode at entry (fix 71)
svForced        db 0                    ; Init forced mode 3 (fix 71)
svShape         dw 0
svCurs          dw 0
fName           db 65 dup(0)
lBuf            db SLOTSZ dup(0)       ; one line: LBUFCAP chars + NUL
                                        ; + length byte at 255 (47/66)
stBuf           db 96 dup(0)
bBuf            db BUFSZ dup(0)
cache           dd CACHE_SZ dup(0)
svScr           db 4000 dup(0)          ; saved text page (fix 22)
popSave         db HLP_H*WWIN*2 dup(0)  ; saved region under the pop-ups
rBuf            db RINGN*SLOTSZ dup(0)  ; ring: view #1 / STDIN window (50)
vCache          db LINES_VIS*SLOTSZ dup(0) ; the current view's lines (63)
vPos            dd VPOSN dup(0)          ; line start ring: line j -> j&31 (64)
cBuf            db 0                    ; 1-byte STDIN staging buffer
tBuf            db 128 dup(0)           ; Truename scratch (fix 30)
sSTDIN          db "STDIN",0
if USE386
sHdr1           db "4VIEW386 ",'0'+VERMAJ,".",'0'+VMIN/10,'0'+VMIN mod 10," - ",0
else
sHdr1           db "4VIEW ",'0'+VERMAJ,".",'0'+VMIN/10,'0'+VMIN mod 10," - ",0
endif
sLoad           db "Loading ",0
sDots           db "...",0
sLn             db "Line ",0
sKey            db "   ",24,25,27,26," PgUp PgDn F1=Help F10=About ESC",0
sErr            db "Cannot open file.",13,10,'$'
; help lines: printed by ShowHelp and drawn inside the F1 window (fix 21)
helpTab         dw a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12,a13,a14,a15,a16,a17,a18,a19
if USE386
a1              db "4VIEW386 ",'0'+VERMAJ,".",'0'+VMIN/10,'0'+VMIN mod 10," - text viewer for DOS",0
else
a1              db "4VIEW ",'0'+VERMAJ,".",'0'+VMIN/10,'0'+VMIN mod 10," - text viewer for DOS",0
endif
a2              db "Copyright (c) 2025-2026",0
a3              db "Javier Gutierrez Chamorro (Guti)",0
a4              db 0
a5              db "Keys:",0
a6              db "  Up/Down .. one line up/down",0
a7              db "  PgUp/PgDn  one page up/down",0
a8              db "  Left/Right horizontal scroll",0
a9              db "  Home ..... go to top of file",0
a10             db "  End ...... go to end of file",0
a11             db "  F1 ....... show this help",0
a12             db "  F10 ...... show about box",0
a13             db "  ESC ...... exit 4VIEW",0
a14             db 0
a15             db "Mouse: click scrollbar, wheel or",0
a16             db "  right button scrolls the view",0
a17             db 0
if USE386
a18             db "Usage: 4VIEW386 [file]",0
else
a18             db "Usage: 4VIEW [file]",0
endif
if USE386
a19             db "       TYPE file | 4VIEW386",0
else
a19             db "       TYPE file | 4VIEW",0
endif
; about lines: drawn inside the F10 window (fix 29). @Date/@Time are
; stamped by ASMC at assembly time; the quotes are added around their
; expansion so the parser accepts the date slashes and time colons.
BUILD_DATE      catstr <">,@Date,<">
BUILD_TIME      catstr <">,@Time,<">
AV              = __ASMC__              ; real ASMC version (e.g. 240)
aboutTab        dw b1,b2,b3,b4,b5,b6,b7
if USE386
b1              db "4VIEW386 ",'0'+VERMAJ,".",'0'+VMIN/10,'0'+VMIN mod 10,0
else
b1              db "4VIEW ",'0'+VERMAJ,".",'0'+VMIN/10,'0'+VMIN mod 10,0
endif
b2              db "Copyright (c) 2025-2026",0
b3              db "Javier Gutierrez Chamorro (Guti)",0
b4              db "Built ",BUILD_DATE," ",BUILD_TIME,0
if USE386
b5              db "Target: 386+",0
else
b5              db "Target: 8088/8086",0
endif
b6              db "Assembler: ASMC ",'0'+AV/100,".",'0'+(AV mod 100)/10,'0'+AV mod 10,0
b7              db "Free to use, modify and distribute.",0
end