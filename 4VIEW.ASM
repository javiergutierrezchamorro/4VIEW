;------------------------------------------------------------------------------
; 4VIEW 1.19 - Turbo Vision style text viewer for DOS (ASMC)
; (c) 2025-2026 Javier Gutierrez Chamorro (Guti)
; Revision 1.19 fixes (built on top of the 1.18 source - fixes 109-114
; are all still in; see 115-116 at the end of this header): the
; assembler itself now emits the final ~6 KB COM in ONE step, no
; truncation script - the ten bulk buffers became pure offset equates
; into the RAM DOS gives a COM beyond its image (fix 115), so the
; 35.297 zero bytes a plain "ASMC -bin" run used to pad after the
; marker (the "ASMC gives me 40K" report) are gone from the FILE, and
; every offset, every code byte and the whole behavior are the ones
; 1.18 had - the only byte that changes in the image is the stamp's
; version digit.
;
; Revision 1.18 fixes (from a full read of the source; see fixes 109-114 at
; the end of this header): the mouse wheel/right button decoding, the line
; skipped by the first Down after loading, the INT 10h blink call, FillBuf
; read errors and two small trims.
;
; Revision 1.17 fixes the two regressions 1.15 shipped plus an old
; 386-only bug the emulation work surfaced:
;  - the load hang: fix 101 dropped FillBuf's "push ax / pop ax" with
;    the wrong argument - the pair protected the DOS read count from
;    FillBuf's OWN "mov ax,progSize", not from ShowProg (whose "uses
;    ax" covers it). With the count destroyed, RdLine's refill path
;    (EOF test = FillBuf's AX) never saw 0 at end of file and the
;    load pass refilled forever: every file hung at startup (fix 106).
;  - the 386 EOF contract: the SWAR rounds (fix 79) leave GARBAGE in
;    DX, and the refill-EOF exit tested that garbage as the "line
;    ended" flag - RdLine returned AL=1 at a true EOF on the -3 build:
;    a phantom line after the last one, a painted row past the end
;    (the broken status bar on PgDn) and GoLine's End walk grinding
;    on at EOF with a DOS call per line (the "386 hangs scrolling
;    down" report). Fixed at the exit: dx=0 is forced there (107).
; 1.15's real work all stays: WrCntRow paints from the slot's length
; byte (fix 99), the scroll cache is a ring (fix 100), the STDIN Home
; anchor math is folded (fix 102), SMART.INC v2.43 folds the eight
; shift macro bodies (fix 103), and the UASM builds emit genuine
; 8086 encodings (fix 105).
;
; Assemble with ASMC (flat COM, single segment) - the COM comes out
; at its FINAL size (~6 KB) in this one step, fix 115: the bulk
; buffers are offsets into the RAM beyond the image, so there is no
; dup(?) tail to cut any more:
;     ASMC -bin -Fo 4VIEW.COM 4VIEW.ASM          (8088/8086, default)
; 386+ build (immediate shifts + 32-bit string ops; the title bar and
; About say "4VIEW386", fix 68):
;     ASMC -3 -bin -Fo 4VIEW386.COM 4VIEW.ASM
; (with JWasm the equivalents are: JWASM -bin -Fo=4VIEW.COM 4VIEW.ASM and
;  JWASM -3 -bin -Fo=4VIEW386.COM 4VIEW.ASM; SMART.INC v2.43 must be next
;  to 4VIEW.ASM or on the include path)
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
;     saved-screen restore: the mode set at entry already cleared
;     the original page, there is nothing left to put back.
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
; 74. DRY PASS: the two repeated slot patterns are now macros:
;     SLOTPTR reg,base,slot (the AH/AL slot*256 addressing, 8 sites:
;     RingAppend, RingPaint, DrwCnt, DrwUp1, DrwDn1 hot/cold/STDIN,
;     same or fewer instructions than the code it replaces) and
;     VPSTORE reg (the 32-bit curPos store into the vPos ring,
;     6 sites), both emitting exactly the instructions they replace.
;     The U2A quotient-correction loop is a .while, and the
;     scrollbar click drops a redundant totLines==0 test (the
;     unsigned <= LINES_VIS branch right after it already covers it).
; 75. STDIN GOES THROUGH THE BUFFER: hFile is 0 in pipe mode and
;     handle 0 IS the pipe, so the 16 KiB engine (FillBuf/GetByte)
;     now serves streams too. 1.00 paid one DOS call per byte here
;     (the exact problem fix 6 solved for files - a 385 KB pipe
;     meant 385.063 calls) and parsed byte per byte through
;     @@slowin; now it is 24 calls and the LODSW scanners do the
;     parsing. The ioctl check (fix 5) already guarantees handle 0
;     is never the keyboard, so the bulk read can never block on
;     console input. cBuf is gone.
; 76. GOLINE IN COUNT MODE: the End key and the scrollbar jumps
;     walk the file in consume-only mode (cntMode=1): the ~22
;     cycles/byte unrolled scanner replaces the ~44.5 store scanner,
;     since only the line starts are needed - the walk is ~2x
;     faster on big files.
; 77. ZERO-LATENCY KEY LOOP: the BIOS ring is checked FIRST, before
;     INT 28h and the mouse poll - a key that arrived while the
;     previous one was being handled (held keys, auto-repeat) is
;     picked up with no idle call in between; INT 28h and INT 33h
;     run only while really idle.
;
; Revision 1.11 fixes:
; 78. THE STATUS BAR CORRUPTED ITSELF PART-WAY THROUGH THE FILE (the
;     "n option)553/2803 19%on)" screenshot): the cold fills of DrwCnt
;     and DrwDn1 divided curLine by 23 and passed SLOTPTR the QUOTIENT
;     in AL instead of the remainder in DL. Row 0's slot cursor started
;     (curLine/23)*256 bytes late, and the per-row wrap check runs only
;     AFTER a row is parsed - so from curLine 552 on (quotient 24: the
;     data layout puts vPos+tBuf exactly 256 bytes past vCache) row 0
;     parsed the view's TOP line, text and NUL, 256 bytes past the
;     vCache end: straight onto sLn/sKey. sLn read "n option)" (the
;     tail of the '; CF=1 -> ... unknown option' comment line visible
;     on screen) and the same NUL cut sKey to "on)". DS=CS, so the
;     smashed constants stayed broken until the program was reloaded.
;     Both sites now pass DL: the fill mapping (line j -> slot j mod
;     23) matches RingPaint/DrwUp1/DrwDn1's read mapping again and no
;     parse can land outside vCache for any curLine.
; 79. 386 COUNT SCAN GOES LODSD+SWAR: the -3 build now eats FOUR bytes
;     per iteration. cand = (v^0A0A0A0Ah)&(v^0D0D0D0Dh) has a zero byte
;     exactly when a data byte lies in 08h..0Fh (a superset of CR/LF:
;     no false negatives), located with the classic (cand-01010101h)&
;     ~cand&80808080h; a hit re-scans those four bytes with the exact
;     @@cr4/@@lfx handlers (TAB/VT/FF only cost the re-scan). ~7.5
;     instead of ~10.6 cycles/byte: the 385 KB pre-scan drops ~30% on a
;     386DX-25. The 8086 keeps the 8-byte LODSW unroll (fix 67) with
;     byte-identical code.
; 80. 386 STORE SCAN GOES LODSD+STOSD: a dword without CR/LF stores its
;     4 characters with ONE STOSD (~10.5 instead of ~23 cycles/byte) -
;     the parse that PgDn/PgUp and the no-cache repaints pay 23 times
;     per page. Candidate dwords re-scan byte per byte into the shared
;     @@stc/@@stl exits; the 0-3 residue bytes re-round through
;     @@sloop. 8086 code unchanged.
; 81. MOUSE POLL THROTTLE: the idle loop polled INT 33h AX=3 (100-1000+
;     cycles per call, driver-dependent) on EVERY pass; a press lasts
;     >= 50 ms and the loop runs thousands of passes in that time, so
;     polling 1 of 8 passes loses nothing and the idle round costs
;     ~22% less on an 8088. The scrollbar drag loop keeps polling
;     every pass (the button state is needed instantly there).
; 82. Version 1.11.
;
; Revision 1.12 fixes:
; 83. THE 386 STORE SCANNER WROTE ITS RE-SCAN ONE DWORD EARLY: @@swh,
;     the SWAR candidate re-scan of the LODSD store loop (fix 80),
;     kept a copy-pasted "sub di,4" from the count scan's re-scan - but
;     the candidate dword was never stored, so DI already pointed at
;     its store position. Every dword containing a byte in 08h..0Fh (a
;     TAB included) stored its four characters one dword early: the
;     line shifted left four chars per candidate, the writes could run
;     below the slot start (into fName and the previous slot, its
;     length byte included) and the length byte at [wDest+255] could
;     wrap to 0FDh-0FFh. The instruction is deleted: only SI goes back
;     four; DI never moved.
; 84. THE COUNT SCANNER ENTERED ITS LOOP WITH GARBAGE IN AX (the
;     scroll-down hang): @@full's contract is "AX = bytes left in the
;     block", but the fast-path entry (or bp,bp / jnz @@full) jumped
;     there without setting AX - a leftover from fix 76, when GoLine
;     started walking files in count mode. CountLines usually got away
;     with it (its AX holds the curPos high word, 0-7 for files under
;     512 KiB, and the 8086 shr cx,3 masked the mess), but GoLine
;     passes the curPos LOW word: at a line straddling the 16 KiB
;     block edge the scanner ran past the block end BX through the
;     whole segment - on the 386 shr cx,2 turned that into up to a
;     64 KiB runaway (the reported freeze on End and scrollbar jumps),
;     and the 8086 has walked wrong since fix 76 as well. Two
;     instructions, once per line, fix it: AX = BX-SI before the jump.
; 85. rBuf AND vCache MERGED INTO ONE 46-SLOT BUFFER: both were 256-
;     byte slots with the same "line j lives in slot j mod 23"
;     discipline, so the COM keeps its size and one buffer now serves
;     both masters - file mode paints slots 0..22 as the view cache
;     (all the mod-23 logic is untouched), STDIN uses all 46 slots as
;     a ring: 23 LINES OF SCROLLBACK, so Up/PgUp/wheel-up/Home work on
;     a pipe (zero I/O: the lines are already in memory; ScrDn reads
;     the pipe only when the view really reaches the read frontier,
;     so Down after Up consumes nothing; Home lands on the oldest
;     held line). CountLines captures lines 0..22 straight into the
;     slots (the RingAppend copy pass and the proc are gone) and
;     records vPos entries 0..23, so the FIRST Down is hot too.
;     ringView/paintBuf/rBuf are deleted; RingPaint is driven by ringN
;     (23 file / 46 STDIN, set once by Init).
; 86. PROGRESS BAR: the status bar shows a 20-cell bar (columns 58..77)
;     while CountLines pre-scans the file. Init sizes the file with
;     one seek-to-EOF and rewinds, ShowProg paints filled =
;     curPos*20/size with both values normalized by the same right
;     shift (no 16-bit overflow at any size), FillBuf repaints it once
;     per 16 KiB block - 24 repaints on a 385 KB file, ~80 cycles each
;     - and CountLines retires the bar. The "Loading <name>..." text
;     is clamped so it always ends before the bar.
; 87. THE 386 BUILD NO LONGER EMITS THE 8086-ONLY SCANNER: the 8-byte
;     LODSW unroll (@@f8..@@next, fix 67) and its @@candlo/@@candhi/
;     @@crlo/@@clok/@@lflo candidate handlers sat after the `else` of
;     fix 79's if USE386 and were assembled unreferenced on -3. Both
;     halves now live inside their own branch: the -3 COM shrinks and
;     the 8086 object is byte-identical.
; 88. Version 1.12.
; 89. DIAG386 DIAGNOSTIC SWITCH (fix 89, no behavior change at the
;     default 0): the 1.12 scanners, the 16 KiB block-edge handling
;     and the complete vPos/cache state machine of the scroll-down
;     path verify clean in a byte-faithful machine simulation (store
;     and count scanners, block straddles, unget byte, EOF edges, and
;     thousands of consecutive Downs over multi-block files), so the
;     DOSBox freeze of the -3 build cannot be reproduced at the
;     algorithm level and gets bisected on the 386-only code instead:
;     -DDIAG386=1 runs the 8086 scanner halves on -3 (LODSD/SWAR off),
;     -DDIAG386=2 also reverts the REP MOVSD/STOSD and MOVZX forms,
;     leaving code paths identical to the 8086 build. The title and
;     About append "d1"/"d2". Version stays 1.12 (no bug was found
;     in the logic; the switch is an instrument, not a fix).
; Revision 1.13 fixes:
; 90. THE -3 BUILD'S FREEZE AND ITS CRAZY PERCENTAGES: root cause
;     found, and it was NOT 4VIEW. SMART.INC v2.4's FastMul 386+ path
;     emits "movzx eax,ax / imul edx,eax,f": the full product lands in
;     EDX (DX = its LOW word) and AX stays the multiplicand, while the
;     macro's contract is DX:AX = AX*f with DX = the HIGH word. Every
;     repaint divided that broken pair: DrwSt printed percents like
;     "50247%" from the first scroll and its DIV overflowed (the
;     freeze: DOS aborts on INT 0 and the screen stays frozen) once
;     curLine*100 crossed totLines - the 2nd/3rd PgDn on small files,
;     a few dozen held-Down lines on bigger ones; DrwBar died the
;     same way a bit later. The 8086 paths are v2.3's and always
;     right, hence "the 8086 works perfectly". The 1.12 simulation of
;     the viewer's logic was clean all along; fixes 83/84 were real
;     but secondary. THE FIX (now in 1.14, see fix 92): SMART.INC
;     v2.42 repairs the macro with SHLD and both call sites call it
;     unconditionally - 1.13's own inline "movzx eax,ax /
;     imul eax,eax,f" was INCOMPLETE: it fixed AX but never wrote
;     DX, so the garbage pair (and the crazy percentages, now fed by
;     DrwBar's division remainder) survived it.
; 91. Version 1.13.
;
; Revision 1.14 fixes:
; 92. FIX 90 WAS INCOMPLETE - THE -3 BUILD KEPT THE CRAZY PERCENTAGES
;     (plus a wrong scrollbar thumb): "movzx eax,ax / imul
;     eax,eax,f" leaves the product in EAX, of which only AX (the
;     low word) reaches the following 16-bit DIV - DX is a DIFFERENT
;     register and was never written (the fix 90 comment read EAX's
;     internal AH:AL halves as if they were the AX:DX pair; the
;     disassembly of the 1.13 -3 build shows both call sites going
;     imul -> mov bx,totLines -> div with no DX write in between).
;     DrwSt therefore divided (garbage<<16)|low16(curLine*100), and
;     its garbage was DrwBar's own broken division REMAINDER (0..
;     totLines-23): the percent reached ~65.000 instead of the v2.4
;     INT 0 freeze - crazy but no longer fatal; DrwBar's thumb rode
;     curPos' high word. THE FIX: SMART.INC v2.42 completes the
;     macro repair (both 386 paths end with "shld edx,eax,16", so
;     DX really carries the high word; factor 1 collapses to "xor
;     dx,dx"), and both call sites drop the if USE386/else/endif
;     and call FastMul unconditionally again - one source of truth,
;     verified by the new battery (every 16-bit multiplicand x the
;     factor set, comparing the DX:AX PAIR, plus a disassembly check
;     of the emitted bytes). The 8086 paths were always right and
;     stay untouched.
; 93. TWO LATENT SIGNED-COMPARE BUGS (ASMC's .if is SIGNED like
;     MASM's - fixes 23/31 already knew and hand-coded cmp/jae
;     elsewhere; UASM's happens to be unsigned, so the ASMC-shipped
;     and UASM-verified binaries even disagreed on these two):
;     a) WrCntRow tested the line length with ".if (al <= byte ptr
;        hPos)" - a length of 128..254 reads NEGATIVE as a signed
;        byte, so every line longer than 127 chars padded its whole
;        row BLANK at any hPos, 0 included (fix 66's own comment
;        says the low byte decides, but the compare never got the
;        unsigned treatment). Now a hand-coded cmp al,byte ptr
;        hPos / jbe.
;     b) CountLines gated the view capture with ".if (totLines <
;        LINES_VIS)" - a totLines of 32.784+ is negative signed, so
;        the capture ran for EVERY line: SLOTPTR indexed slot bl (up
;        to 255) far past vCache's 46 slots, VPSTORE wrote
;        vPos[totLines*4] wrapping into bBuf, the line TEXT went to
;        that wild wDest, and the scan stayed in the 2x slower store
;        mode (cntMode is set by the == LINES_VIS elseif, which can
;        never fire once totLines is past it). Files under 32.784
;        lines were never affected. Both tests are now cmp/jae
;        unsigned.
; 94. DIAG386 RETIRED: the bisect switch (fix 89) did its job - the
;     freeze root cause is known (fix 90, completed by fix 92) and
;     the instrument is dead weight. SWAP386/WIDE386 collapse into
;     USE386 (they both equal it at DIAG386=0, so the binaries are
;     unchanged), the -DDIAG386 builds, their title/About strings
;     and the 25-line header block are gone.
; 95. RINGPAINT'S WRAP LIMIT IS LOOP-INVARIANT: the per-row slot
;     check recomputed ringN*256+vCache with "mov ax,ringN / shl
;     ax,8" - EIGHT macro-expanded 1-bit shifts on an 8086 - 23
;     times per repaint. The limit is computed once before the loop
;     into DX (free: WrCntRow never touches it), ~250 instructions
;     less per full repaint on the 8086.
; 96. BRANCHLESS vPos WRAP: "add dx,4 / .if (dx >= VPOSN*4) xor
;     dx,dx" becomes "add dx,4 / and dx,7Fh" in DrwCnt and DrwDn1's
;     cold fill - the entries are multiples of 4 in 0..124, so the
;     AND wraps 128 to 0 exactly like the branch did, one
;     instruction less per row and no compare.
; 97. THE COM FILE STOPS CARRYING ~35 KB OF ZEROS: fName/lBuf/stBuf/
;     bBuf/cache/svScr/popSave/vCache/vPos/tBuf move to a dup(?)
;     tail behind the FILEEND marker, and the shipped COMs are cut
;     right after it: ~41 KB -> ~6 KB, seven times fewer bytes to
;     load from a floppy (the fix 85/87 size ethos). The assembler
;     itself pads the emitted file with zeros up to the last
;     declared item (ASMC's bin writer only skips WHOLE BSS segments
;     and this is a single-segment COM), so the cut is the second
;     step: search the file for "<4VIEW14>" and truncate right
;     after it - the marker is the last initialized byte. Nothing
;     breaks if the step is skipped: the zeros are just ballast. A
;     write-before-read audit per buffer says only vCache's zeros
;     are load-bearing (the EOF rows of short files, STDIN slots
;     below the first fill, ring slots beyond a short pipe must
;     paint blank), so Init now clears it once with BLKFIL;
;     everything else is written before it is ever read.
; 98. Version 1.14 (needs SMART.INC v2.42).

; Revision 1.15 fixes:
; 99. WrCntRow PAINTS FROM THE LENGTH BYTE - the per-character NUL
;     probes leave the loop. The slot's byte 255 (fix 66) is written
;     by every RdLine exit, so avail = len - hPos is exactly the
;     number of REAL chars the window can show: a full row (avail >
;     LINEWID) paints 38 unrolled pairs plus the 77th char with FIVE
;     instructions per pair instead of nine (no lodsb/or/jz chain),
;     a short row paints its avail chars and pads the rest with one
;     REP STOSW (the pad count waits on the stack while LODSB runs),
;     and the NUL position is never read at all - the 1.14 exit zoo
;     (@@o1/@@o2/@@o3 and their pad arithmetic) is gone. About a
;     fifth less time inside the paint loop on an 8088, and one
;     third fewer instructions; the painted cells are identical for
;     every (len, hPos, content) combination - proven exhaustively
;     by scripts/sim_wrcntrow.py on both builds.
; 100. THE SCROLL CACHE IS A RING: the old linear buffer shifted
;     (CACHE_SZ-1)*4 = 180 bytes on EVERY CachePos once full - and
;     the GoLine/End walks call it once per line, so an 8088 walking
;     to the end of a 10.000-line file paid ~2.400 cycles per line
;     for the shift alone, more than double RdLine's consume scan.
;     cHead (the next write slot) turns the drop-oldest shift into
;     one overwrite: the most recent entry is always cHead-1, ScrUp
;     pops by decrementing cHead (the wrap is a single AND), and
;     writing after pops refills the popped slots top-down (LIFO -
;     a Down right after an Up re-pushes the same value). CACHE_SZ
;     grows 48 -> 64 (branchless mask, +64 BSS bytes inside the
;     dup(?) tail: the COM does not grow) and the fast-path Up chain
;     is 64 deep now.
; 101. TWO REDUNDANT REGISTER SAVES RETIRED (a third, FillBuf's AX
;     pair, was wrongly retired with them - the misreading is fixed
;     and documented in 106): the PgDn loop pushed CX around ScrDn
;     although ScrDn - unlike ScrUp, whose SeekSoft can fall into
;     the CX-clobbering Seek - never touches CX; and GoLine's walk
;     pushed CX although both callees preserve it (RdLine via uses,
;     CachePos never loaded it - and the ring leaves it with no
;     string op at all).
; 102. STDIN HOME'S OLDEST-LINE MATH: cmp RSLOTS/jbe/sub/jmp/xor
;     collapses to sub RSLOTS/jae/xor - the borrow IS the "fewer
;     than 46 lines held" case. Two instructions and a label less,
;     same anchor as ScrUp's.
; 103. SMART.INC v2.43: the eight 8086 shift macros each repeated
;     the same 15-line body and differed only in the emitted
;     instruction - the body now lives once in the internal __SHx
;     helper and every macro is a two-line wrapper (SAL keeps its
;     own ??sal; it encodes as SHL anyway). Expansions are
;     byte-identical to v2.42 on the full 8086 battery; only the
;     negative-count error text became uniform.
; 104. Version 1.15 (needs SMART.INC v2.43); the COM cut marker is
;     "<4VIEW15>".
; 105. THE SHIPPED "8086" COMS WERE NOT: UASM's instruction table
;     tags the group-1 rows that emit opcode 83 (reg/mem,imm8 - a
;     80186-only form, introduced with the 186) with P_86, so every
;     UASM-assembled .8086 binary silently carried 186-only code -
;     77 sites in the 1.14 COM (cmp/add/sub/and with immediates in
;     Main, RdLine, DrwCnt, U2A...). On a real 8088/8086 those bytes
;     decode as garbage; ASMC, the reference toolchain, is CPU-
;     strict and always emitted the legal 05/81 wide forms, which is
;     why the sources were never wrong - only the convenience COMs
;     of the 1.11-1.14 rounds were. THE FIX lives in the verifier
;     (scripts/uasm8086_83fix.patch): the two table rows become
;     P_186 and the codegen table walk now skips entries whose
;     minimum CPU exceeds the current one, so .8086 falls through to
;     the 80/81 encodings (the AX short forms return too). The -3
;     target keeps opcode 83 (legal there) and rebuilds byte-
;     identical modulo the build stamp; the 8086 COM contains ZERO
;     opcode-83 bytes now, at ~53 bytes more (the wide immediates).
;     This round's other diffs were re-verified on the fixed build.
; 106. THE LOAD HANG, OR: FIX 101 MISREAD FILLBUF'S PUSH. RdLine's
;     refill path is "call FillBuf / or ax,ax / jz @@eof" - the DOS
;     read count IS FillBuf's return value and 0 means EOF. The
;     push/pop around the progress-bar call never guarded AX against
;     ShowProg (its "uses ax" does that); it guarded the count
;     against FillBuf's own "mov ax,progSize" two lines below. With
;     the pair gone, FillBuf returned progSize's low word: at a real
;     EOF the DOS read returns AX=0, but the test compared progSize
;     - nonzero for every file - so the scanner refilled forever and
;     4VIEW hung during the load. STDIN truncated instead: progSize
;     is 0 there, so every refill looked like EOF and pipes died at
;     the first 16 KiB block. The push/pop is back, byte-for-byte
;     the 1.14 pair; the other two fix-101 saves (PgDn's CX, GoLine's
;     CX) were re-audited call tree by call tree and stand. The
;     other 1.15 fixes re-verified: WrCntRow simulator 10.680 cases
;     0 failures, ring-cache simulator 3.000 walks OK, SMART.INC
;     batteries byte-identical.
; 107. THE 386 EOF CONTRACT, OR: FIX 79 FORGOT DX. RdLine's exit
;     reason lives in DX (0 = EOF, 1 = EOL) and the shared @@dones
;     epilogue decides AL from it. The 386 SWAR rounds (fix 79) run
;     their candidate test THROUGH DX - "mov edx,eax / ... / not
;     edx / and eax,edx" - and the no-candidate path (jz @@fwn)
;     leaves SWAR garbage in DX. The 8086 rounds only touch AL/AH,
;     so the contract survived there. On -3, a refill that lands on
;     EOF right after a SWAR round reached @@eof with DX != 0: the
;     epilogue reported "line read" (AL=1) at a true EOF. Three
;     symptoms: CountLines counted a phantom line after the last
;     one; DrwCnt painted a row past the end instead of clearing it
;     (the corrupted status-bar rows on PgDn); and GoLine's End/
;     scrollbar walk - ".break .if (!al)" - kept going at EOF, one
;     CachePos + RdLine + DOS read per remaining line, up to 65.535
;     bogus iterations: the "386 se cuelga al hacer scroll" hang.
;     Fix 84 (1.14) had repaired the sibling AX contract of the
;     same resume path but missed DX. THE FIX lives in the refill's
;     EOF branch: "jnz @@rfin / xor dx,dx / jmp @@dones" - the EOF
;     arrival forces its exit reason to 0 and skips the dead label;
;     every EOL exit keeps writing dx=1 itself. 2 bytes more on both
;     builds, and the first attempt (an xor AT the @@eof label) was
;     wrong - @@donef falls through it and every EOL exit would have
;     reported EOF; the Unicorn harness caught it immediately. Found by the
;     Unicorn harness (scripts/emu_hang.py): the 386 counted 386
;     lines where the 8086 and the reference count 385; after the
;     fix both builds agree on every line boundary.
; 108. Version 1.17 (still SMART.INC v2.43); the COM cut marker was "<4VIEW17>".
; 109. MOUSE: MousePoll used TESTFLAG with MASKS (6/4/2) but SMART.INC's
;     TESTFLAG takes a BIT INDEX: "testflag bl,6" tested bit 6 (40h),
;     "testflag bl,4" bit 4 (10h) and "testflag bl,2" bit 2 (04h = the MIDDLE
;     button). Net effect: wheel up (middle) scrolled DOWN, the plain right
;     button did nothing. Now plain TEST with the real masks: middle+right
;     (BL and 6 = 6) = wheel down, middle alone = wheel up, right alone =
;     one line down, bit 0 = left click.
; 110. CountLines recorded vPos entry 23 AFTER reading line 23, i.e. the
;     start of line 24: the first Down after loading painted line 24 where
;     line 23 belongs and left the view cache inconsistent. It is recorded
;     right after line 22 is captured (curPos = start of line 23) and
;     count-only mode starts one line earlier too (line 23 is no longer
;     parsed in store mode for nothing).
; 111. Init: "INT 10h AX=1103h BX=1" is SET BLOCK SPECIFIER (font maps), not the
;     blink switch. AX=1003h BL=1 (toggle intensity/blink: blink) is what
;     fix 70 meant. A VGA that honors 1103h with BL=1 maps attribute-bit-3-
;     clear text to an empty font block.
; 112. FillBuf: with CF=1 after AH=3Fh AX holds an error code, which was
;     stored as the byte count; now an error reads as EOF (AX=0).
; 113. Cpy copies the NUL with the data and backs DI onto it (4 instructions
;     per char instead of CMP [SI],0 + JZ + LODSB + STOSB + JMP); CpyN on
;     the 8086 build loses a dead PUSH AX / MOV AX,CX / POP AX.
; 114. Version 1.18; the COM cut marker is "<4VIEW18>" (update the script
;     that truncates the COM at the marker).
;
; Revision 1.19 fixes:
; 115. THE ASSEMBLER ITSELF NOW EMITS THE ~6 KB COM. Fix 97 moved the
;      ten bulk buffers (fName/lBuf/stBuf/bBuf/cache/svScr/popSave/
;      vCache/vPos/tBuf, 35.297 bytes) to a dup(?) tail behind the
;      FILEEND marker and cut the SHIPPED COMs right after it - but a
;      plain "ASMC -bin" run pads the single-segment image with zeros
;      up to the LAST DECLARED ITEM, so an uncut build is 41 KB of
;      which 35.297 are ballast zeros (the "a ti el .COM te da 5K y
;      ASMC me da 40K" report): the cut was a second, manual build
;      step the source did not perform. The ten buffers are now pure
;      offset EQUates into the RAM DOS gives a COM beyond its image -
;      exactly where the cut COM already kept them at runtime (same
;      footprint, same write-before-read audit, vCache still cleared
;      by Init) - so there is NO declared item after the stamp any
;      more: ASMC, JWasm and LINK16 /TINY all emit the final-size COM
;      in one step and the stamp is just a version marker now. The
;      equate chain reproduces the dup(?) offsets byte for byte (no
;      alignment changes), so both builds come out IDENTICAL to 1.18
;      except the stamp's version digit - verified on ASMC 2.41 and
;      UASM 2.57 (8086 and -3) by image comparison.
; 116. Version 1.19 (needs SMART.INC v2.43); the image stamp is
;      "<4VIEW19>".
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

;------------------------------------------------------------------------------
; 386-only parts below are selected by USE386 alone: the DIAG386
; bisect switch of fixes 89-90 retired in fix 94 once the freeze's
; root cause was found (SWAP386/WIDE386 both equalled USE386 at the
; default DIAG386=0, so the binaries are unchanged).
;------------------------------------------------------------------------------

include smart.inc               ; shl/shr imm, movzx, FastMul, push/pop
                                ; multi, setflag/testflag (Guti, v2.43).
                                ; Include AFTER the CPU is selected: @Cpu is read
                                ; here (8086: shifts expand 1 bit at a
                                ; time, MOVZX/MOVSX are emulated; -3: the
                                ; native forms pass straight through).

.code
org 100h

VERMAJ      equ 1                       ; product version 1.19
VMIN        equ 19
LINES_VIS   equ 23                      ; content rows 1..23 (title row 0,
                                        ; status row 24)
CACHE_SZ    equ 64                      ; scroll cache entries - a ring of
CACHE_MSK   equ CACHE_SZ-1              ; line starts since fix 100 (48
                                        ; were linear and shifted 180
                                        ; bytes per CachePos once full)
BUFSZ       equ 16384                   ; 16 KiB: 24 reads per 385 KB (fix 42)
LINEWID     equ 77                      ; painted columns of a line
LBUFCAP     equ 254                     ; chars kept per line: the 256-byte
                                        ; slot is chars + NUL + the line's
                                        ; length byte at 255 (fix 66)
HPOSMAX     equ LBUFCAP-LINEWID         ; last useful horizontal window
                                        ; (177 < 256: WrCntRow compares
                                        ; hPos's low byte, fix 66)
RSLOTS      equ 46                      ; merged view-buffer slots (85):
                                        ; slots 0..22 are the file view
                                        ; cache, all 46 form the STDIN
                                        ; scrollback ring (23 lines back)
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
; SLOTPTR reg, base, slot - reg = base + slot*256: the 256-byte slots
; (fix 63) are addressed with the AH/AL trick (the 8086 has no shl ax,8):
; the slot index goes to AH, AL is cleared and one ADD does the rest.
; base is an offset expression (offset vCache); slot is the 8-bit slot
; source (vSlot, AL, BL, DL). Clobbers AX, destroys flags.
;------------------------------------------------------------------------------
SLOTPTR macro reg, base, slot
        mov ah,slot
        xor al,al                       ; AX = slot*256
        mov reg,base
        add reg,ax
        endm

;------------------------------------------------------------------------------
; VPSTORE reg - record the current line's start (curPos, 32-bit) in the
; vPos ring entry at byte offset reg (fix 64). Clobbers AX.
;------------------------------------------------------------------------------
VPSTORE macro reg
        mov ax,word ptr curPos
        mov word ptr vPos[reg],ax
        mov ax,word ptr curPos+2
        mov word ptr vPos[reg+2],ax
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
                testflag dl,7           ; BIT 7 (ISDEV): a device (CON, NUL...)
                jz @@dostdin            ; clear: a file or a pipe -> view STDIN
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
        xor ax,ax
        rep stosb
        ; vCache is the one bulk buffer whose zeros are load-bearing
        ; (fix 97): the EOF rows of short files, STDIN slots below the
        ; first fill and ring slots beyond a short pipe must paint as
        ; blank. The rest of the bulk data (fix 97) is write-before-
        ; read and lives past the image (fix 115), so the COM file
        ; carries none of it
        mov di,offset vCache
        mov cx,RSLOTS*SLOTSZ
        BLKFIL                          ; AX = 0 here: the wide clear

        ; the merged view buffer (fix 85): file mode paints slots 0..22
        ; (the mod-23 view cache), STDIN turns all 46 slots into its
        ; scrollback ring
        .if (isFile)
                mov ringN,LINES_VIS
        .else
                mov ringN,RSLOTS
        .endif

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
        ; cyan. AX=1003h BX=0001h re-enables it on EGA/VGA; the PC/XT
        ; BIOSes range-check AH and IRET on 10h+, so it is a no-op on
        ; CGA/MDA machines (where nothing could have disabled it).
        mov ax,1003h                    ; AH=10h AL=03h: intensity/blink
        mov bx,0001h                    ; BL=1: blink ON (fix 111; 1103h was
        int 10h                         ; "set block specifier")

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
                ; progress bar (fix 86): size the file with one
                ; seek-to-EOF and rewind to BOF (the fresh-open state
                ; has bBase=0 and a zero DOS pointer: the invariant
                ; holds, FillBuf reads from 0)
                mov bx,ax
                xor cx,cx
                xor dx,dx
                mov ax,4202h
                int 21h
                mov word ptr progSize,ax
                mov word ptr progSize+2,dx
                xor cx,cx
                xor dx,dx
                mov ax,4200h
                int 21h
                call FullPath           ; fName = fully qualified path
                call DrwHdr             ; title now shows the full path
                mov si,offset fName
                call StatLoad           ; "Loading <full path>..." (fix 30)
                call ShowProg           ; empty bar: the scan starts (86)
                call CountLines         ; also captures view #1 (fixes 55/85)
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
        shr cx,1
        rep movsw
        jnc @F
        movsb                   ; odd length: the last byte
@@:
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
                                        ; chrome procs leave ES=vSeg!).
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
        .if (di > offset stBuf+54)     ; clamp the name (fix 86): the
                mov di,offset stBuf+54 ; text must end before the bar
        .endif
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
; ShowProg - progress bar (fix 86): 20 cells on columns 58..77 of the
; status bar, filled = curPos*20/progSize. progSize and curPos are
; normalized by the same right shift first (size>>SI, pos>>SI), so the
; 16-bit MUL/DIV cannot overflow at any file size up to 4 GiB-1 and
; the quotient still lands in 0..20. Painted empty by Init when the
; load starts and by every FillBuf while the pre-scan runs - one
; repaint per 16 KiB block, ~80 cycles each on an 8086; CountLines
; clears progSize when the scan ends, so later refills (GoLine, cold
; Downs at a block edge) paint nothing. Everything is in the uses
; list or saved explicitly: the FillBuf callers hold SI/DI live.
;------------------------------------------------------------------------------
ShowProg proc uses ax bx cx dx si di
        mov ax,word ptr progSize
        or ax,word ptr progSize+2      ; zero: no bar to paint
        jz @@done
        push es
        xor si,si                      ; the normalization shift
        mov dx,word ptr progSize+2
        mov ax,word ptr progSize
        .while (dx)                    ; shift the size right until the
                shr dx,1               ; high word is empty
                rcr ax,1
                inc si
        .endw
        mov bx,ax                      ; BX = size>>si, never zero here
        mov dx,word ptr curPos+2       ; curPos by the same shift count
        mov ax,word ptr curPos
        mov cx,si
        .while (cx)
                shr dx,1
                rcr ax,1
                dec cx
        .endw
        mov si,20
        mul si                         ; DX:AX = pos16*20
        div bx                         ; AX = filled cells, 0..20
        mov si,ax
        mov cx,ax
        mov es,vSeg
        mov di,24*160+2+58*2           ; row 24, column 58
        mov ax,A_STAT or 0DBh          ; the filled part first
        rep stosw                      ; (CX=0: a no-op)
        mov cx,20
        sub cx,si
        mov ax,A_STAT or 0B0h          ; the empty rail
        rep stosw
        pop es
@@done: ret
ShowProg endp

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
; NEW (fixes 55/85): the first LINES_VIS lines run in STORE mode parsed
; STRAIGHT into their vCache slots (no RingAppend copy pass any more:
; the proc is gone) and vPos records starts 0..22 plus entry 23 (the
; line below the view: the first Down's hot read) - so the initial
; Draw, Home AND the first Down all cost zero extra parses. The
; trailing line without EOL still counts exactly: at EOF the scan
; compares curPos with the saved line start (tmpPos), which the
; no-store mode would leave in an empty lBuf. The progress bar (fix
; 86) is retired here: progSize is cleared so later FillBuf refills
; (GoLine, cold Downs at a block edge) paint nothing.
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
                cmp totLines,LINES_VIS          ; capture lines 0..22 only:
                jae @@nocap                     ; UNSIGNED (fix 93: the 1.07
                                                ; .if was SIGNED - a totLines
                                                ; of 32.784+ read negative and
                                                ; the capture ran for EVERY
                                                ; line, with slot bl up to 255
                                                ; and vPos[totLines*4] far out
                                                ; of range)
                        ; capture view #1 (fixes 55/85): parse lines
                        ; 0..22 straight into their slots, no copy pass,
                        ; and record every start in vPos
                        mov bx,totLines
                        SLOTPTR di,offset vCache,bl
                        mov wDest,di
                        mov si,totLines
                        shl si,2                ; vPos entry of this line
                        VPSTORE si
@@nocap:        call RdLine
                .if (al)                ; ended on CR/LF: line read
                        cmp totLines,LINES_VIS  ; still capturing? UNSIGNED
                        jae @@aft               ; (fix 93) no: view is full
                        mov wDest,offset lBuf   ; the next parse goes to lBuf
                        cmp totLines,LINES_VIS-1
                        jne @@aft
                        ; line 22, the last one of the view, was just read:
                        ; curPos IS the start of line 23 = the line below
                        ; the view, the first Down's hot read (fix 110: 1.17
                        ; stored it after reading line 23 = line 24's start)
                        mov cntMode,1           ; count-only from here
                        mov si,LINES_VIS*4      ; vPos entry 23
                        VPSTORE si
@@aft:                  .break .if (totLines==0FFFFh)   ; saturate (10)
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
        mov wDest,offset lBuf           ; safety: never leave a slot armed
        xor ax,ax
        mov word ptr progSize,ax        ; retire the progress bar (86)
        mov word ptr progSize+2,ax
        mov vcValid,1                   ; slots 0..22 hold view #1 (85)
        mov vcTop,0
        mov vSlot,0
        mov word ptr curPos,0
        mov word ptr curPos+2,0
        mov curLine,0
        mov cCnt,0
        call SeekSoft
        ret
CountLines endp

;------------------------------------------------------------------------------
; FillStdin - prime the STDIN ring with the first view: read up to
; LINES_VIS lines from the pipe, each one parsed STRAIGHT into its ring
; slot (fixes 50/85: line j lives in slot j mod RSLOTS, no copy pass).
;------------------------------------------------------------------------------
FillStdin proc
        mov cx,LINES_VIS
        .repeat
                mov ax,rIdx
                SLOTPTR di,offset vCache,al      ; parse into slot rIdx
                mov wDest,di
                call RdLine
                mov wDest,offset lBuf
                .break .if (!al)
                inc rIdx
                .if (rIdx >= RSLOTS)
                        mov rIdx,0
                .endif
        .untilcxz
        ret
FillStdin endp

;------------------------------------------------------------------------------
; RingPaint - paint the merged view buffer as the content window (fix
; 56, split out of DrwCnt; fix 85: ONE buffer now): row i shows line
; curLine+i, which lives in slot (curLine+i) mod ringN (line j is slot
; j mod ringN by construction); the walk starts at slot curLine mod
; ringN and wraps once. ringN is 23 in file mode (the view-cache slots,
; the captured first view and Home included) and 46 for STDIN (the
; scrollback ring) - DrwCnt picks this painter for both.
;------------------------------------------------------------------------------
RingPaint proc uses ax bx cx dx si di bp
        mov es,vSeg
        mov ax,curLine
        xor dx,dx
        mov bx,ringN
        div bx                          ; DX = curLine mod ringN
        SLOTPTR si,offset vCache,dl     ; SI = vCache + slot*256
        mov ax,ringN                    ; the wrap limit (ringN*SLOTSZ +
        shl ax,8                        ; vCache) is loop-invariant: hoisted
        add ax,offset vCache            ; here once (fix 95 - the per-row
        mov dx,ax                       ; version paid a shl ax,8 chain x 23
        mov di,160+2                    ; rows; DX is free: WrCntRow never
        mov cx,LINES_VIS                ; touches it)
        .repeat
                mov bp,di
                push cx
                push si
                call WrCntRow
                pop si
                add si,SLOTSZ
                cmp si,dx
                jb @@k
                mov si,offset vCache    ; wrap to the oldest slot
@@k:            mov di,bp
                add di,160
                pop cx
        .untilcxz
        ret
RingPaint endp

;------------------------------------------------------------------------------
; Main - key dispatch. Left/Right/Ctrl+Left/Ctrl+Right scroll the
; horizontal window (fix 47); STDIN scrolls inside the 46-line ring
; window (fix 85).
;------------------------------------------------------------------------------
Main proc
        .if (!isFile)
                call FillStdin          ; prime the ring with view #1
        .endif
        call Draw
@@lp:   ; wait for a keystroke: the BIOS ring (0040h) is checked FIRST,
        ; so a key that arrived while the last key was being handled is
        ; taken with ZERO extra latency (fix 77) - INT 28h and the mouse
        ; poll run only while really idle (fixes 25/26)
        .while (1)
                KeyAvail()              ; ZF=1: ring empty
                .break .ifnz            ; a key waits: serve it now
                int 28h                 ; DOS idle: TSRs/multitaskers run
                inc idleCnt             ; fix 81: INT 33h AX=3 costs
                test idleCnt,7          ; 100-1000+ cycles per call and a
                jnz @@nom               ; press lasts >= 50 ms - the idle
                .if (mPres)             ; loop runs thousands of passes
                        call MousePoll  ; in that time, so polling 1 of
                .endif                  ; every 8 is plenty (the drag
@@nom:                                  ; loop polls every pass: it needs
        .endw                           ; the button state instantly)
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
                        call ScrDn      ; CX survives ScrDn: it only
                        or moved,al     ; touches AX/DX (only ScrUp can
                .endf                   ; reach the CX-clobbering Seek,
                                        ; fix 101)
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
                .else
                        ; STDIN (fix 85): Home jumps to the oldest line
                        ; the ring still holds - a pipe cannot rewind
                        ; any further
                        mov ax,totLines
                        sub ax,RSLOTS   ; oldest line still in the ring
                        jae @@hc        ; (102: the borrow IS the "all
                        xor ax,ax       ; of them held" case)
@@hc:                   cmp ax,curLine
                        je @@hd
                        mov curLine,ax
                        mov al,1
@@hd:
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
        mov al,bl
        and al,6
        cmp al,6                        ; middle+right together = wheel down
        je @@wdn
        test bl,4                       ; middle alone = wheel up
        jnz @@wup
        test bl,2                       ; right alone: one line down
        jnz @@wdn
        test bl,1                       ; left click on scrollbar (fix 109)
        jz @@done
        shr cx,3                        ; /8 -> column (one SHR on 386+)
        shr dx,3                        ; /8 -> row
        .if (cx==78 && dx>=1 && dx<=LINES_VIS && isFile)
                                        ; the thumb needs a seekable file:
                                        ; a pipe has no line N (fix 50)
                dec dx                  ; thumb row 0..LINES_VIS-1
                mov bx,totLines
                cmp bx,LINES_VIS        ; unsigned: 0 lines or the whole
                jbe @@done             ; file on screen -> no travel
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
                test bl,1
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
                ; STDIN (fix 85): the 46-slot ring holds the last 46
                ; lines - Up/PgUp/wheel-up work inside that window with
                ; ZERO I/O (the lines are already in memory); a pipe
                ; cannot rewind any further, that is the honest limit
                mov ax,totLines
                cmp ax,RSLOTS
                jbe @@sgo               ; fewer than 46 lines: all held
                sub ax,RSLOTS           ; oldest line still in the ring
                cmp ax,curLine
                jb @@sgo                ; above it: the move is safe
                ret                     ; at the ring base: no move
@@sgo:          dec curLine
                mov al,1
                ret
        .endif
        .if (cCnt)
                dec curLine
                dec cCnt
                dec cHead
                and cHead,CACHE_MSK     ; pop the top entry (ring, 100)
                mov bx,cHead
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
@@doit: call CachePos
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
        dec cHead
        and cHead,CACHE_MSK             ; the ring's top entry (100)
        mov bx,cHead
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
                mov ax,curLine
                add ax,LINES_VIS
                cmp ax,totLines
                jb @@have               ; the new bottom line is ALREADY in
                                        ; the ring (an Up went there first):
                                        ; advance without touching the pipe
                mov ax,rIdx
                SLOTPTR di,offset vCache,al      ; parse straight into the
                mov wDest,di            ; slot rIdx (fix 85: no copy pass)
                call RdLine             ; EOF decides (the estimate of 1.05
                mov wDest,offset lBuf   ; froze the pipe after line one)
                or al,al
                jz @@s
                inc rIdx                ; line j is slot j mod 46: rIdx
                .if (rIdx >= RSLOTS)    ; walks the same discipline
                        mov rIdx,0
                .endif
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
@@have:         mov ax,curLine
                inc ax
                jz @@s                  ; 65.535 top lines: stop safely
                mov curLine,ax
                mov al,1
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
        .if (isFile)
                mov ax,word ptr curPos
                mov word ptr savPos,ax
                mov ax,word ptr curPos+2
                mov word ptr savPos+2,ax
                mov bx,curLine
                and bx,31
                shl bx,2                       ; BX = (curLine and 31)*4: vPos
                VPSTORE bx                     ; entry (fix 64: no [DX] on 8086)
                .if (vcValid && vcTop==curLine+1)
                        ; hot (fix 64): the new top line takes the slot the old
                        ; bottom line (vcTop+22, slots are line mod 23) just left
                        .if (vSlot)
                                dec vSlot
                        .else
                                mov vSlot,LINES_VIS-1
                        .endif
                        SLOTPTR bx,offset vCache,vSlot   ; slot*256 (AH load)
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
        .else
                ; STDIN (fix 85): the new top line is already in the
                ; ring - paint its slot, zero reads, zero parses
                mov ax,curLine
                xor dx,dx
                mov bx,RSLOTS
                div bx                          ; DX = curLine mod 46
                SLOTPTR si,offset vCache,dl
        .endif
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
                        SLOTPTR bx,offset vCache,vSlot   ; slot*256
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
                        VPSTORE di              ; holds the paint slot
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
                        SLOTPTR bx,offset vCache,dl  ; slot*256 (AH/DL;
                                        ; fix 78: AL was the quotient)
                        mov ax,curLine
                        and ax,31
                        shl ax,2                ; vPos: row 0 (64)
                        mov di,ax               ; DI indexes (no [DX] on
                        mov cx,LINES_VIS        ; 8086, fix 64)
@@fl:           mov wDest,bx           ; parse row i straight into slot
                        VPSTORE di              ; vPos: row i's start (64)
                        call RdLine
                        add bx,SLOTSZ
                        .if (bx >= offset vCache+LINES_VIS*SLOTSZ)
                                mov bx,offset vCache
                        .endif
                        add di,4
                        and di,7Fh              ; branchless wrap (fix 96)
                        loop @@fl
                        if USE386
                        movzx ax,vSlot         ; native MOVZX (89)
                        else
                        mov al,vSlot           ; SMART's 8086 MOVZX
                        xor ah,ah              ; emulation, inline (89)
                        endif                  ; AX = vSlot: the bottom
                        add ax,LINES_VIS-1     ; row's slot is vSlot+22,
                                                ; mod 23 (sizes stay legal)
                        .if (ax >= LINES_VIS)
                                sub ax,LINES_VIS
                        .endif
                        SLOTPTR si,offset vCache,al      ; slot*256 (AH/AL)
                        mov ax,curLine          ; vPos: the line below
                        add ax,LINES_VIS        ; the view (next Down 64)
                        and ax,31
                        shl ax,2
                        mov di,ax               ; DI indexes (fix 64)
                        VPSTORE di              ; vPos: the line below
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
                ; STDIN ring (fix 85): the new bottom row is line
                ; curLine+22, already in slot (curLine+22) mod RSLOTS -
                ; whether ScrDn just read it at the frontier or an Up
                ; visited it before, nothing is re-read from the pipe
                mov ax,curLine
                add ax,LINES_VIS-1
                xor dx,dx
                mov bx,RSLOTS
                div bx                  ; DX = (curLine+22) mod 46
                SLOTPTR si,offset vCache,dl      ; slot*256 (AH/DL trick)
        .endif
        mov di,LINES_VIS*160+2          ; draw on the bottom row (fix 38)
        call WrCntRow
        call DrwBar
        call DrwSt
        pop es
        ret
DrwDn1 endp

;------------------------------------------------------------------------------
; WrCntRow - paint one line on a content row. DS:SI = slot base (lBuf
; or a merged-buffer slot: a vCache view slot or a STDIN ring slot),
; DI = byte offset of the row's column 1 in the video page (ES =
; video segment). The slot's LENGTH BYTE at slot+255 (fix 66: every
; slot is LBUFCAP chars + NUL + its length, written by every RdLine
; exit) does the whole dispatch since fix 99: avail = len - hPos is
; exactly the number of REAL chars the window can show, so the paint
; loop never probes for the NUL any more (the compare stays
; UNSIGNED, fix 93):
;   avail > LINEWID : the row is full - 38 unrolled pairs plus the
;                     77th char, five instructions per pair instead
;                     of the old nine (no lodsb/or/jz per byte);
;   1..LINEWID      : avail chars, then the pad cells in one REP
;                     STOSW (the pad count waits on the stack while
;                     LODSB runs);
;   len <= hPos     : the whole row is one REP STOSW.
; Clobbers AX CX SI DI only - DrwCnt holds its vPos cursor in DX,
; RingPaint its wrap limit there and both keep BX/BP live (fix 99
; keeps the 1.14 contract).
;------------------------------------------------------------------------------
WrCntRow proc
        mov al,byte ptr [si+255]        ; the line's length (fix 66)
        cmp al,byte ptr hPos            ; the line ends left of the window?
        jbe @@pad                       ; UNSIGNED (fix 93: the 1.10 .if
                                        ; was SIGNED - a length of 128..
                                        ; 254 read negative and every
                                        ; such line padded blank at any
                                        ; hPos, 0 included; HPOSMAX < 256,
                                        ; so the low byte decides, fix 66)
        sub al,byte ptr hPos            ; avail: real chars from the
        mov cl,LINEWID                  ; window start on (99); CL =
        sub cl,al                       ; pad cells, CF=1: full row
        mov ah,ATTR_CONT
        jc @@full
        add si,hPos                     ; window start: one ADD, no walk
        mov ch,0                        ; CX = the pad count (0..76)
        push cx                         ; it waits here while LODSB runs
        mov cl,al                       ; CX = chars to paint (1..77)
@@ps:   lodsb
        stosw
        loop @@ps
        pop cx                          ; pad the rest (CX=0: no-op)
        mov al,' '                      ; AH already carries ATTR_CONT
        rep stosw
        ret
@@full: add si,hPos                     ; window start: one ADD, no walk
        mov cx,38                       ; 38 pairs + the 77th char: no
@@p:    lodsb                           ; NUL probes - the length byte
        stosw                           ; already proved these 77 chars
        lodsb                           ; are data (fix 99)
        stosw
        loop @@p
        lodsb                           ; the 77th char
        stosw
        ret
@@pad:  mov ax,A_CONT or ' '            ; the whole row is padding
        mov cx,LINEWID
        rep stosw
        ret
WrCntRow endp

;------------------------------------------------------------------------------
; CachePos - remember curPos (start of current line) in the ring cache.
; A RING since fix 100: cHead is the next slot to write and a full
; cache overwrites its oldest entry - the old linear buffer shifted
; (CACHE_SZ-1)*4 bytes per call once full, and the GoLine/End walks
; call it once per line, so an 8088 paid more for the shift than for
; the scan itself. The most recent entry is always cHead-1; writes
; after ScrUp pops refill the popped slots top-down (LIFO), and the
; valid window is always [cHead-cCnt .. cHead-1]. cHead needs no
; reset anywhere: any position is right for an empty cache.
;------------------------------------------------------------------------------
CachePos proc
        mov bx,cHead
        shl bx,2                                ; *4
        mov ax,word ptr curPos
        mov dx,word ptr curPos+2
        mov word ptr cache[bx],ax
        mov word ptr cache[bx+2],dx
        inc cHead
        and cHead,CACHE_MSK                     ; ring wrap (fix 100)
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
        mov cntMode,1                   ; consume-only walk: End and the
        .while (cx)                     ; scrollbar jump ~2x faster on
                call CachePos           ; big files (fix 76: the text is
                call RdLine             ; not needed, only the line
                .break .if (!al)        ; starts - the store scanner is
                dec cx                  ; twice the cost of this one).
                                        ; CX survives both calls (101:
                                        ; RdLine saves it via uses and
                                        ; the ring CachePos never loads
                                        ; it - no string op any more)
        .endw
        mov cntMode,0
        ret
GoLine endp

;------------------------------------------------------------------------------
; Buffered input engine (fixes 6, 7 and 42)
;------------------------------------------------------------------------------
; FillBuf - refill bBuf from the file (INT 21h AH=3Fh, BUFSZ bytes) and
; set bLen/bIdx. In STDIN mode hFile is 0 and handle 0 IS the pipe, so
; the same call buffers the stream (fix 75). NEW in 1.05: no AH=42h seek any more - the DOS file
; pointer equals bBase at every entry (open: 0; Seek moves the pointer
; AND sets bBase=curPos; FillBuf itself advances bBase by the bLen bytes
; just read), so the seek was one wasted DOS call per block (fix 42).
; Returns AX = the bytes read, 0 = EOF: RdLine's @@refill tests it
; right after the call (fix 106 - 1.15 returned progSize instead and
; the load hung). Keeps bx/cx/dx: RdLine's refill path holds the
; fetch cursor, the loop count and the exit flag across the call.
FillBuf proc uses bx cx dx
        mov bx,hFile
        mov ah,3Fh
        mov dx,offset bBuf
        mov cx,BUFSZ
        int 21h
        jnc @@ok                        ; CF=1: AX is an error code, not
        xor ax,ax                       ; a byte count: treat it as EOF (112)
@@ok:   mov bLen,ax
        mov bIdx,0
        push ax                         ; the read count IS the return
        mov ax,word ptr progSize        ; value: the 1.14 push/pop
        or ax,word ptr progSize+2       ; guards it against THIS mov,
        jz @@np                         ; not against ShowProg (its
        call ShowProg                   ; uses ax was never the point;
@@np:   pop ax                          ; fix 101 dropped the pair and
        ret                             ; every file hung at load, 106)
FillBuf endp

; GetByte - AL = next byte, CF=1 on EOF. Consumed bytes advance bIdx;
; curPos is NOT updated here any more: curPos = bBase+bIdx is kept as an
; invariant and materialized by the callers (RdLine, fix 37).
; FIX 75: STDIN runs through the same 16 KiB engine as files - hFile is
; 0 in pipe mode and handle 0 IS the pipe, so FillBuf's AH=3Fh works
; unchanged. 1.00 did one DOS call per byte here (a 385 KB pipe paid
; 385.063 calls, the exact problem fix 6 fixed for files); now it pays
; 24, and RdLine's LODSW scanners serve pipes at full speed too.
GetByte proc
        .if (hFull)
                mov al,hByte
                mov hFull,0
                clc
                ret
        .endif
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
        mov al,byte ptr bBuf[bx]
        inc bIdx
        clc
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
        mov ax,bx
        sub ax,si                       ; AX = bytes left in the block:
        or bp,bp                        ; @@full's entry contract (fix 84:
        jnz @@full                      ; 1.11 jumped there with the CALLER'S
                                        ; AX - CountLines got away with the
                                        ; curPos high word, but GoLine passes
                                        ; curPos low: at a block-straddling
                                        ; line the scan marched past BX
                                        ; through the whole segment, up to
                                        ; a 64 KiB runaway on the 386 - the
                                        ; scroll-down hang; the 8086 walked
                                        ; wrong since fix 76 too)

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
@@sn:   if USE386
        cmp ax,4
        jb @@swr                        ; 1-3 bytes: the pairs path below
        shr ax,2                        ; AX = dwords of this round (fix
        mov cx,ax                       ; 80: a dword without CR/LF stores
@@sw:   lodsd                           ; its 4 characters with ONE STOSD,
        mov edx,eax                     ; ~10.5 instead of ~23 cycles/byte
        xor eax,0A0A0A0Ah               ; on the 386 - this is the parse
        xor edx,0D0D0D0Dh               ; that PgDn/PgUp and the no-cache
        and eax,edx                     ; repaints pay 23 times per page.
        mov edx,eax                     ; Same SWAR candidate test as fix
        sub eax,01010101h               ; 79; candidate dwords re-scan
        not edx                         ; byte per byte into the shared
        and eax,edx                     ; @@stc/@@stl exits (DX is still
        and eax,80808080h               ; the entry 0 mid-line: no exit
        jnz @@swh                       ; has run, and each one writes it
        mov eax,[si-4]                  ; before @@dones). The 0-3
        stosd                           ; residue bytes re-round through
@@swn:  loop @@sw                       ; @@sloop, which enters @@swr:
        jmp @@sloop                     ; no loop, every path consumes.
@@swh:  sub si,4                        ; candidate: re-scan it exactly.
                                        ; NO "sub di,4": the dword was
                                        ; never stored, DI already points
                                        ; at its store position - the 1.11
                                        ; copy-paste from the count scan's
                                        ; @@swh stored every candidate one
                                        ; dword early (fix 83): the line
                                        ; shifted 4 chars per TAB/08-0Fh
                                        ; dword, the writes could run
                                        ; below the slot start (into fName
                                        ; and the previous slot's length
                                        ; byte) and [wDest+255] wrapped
        mov dx,4
@@sr:   lodsb
        cmp al,13
        je @@stc                        ; CR: shared peek exit
        cmp al,10
        je @@stl                        ; LF: shared exit
        stosb
        dec dx
        jnz @@sr
        jmp @@swn                       ; dword done: count it with CX
@@swr:
        endif
        shr ax,1                        ; AX = words of this round
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
        if USE386
        shr cx,2                        ; CX = dwords (fix 79: on the 386
        jz @@t4                         ; the scan reads LODSD and tests
@@fw:   lodsd                           ; four bytes in parallel: cand =
        mov edx,eax                     ; (v^0A0A0A0Ah)&(v^0D0D0D0Dh) has
        xor eax,0A0A0A0Ah               ; a zero byte exactly when the
        xor edx,0D0D0D0Dh               ; data byte lies in 08h..0Fh (a
        and eax,edx                     ; superset of CR/LF: no false
        mov edx,eax                     ; negatives). The classic formula
        sub eax,01010101h               ; locates them: (cand-01010101h)
        not edx                         ; & ~cand & 80808080h. TAB/VT/FF
        and eax,edx                     ; false hits only re-scan those
        and eax,80808080h               ; four bytes with the exact
        jz @@fwn                        ; handlers below. ~7.5 instead of
        sub si,4                        ; ~10.6 cycles/byte: the pre-scan
        mov dx,4                        ; of a 385 KB file drops ~30% on
@@dr:   lodsb                           ; a 386DX-25. DX is free here: no
        sub al,10                       ; exit has run, it is still the
        cmp al,3                        ; entry 0 and every exit below
        ja @@drn                        ; writes it before @@dones.
        cmp al,3
        je @@cr4                        ; CR: the shared peek handler
        or al,al
        jz @@lfx                        ; LF: the shared exit
@@drn:  dec dx
        jnz @@dr
@@fwn:  loop @@fw
        jmp @@t4                        ; the 0-3 residue bytes
        else
        shr cx,3                        ; CX = 8-byte units (fix 67:
        jz @@t4                         ; unroll-8 halves the LOOP toll;
                                        ; fix 87: the unroll and its
                                        ; candidate handlers now live INSIDE
                                        ; the 8086 branch - 1.11 assembled
                                        ; them unreferenced on -3)
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
        endif
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
        if USE386                      ; fix 87/89: 8086-only candidates
        else
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
        endif
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
@@eof:                                  ; EOF from @@refill: bIdx=0 there,
                                        ; DX=0 forced by the refill branch
                                        ; below (fix 107: the 386 SWAR
                                        ; rounds leave garbage in DX and
                                        ; the old "or dx,dx" then reported
                                        ; a phantom line at true EOF)
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
        jnz @@rfin                      ; more data: resume the scan
        xor dx,dx                       ; 107: EOF exit reason. The 386
        jmp @@dones                     ; SWAR rounds (79: @@fw/@@sw) run
@@rfin:                                 ; their candidate test THROUGH DX
                                        ; and leave garbage behind - the
                                        ; refill-EOF arrival must not test
                                        ; it as the "line ended" flag (the
                                        ; 8086 rounds only touch AL/AH)


        mov si,offset bBuf
        mov bx,bLen
        add bx,offset bBuf
        mov ax,bx
        sub ax,si                       ; bytes of the fresh block
        or bp,bp                        ; a consume-only line is running?
        jnz @@full
        jmp @@sloop                     ; display: the round check
                                        ; recomputes bytes and capacity
@@slowin:                               ; the unget slot only: byte per byte
                                        ; (STDIN is buffered too, fix 75)
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
; I/O: DrwCnt paints the merged buffer for STDIN and for the captured
; view of lines 0..22 (fixes 50/55/85).
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
; DrwHdr - title bar: "4VIEW[386] 1.17 - <path\name>" (or STDIN). Painted by
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
; The merged buffer (fix 85) backs the view in every zero-I/O case:
; STDIN (the 46-slot ring holds the last 46 lines, so any view inside
; the scrollback window paints without touching the pipe) and the file
; view-cache hit (fix 63: curLine == vcTop, the slots hold exactly this
; view - Left/Right h-scroll, pop-up close, Home and the captured
; first view of lines 0..22 included) - both paint through RingPaint.
; File mode otherwise (fix 63): every row is parsed straight into its
; vCache slot (wDest), vPos records each start (fix 64) and the view
; becomes the cached one. No MUL (fix 13), BP carries the row base and
; advances by 160. Each line is written once and only the unused tail
; is padded - EOF rows are cleared explicitly.
;------------------------------------------------------------------------------
DrwCnt proc uses ax bx cx dx si di bp
        .if (!isFile || (vcValid && curLine==vcTop))
                ; the merged buffer already holds this view (fix 85):
                ; STDIN's ring, or the file view-cache hit (fix 63) -
                ; paint the slots, zero file access
                call RingPaint
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
        SLOTPTR bx,offset vCache,dl     ; BX = slot cursor of row 0 (fix
                                        ; 78: DL is curLine mod 23 - 1.10
                                        ; passed AL, the QUOTIENT of the
                                        ; div, so the cursor started
                                        ; (curLine/23)*256 bytes late and
                                        ; row 0 parsed the top line past
                                        ; the vCache end: the status bar
                                        ; bug, see the 1.11 header)
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
                VPSTORE si              ; on 8086, fix 64): row i's start
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
                and dx,7Fh              ; branchless vPos wrap (fix 96:
                                        ; entries are 4*0..4*31, 128
                                        ; wraps to 0, one instruction
                                        ; less and no compare)
                pop cx
        .untilcxz
        ; vPos entry of the line AFTER the bottom row (the next Down's
        ; fast path): curPos is on it now, DX already points there (64)
        mov si,dx                       ; SI indexes (no [DX] on 8086)
        VPSTORE si                      ; vPos: the line below the view
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
; is FastMul 22 on both builds (fix 92: 1.13's -3-only MOVZX+IMUL
; inline left DX unwritten and the thumb rode garbage - the macro's
; v2.42 SHLD repair feeds the DIV the exact DX:AX pair again).
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
        FastMul 22              ; DX:AX = curLine*22, no MUL (fixes
                                ; 35/92: the 1.13 -3-only MOVZX+IMUL
                                ; inline never wrote DX and the DIV
                                ; read a garbage high word)
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
; (fix 4), then PaintStat paints it. curLine*100 is FastMul 100 on
; both builds (fixes 35/92: 1.13's -3-only MOVZX+IMUL inline left DX
; unwritten - the macro's v2.42 SHLD repair feeds the DIV the exact
; DX:AX pair); only the final DIV by the variable
; totLines remains (fix 13). 1.06 (fix 47): when the horizontal
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
        FastMul 100                     ; DX:AX = curLine*100 (fixes
        mov bx,totLines                 ; 35/92: no MUL, DX really is
        div bx                          ; the high word now); variable
                                        ; divisor: DIV stays
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
@@c:     lodsb
        stosb                   ; copy the NUL too, then put DI back on
        or al,al                ; it: the same result as the .while
        jnz @@c                 ; (fix 113), 4 instructions per char
        dec di
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
        shl ax,2                        ; 8q (2q doubled twice)
        add ax,dx                       ; 10q
        mov dx,ax
        mov ax,bx
        sub ax,dx                       ; remainder candidate
        .while (ax>=10)                 ; correct the approximate quotient
                sub ax,10
                inc si
        .endw
        mov bx,si                       ; quotient for the next digit
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
; FIX 97 moved the bulk buffers to the END as dup(?) behind the
; FILEEND marker, cut right after by a build script (41.174 ->
; 5.941 bytes in 1.14); FIX 115 retires the cut: the buffers are
; now offset equates (see the tail) and the assembler emits the
; final image in one step. A write-before-read
; audit per buffer backs the change: fName is written by ParseCmd
; before any read (and never read when isFile=0), lBuf's [0] and
; length byte are written by RdLine's entry/exit before any paint,
; stBuf by StatLoad/DrwSt before PaintStat, bBuf by FillBuf before any
; scan (bLen gates it), cache by CachePos before the cCnt-guarded
; reads, svScr by Init's save before Done's restore, popSave by the
; PopUp save loop before the restore loop, vPos by the VPSTORE fills
; before the guarded hot reads, tBuf by Truename before the SCASB.
; The ONE exception is vCache: short files read the EOF rows, STDIN
; reads slots below the first fill and ring slots beyond a short pipe
; - they must paint as blank, so Init clears it once with BLKFIL
; (fix 97).
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
cHead           dw 0                    ; scroll ring: next write slot,
                                        ; most recent entry is cHead-1
                                        ; (fix 100; lives inside the Init-
                                        ; cleared block, like cCnt)
hFull           db 0
hByte           db 0
bBase           dd 0
bLen            dw 0
bIdx            dw 0
keyScan         db 0
moved           db 0
hPos            dw 0                    ; horizontal window start (fix 47)
rIdx            dw 0                    ; next STDIN ring slot (fixes 50/85)
ringN           dw 0                    ; ring slots: 23 file / 46 STDIN (85)
progSize        dd 0                    ; file size for the load bar (86)
cntMode         db 0                    ; RdLine consume-only pass (49)
vSlot           db 0                    ; view cache: top row's slot (63)
vcTop           dw 0                    ; view cache: top line number (63)
vcValid         db 0                    ; slots hold lines vcTop..+22 (63)
popRow          dw 0
popCol          dw 0
popLines        dw 0
popOff          dw 0            ; pop-up corner offset, reused 3x (fix 33)
zEnd            label byte
isFile          db 0            ; set by ParseCmd: NEVER zeroed by Init
wDest           dw offset lBuf ; RdLine store target (63): pointer,
                                ; deliberately outside the Init-cleared
                                ; block (fix 63)
vSeg            dw 0B800h       ; Init sets B000h for mono (mode 7)
svPage          db 0
svMode          db 0                    ; video mode at entry (fix 71)
svForced        db 0                    ; Init forced mode 3 (fix 71)
svShape         dw 0
svCurs          dw 0
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
idleCnt         db 0                    ; idle-pass counter (fix 81); it
                                        ; only feeds the mod-8 throttle
; --- fix 115 (over fix 97): the bulk tail is no longer DECLARED
; data. The ten work buffers are pure offset EQUates into the RAM DOS
; gives a COM beyond its image - exactly the byte offsets the 1.14
; dup(?) layout produced (same order, same sizes, no alignment
; games), so every code byte is unchanged; but the assembler now has
; NO item after the FILEEND stamp and ends the emitted image at it:
; "ASMC -bin" alone gives the final ~6 KB COM, no truncation step (a
; plain -bin run used to pad 35.297 zero bytes up to the last dup(?)
; item - the reported 40K). The load footprint is the one fix 97
; audited: Init clears vCache (the only read-before-write buffer),
; every other buffer is written before it is read, and the stack
; lives ~24 KB above BMEMTOP at the top of the segment.
FILEEND         db "<4VIEW19>",0       ; last initialized bytes: the
                                        ; image stamp (fix 97; the cut
                                        ; step retired by fix 115)
BSSBASE         equ $                  ; RAM base: first byte past the image
fName           equ BSSBASE                    ; 65 bytes (12)
lBuf            equ fName+65                   ; SLOTSZ: LBUFCAP chars
                                        ; + NUL + length at 255 (47/66)
stBuf           equ lBuf+SLOTSZ                ; 96 bytes (4)
bBuf            equ stBuf+96                   ; BUFSZ bytes (6)
cache           equ bBuf+BUFSZ                 ; CACHE_SZ*4 (100)
svScr           equ cache+CACHE_SZ*4           ; 4000 bytes (22)
popSave         equ svScr+4000                 ; HLP_H*WWIN*2 (33)
vCache          equ popSave+HLP_H*WWIN*2       ; RSLOTS*SLOTSZ (63/85):
                                        ; slots 0..22 are the file view
                                        ; cache, all 46 form the STDIN
                                        ; scrollback ring - one buffer,
                                        ; zeroed by Init (fix 97)
vPos            equ vCache+RSLOTS*SLOTSZ       ; VPOSN*4 (64)
tBuf            equ vPos+VPOSN*4               ; 128 bytes (30)
BMEMTOP         equ tBuf+128           ; last RAM byte the program owns
end