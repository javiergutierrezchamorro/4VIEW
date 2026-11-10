;------------------------------------------------------------------------------
; 4VIEW 2.02 - Turbo Vision style text viewer for DOS (ASMC)
; (c) 2025-2026 Javier Gutierrez Chamorro (Guti)
; Revision 2.02 fixes (194-198; the hex rewrite, info popup, word wrap and
; the bug-sweep):
;  194. HEX MODE WAS BROKEN (the screenshot): the 2.01 HexDraw painted
;       addresses that never incremented (all "0000"), left the top rows
;       black, and showed no ASCII gutter. The root cause was a
;       combination of: (a) the separate 23-row clear loop painted cols
;       1-77 but the per-row paint then wrote from col 1 with stosw whose
;       DI was recomputed from BP, and the address column read curPos
;       AFTER GetByte had advanced bIdx through 16 bytes (the reader's
;       curPos invariant bBase+bIdx had drifted from the row start stored
;       in @@read); (b) past-EOF rows jumped to @@skip without clearing,
;       leaving stale content; (c) DrwSt showed text-line numbers
;       (meaningless in hex mode). HexDraw is rewritten: one row per
;       iteration, clear-and-paint combined, the address is captured
;       BEFORE GetByte touches the reader, past-EOF rows are cleared to
;       spaces, and the ASCII gutter is always painted. HexB uses
;       shr al,4 (SMART.INC: native on 386, 4 shifts on 8086) instead of
;       four shr al,1.
;  195. HEX-AWARE STATUS BAR AND SCROLLBAR: DrwSt in hex mode now shows
;       "Off <byte>/<size> <pct>%" with the byte offset = curLine*16 and
;       the percentage based on hex rows (fileSize/16), not text lines.
;       DrwBar in hex mode maps the thumb to hex rows. The scrollbar and
;       status bar are now consistent with the hex view.
;  196. 'I' INFO IS A POPUP: the 2.01 ShowInfo painted a one-line "Size:
;       N Lines: N" on the status bar (and clobbered it for the next
;       repaint). ShowInfo now builds a 6-line info table (file name,
;       size, line count, position, mode) and displays it through PopUp
;       - green box, centered, any key dismisses, screen restored.
;  197. WORD WRAP IMPLEMENTED: 'W' toggles wrap mode (the 2.00 wrapOn
;       flag was vaporware - fix 182 removed it as dead). When wrap is
;       on: hPos is locked to 0, RdLine caps each line at LINEWID chars
;       (the store capacity check uses LINEWID instead of LBUFCAP), and
;       the @@sful path returns immediately (AL=1) without consuming the
;       rest of the logical line - so each visual row is a separate
;       cache/count entry. CountLines recounts visual rows when wrap is
;       toggled. Left/Right/Ctrl+Left/Ctrl+Right are disabled in wrap
;       mode. The cache, scroll ring and navigation all work with visual
;       rows transparently.
;  198. MOUSE RELEASE-WAIT INVERTED (found in the 2.02 code review): the
;       scrollbar drag's @@wr loop tested "test bl,1 / jz @@wr" - jumping
;       back when the button was RELEASED (ZF=1) and exiting when PRESSED.
;       This inverted the intent: the click auto-repeated (the poll saw
;       the button still down and re-fired) and could hang if the user
;       released mid-Draw. "jnz @@wr" loops while pressed and exits on
;       release, matching the comment.
;  199. ScrDn HEX MISSING CARRY CHECK: the hex branch of ScrDn did
;       "add ax,LINES_VIS" without testing carry - the text branch has
;       "jc @@s" but the hex branch omitted it. For curLine near 65535
;       the add wraps to a small value, the EOF guard passes, and ScrDn
;       advances curLine until it wraps to 0 (the view jumps from bottom
;       to top). "jc @@s" is added after the add.
;  200. DEAD srSave2 REMOVED: DoSearch's "SAVEPOS srSave2" at @@cont was
;       write-only (never read - the post-hit walk re-derives the position
;       from curPos=0/SeekSoft). The 4 mov instructions per scanned line
;       and the srSave2 dd 0 declaration are gone.
;  201. POPASK CX RELOAD ORDER: INT 33h AX=1 (show mouse) sat between
;       the CX=askCnt reload and ret. The MS driver preserves CX but some
;       clones don't - the reload now comes AFTER the INT 33h so the
;       return value is safe regardless of the driver.
;  202. Version 2.02; the image stamp is "<4VIEW202>". SMART.INC stays
;       at v2.43.
;
; Revision 2.02b fixes (208-213; the comprehensive review pass):
;  208. SIGNED COMPARISON IN DoSearch (CRITICAL): the forward-search
;       guard ".if (ax >= totLines)" was SIGNED - ASMC's .if generates
;       jge. When totLines >= 32768 (negative signed), the test
;       "positive >= negative" was always true, so the forward search
;       silently reported "not found" on any file with >= 32768 lines
;       without scanning a single line. Changed to cmp/jae (UNSIGNED),
;       joining the discipline of fixes 23/31/93/129/140.
;  209. DetectBinary BUFFER OVERFLOW (CRITICAL): DetectBinary probed
;       up to 512 bytes into hxBuf, but hxBuf was only 16 bytes - the
;       remaining 496 bytes overflowed into infoBuf and 16 bytes past
;       BMEMTOP into free RAM. Non-fatal by luck of layout (infoBuf is
;       write-before-read, the tail is free RAM), but a latent crash.
;       hxBuf is now 512 bytes (infoBuf pushed forward accordingly,
;       stack still > 6KB).
;  210. HexDraw CARRY LOSS (robustness): "add ax,bp" followed by
;       "xor dx,dx" - XOR clears CF, so if curLine+bp overflowed 65535
;       the carry was lost and DX:AX got the wrong 32-bit offset.
;       Currently safe (curLine bounded to <= 65512), but fragile if
;       a future change lets curLine reach 65535. Changed to "mov dx,0
;       / adc dx,0" which preserves and propagates the carry.
;  211. DEAD CODE: AtoU's "inc cx" incremented the multiplier (10->11)
;       not the digit counter - "mov cx,10" reset it each iteration.
;       PopAsk's "mov popLines,2" was write-only (PopAsk doesn't call
;       PopUp). Both removed.
;  212. HEXROWS MACRO: the (fileSize+15)/16 computation was duplicated
;       4 times (Main End, MousePoll, DrwBar, DrwSt) with 4 different
;       @@ label names (@@hs, @@mhr, @@hdiv, @@hshft). All 4 replaced
;       by one HEXROWS macro with LOCAL labels - one source of truth,
;       no label name proliferation.
;  213. 386 LOOP OPTIMIZATION in HexDraw: the 3 hot loops (read, hex
;       bytes, ASCII) used "loop" which costs 11 cycles taken on a 386.
;       Changed to "dec cx / jnz" (2 cycles) on the 386 build, keeping
;       "loop" on 8086 (17 cycles there, beats dec+jnz's 3+16). ~3300
;       cycles saved per hex repaint on 386. Same pattern as fix 134.
;       Version 2.02b; the image stamp stays "<4VIEW202>".
;
; Revision 2.02c changes (214-217; V removal, I date/time, cleanup):
;  214. V (SHOWSTATS) REMOVED: the 'V' key showed a one-line stats bar
;       duplicating 'I' info (lines and bytes) plus the file date/time.
;       ShowStats proc, the sLines2/sDate strings, and the V handler in
;       Main are all gone. The 'V' and 'v' keys now both trigger
;       back-scan (was: V=stats, v=back-scan). The help line a15 no
;       longer mentions V.
;  215. I (SHOWINFO) ADDS DATE/TIME: the info popup now has 7 lines
;       (was 6) — line 5 shows "Date: dd-mm-yyyy hh:mm" from INT 21h
;       AX=5700h (the file's timestamp). infoBuf grows 480->560 bytes
;       (7*80), infoTab has 7 entries. For STDIN (no file handle) the
;       date line is blank.
;  216. DATE OPTIMIZATION: the svDate/svTime field extractions switched
;       from "mov cl,N / shr ax,cl" to "shr ax,N" (SMART.INC macro:
;       native on 386, N one-bit shifts on 8086 at ~2 cycles each vs
;       mov cl + shr cl at ~4+8+4N cycles — ~2.5x faster on 8086).
;       svDate/svTime are cached in BX across the U2A calls (U2A
;       preserves BX via its uses list) — saves 5 memory reads.
;  217. DEAD CODE REMOVED: DrwBar's ".if (ax>=LINES_VIS) mov ax,
;       LINES_VIS-1" clamp was unreachable — the DIV quotient is
;       bounded to 0..22 by the curLine <= eff_total-LINES_VIS
;       invariant (same class as fix 159). Also removed orphaned
;       comment after infoTab, stale "fix 180" on svDate/svTime, and
;       sLines2/sDate dead data strings.
;       Version 2.02c; the image stamp stays "<4VIEW202>".
;
; Revision 2.02d changes (218-219; Down scroll speed and Info reorder):
;  218. DOWN SCROLL WAS 2x SLOWER THAN UP: ScrDn called RdLine in STORE
;       mode (~44 cycles/byte on 8086) to advance the reader past the
;       current line — but ScrDn only needs the line START position
;       (for the EOF check), not the text. ScrUp's fast path did ZERO
;       RdLine (just popped the position cache). The asymmetry: Up = 1
;       RdLine (DrwUp1 only), Down = 2 RdLine (ScrDn + DrwDn1).
;       Fix: ScrDn's RdLine now runs in CONSUME mode (cntMode=1,
;       ~22 cycles/byte) — 2x faster. Down is now 1 consume + 1 store
;       vs Up's 0 + 1 store, a much smaller gap.
;  219. INFO POPUP REORDERED: lines are now File, Size, Date, Lines,
;       Position, blank, Mode (was File, Size, Lines, Position, Date,
;       blank, Mode). Date is now in position 3 — more logical grouped
;       with the other file metadata (Size).
;       Version 2.02d; the image stamp stays "<4VIEW202>".
;
; Revision 2.02e optimizations (220-222; the 386 hex-mode speed pass):
;  220. HEXROWS MACRO USES NATIVE 32-BIT SHIFT ON 386+: the macro computed
;       (fileSize+15)/16 with a 4-iteration shr dx,1/rcr ax,1 loop. On a
;       386 each RCL r/m16,1 costs ~9 cycles, so the loop cost ~44 cycles
;       per call. The 386+ path now does "mov eax,dword ptr fileSize /
;       add eax,15 / shr eax,4 / cmp eax,0FFFFh / jbe / mov eax,0FFFFh"
;       - one native 32-bit load and one immediate shift, ~15 cycles.
;       Called from DrwBar, DrwSt, MousePoll and End (4 sites), the save
;       is ~120 cycles per hex-mode frame. The 8086 path is untouched
;       (it has no native 32-bit shift). The 386 path also clobbers fewer
;       registers (only EAX vs AX+DX+CX on 8086), which all 4 call sites
;       already tolerate.
;  221. HEXDRAW OFFSET COMPUTATION USES NATIVE 32-BIT OPS ON 386+: the
;       per-row byte offset (curLine+bp)*16 was computed with "add ax,bp /
;       mov dx,0 / adc dx,0" (to catch 16-bit overflow into DX) then 4
;       "shl ax,1 / rcl dx,1" pairs - 8 shift instructions plus the carry
;       propagation, ~50 cycles per row on a 386 (RCL is ~9 cycles there).
;       The 386+ path now does "movzx eax,word ptr curLine / movzx edx,bp /
;       add eax,edx / shl eax,4" - 4 instructions, ~12 cycles. The MOVZX
;       zero-extends both operands to 32 bits, so the add cannot overflow
;       and no carry propagation is needed. One "cmp eax,dword ptr fileSize"
;       replaces the 3-instruction 16-bit compare chain. ~40 cycles saved
;       per row, ~920 per 23-row hex frame. The 8086 path keeps the
;       shift-and-rcl chain (no native 32-bit ops available).
;  222. REDUNDANT PUSH CX/POP CX AROUND GETBYTE REMOVED: the read loops in
;       HexDraw (16 bytes) and DetectBinary (512 bytes) wrapped GetByte in
;       "push cx / call GetByte / pop cx" to protect the loop counter.
;       GetByte has no USES clause but only touches BX and AX internally;
;       its one callee (FillBuf) has "uses bx cx dx" so CX survives the
;       whole call chain. The push/pop was dead weight - 4 bytes and ~30
;       cycles per loop iteration removed (2 stack accesses + 2 memory
;       accesses per call). DetectBinary's 512-iteration loop saves ~15K
;       cycles per file open; HexDraw's read loop saves ~480 cycles per
;       hex frame. Verified by register-flow analysis of GetByte and
;       FillBuf: no path through GetByte loads or stores CX.
;       Version 2.02e; the image stamp stays "<4VIEW202>".
;
; Revision 2.02f changes (223-230; the review pass - two latent reader
; bugs, two edge bugs in the 2.00 UI code, and four optimizations.
; Both builds re-verified by source review; SMART.INC stays at v2.43,
; it needed no change):
;  223. POPASK/ASKPAINT PAINTED STALE CHARACTERS: AskPaint scanned the
;       buffer for the NUL terminator, but the NUL is only written at
;       @@done (Enter) - never while editing. After a Backspace the
;       deleted character stayed on screen (the length byte said 2,
;       the display said 3), and reusing a buffer from a previous
;       prompt (srPat is shared by every Find/Scan/Goto call) showed
;       the old text's tail behind the new typing: type "C" into a
;       buffer that held "AB\0" and the box showed "CB". AskPaint now
;       paints EXACTLY askCnt characters and pads the rest.
;  224. THE PC/XT TYPEMATIC GUARD READ THE WRONG TABLE BYTE: INT 15h
;       AH=C0h returns ES:BX -> a table whose WORD at offset 0 is its
;       own LENGTH and whose MODEL byte sits at offset 2 - the 1.35
;       read ES:[BX], i.e. the length's low byte (8 or 10 on every
;       BIOS that implements the call). "cmp al,0FDh / jae" therefore
;       NEVER took the PC/XT/PCjr exit (8 < 0FDh always) and the AT
;       typematic call (INT 16h AX=0305h) ran on exactly the machines
;       the guard was written to exclude. ES:[BX+2] reads the model.
;  225. RDLINE'S UNGET curPos ADJUST WAS A 16-BIT DEC: "@@dones"
;       computes curPos = bBase+bIdx (32-bit, exact) then, when the
;       unget slot holds a peeked byte, "dec word ptr curPos" - DEC
;       does not borrow into the high word, so a curPos whose LOW
;       word is 0 (bBase+bIdx landing exactly on a 64 KiB boundary -
;       needs a file over 64 KiB with a CR at boundary-1 followed by
;       a non-LF) wrapped to ...FFFF with the high word UNTOUCHED:
;       curPos jumped 64 KiB forward and the next SeekSoft served
;       garbage. The adjust is now sub ax,1 / sbb ax,0 on the pair.
;       All hFull paths keep bIdx >= 1 (GetByte post-read states),
;       so nothing else changes.
;  226. RDLINE'S SLOW PATH (unget slot) IGNORED WRAP MODE: the entry
;       capacity was LBUFCAP (254) unconditionally, so with a pending
;       unget byte the wrap build stored up to 254 chars into ONE
;       visual row - the display paints only LINEWID (77) of them and
;       the rest of the logical line was silently eaten instead of
;       becoming the next visual row. The entry now caps CX at
;       LINEWID when wrapOn, and the full-row exit ungets the byte
;       that would overflow (dx=1, like @@sful) instead of consuming
;       it. Non-wrap behavior unchanged.
;  227. HEXDRAW READS THE ROW WITH ONE BLOCK COPY (OPT): the 16-byte
;       read loop paid 16 GetByte calls (call+ret + the bIdx/bLen
;       tests each, ~40 cycles per byte on an 8086). When bLen-bIdx
;       >= 16 (the usual case: SeekSoft just rewound inside the
;       block) the row is copied straight from bBuf with one BLKCP
;       and bIdx += 16 - the exact state GetByte would leave. The
;       GetByte path remains for the block edge, the refill and the
;       EOF padding: ~480 cycles less per hex row on an 8086
;       (~11K per 23-row frame), ~700 on a 386.
;  228. SCRDn's HEX X16 WITHOUT MUL (OPT): "mov bx,16 / mul bx" cost
;       ~118 cycles per scrolled line on an 8086; the 8086 build now
;       shifts (xor dx,dx + four shl/rcl pairs, ~19 cycles). The 386
;       build keeps MUL (the chain costs the same there). BX and CX
;       untouched in both: fix 191's PgDn contract holds.
;  229. DRWST'S HEX OFFSET GOES THROUGH FastMul 16 (OPT): the
;       hand-written xor/shl/rcl chain is exactly what FastMul 16
;       emits on the 8086 (byte-identical), while the 386 build gets
;       the native movzx/shl/shld - 3 instructions instead of 8.
;  230. MATCHSTR'S UPCASE CALLS INLINED (OPT): case-insensitive
;       matching paid two CALL/RET per compared character (~40 cycles
;       per char on an 8086) for every character of every scanned
;       line. The upcase logic is inlined (one xchg between the two
;       halves); the UpCase proc had no other caller and is gone.
;       Version 2.02f; the image stamp stays "<4VIEW202>".
;
; Revision 2.02a fixes (203-207; the hex hang root cause and cleanup):
;  207. HEX MODE HUNG - FastMul CLOBBERED BX (THE ROOT CAUSE): the 2.02
;       DrwBar and DrwSt hex code saved the effective total (hexRows) in
;       BX BEFORE calling FastMul, then used BX as the DIV divisor AFTER.
;       But FastMul's 8086 shift-and-add implementation uses BX as a
;       TEMPORARY register (22 = 16+4+2 needs a scratch for the original
;       multiplicand across the shift chain). The text-mode code was safe
;       because it loaded BX from a memory variable (totLines) AFTER
;       FastMul - but the hex code saved in BX BEFORE, so BX held garbage
;       at the DIV. If the garbage was 0, INT 0 (#DE) fired and the
;       viewer hung (the status bar never got repainted, the scrollbar
;       thumb never appeared, the keyboard went dead). If the garbage was
;       non-zero, the thumb/percentage showed wrong values silently.
;       The fix: save the effective total on the STACK (push ax) before
;       FastMul, pop it into BX after (pop bx). The stack is immune to
;       FastMul's register clobbering. Applied to BOTH DrwBar and DrwSt
;       hex paths. The text-mode path (which loads from memory) was
;       always safe and is now unified with the hex path through the
;       same push/pop sequence.
;  203. DrwBar LABEL AMBIGUITY: the 2.02 hex branch had jbe @@f that
;       resolved to @@hcap (next @@ label) instead of the full-thumb
;       @@f. DrwBar rewritten: hex computes hexRows into AX, falls
;       through to the unified text-mode thumb code. One path.
;  204. DrwSt @@hs RENAMED to @@hshft (latent conflict with Main's
;       @@hs). mul cx replaced with shifts.
;  205. ScrDn HEX CARRY CHECK: jc @@s added after add ax,LINES_VIS.
;  206. MOUSE RELEASE-WAIT: jz → jnz (was inverted).
;
; Revision 2.01 fixes (172-186; the 2.00 audit pass - the 'I' hang, the
; search rewrite, hex-mode navigation and the vaporware purge):
;  172. 'I' (AND 'V') HUNG THE VIEWER: U2A32's divide-by-10 loop tested
;       "quotient == 0" with "or dx,ax" - a DESTRUCTIVE or that left
;       DX = high|low, so the next iteration divided the OR-mangled
;       pair instead of the true quotient: the value never reached 0:0,
;       the loop pushed one "digit" word per iteration and SP marched
;       down through the whole 64 KiB segment, overwriting the program
;       itself with the pushed words (~29.275 iterations on a 24 KiB
;       file) before the CPU went on executing smashed code. Proven by
;       emulation: the very first key that formats a 32-bit number
;       ('I' info, 'V' stats) froze the machine. The test is now
;       "or bx,ax" - BX holds the high quotient and is dead after
;       "mov dx,bx" - so DX:AX survive intact and any 32-bit value
;       converges in at most 10 iterations. One byte in the image.
;  173. THE SEARCH PROMPT PAINTED GARBAGE: PopAsk used SI both as the
;       caller's prompt pointer (uses list) and as the save loop's
;       video cursor; by the time the prompt row was painted SI held
;       popOff+4*rowAdv - an offset into the CODE - and the box showed
;       code bytes instead of "Find:". The prompt pointer is now
;       pushed before the save loop and popped after it.
;  174. THE SEARCH LINE NUMBERS WERE FICTION: DoSearch's scanner
;       counted BX from 0 while the reader was already positioned at
;       the walk's target line, so every match was recorded as a
;       BX-relative "line" - a forward search for a word on every
;       line reported a hit but never moved the view. BX now starts
;       at the scan's true first line (forward: curLine+1; back: 0),
;       forward matches stop at the first hit, and the back scan
;       stops at curLine instead of walking to EOF.
;  175. AN ESC-ABORTED SEARCH CORRUPTED THE VIEW: the abort exit left
;       curPos deep in the scan while curLine stayed put, so the next
;       Down painted lines from the middle of nowhere. All exits now
;       restore the saved curPos through SeekSoft.
;  176. THE POSITIONING WALK AFTER A HIT THREW THE VIEW BACK TO BOF:
;       the second walk left curPos on the found line, then a
;       copy-pasted "curPos=0 / SeekSoft" block re-anchored the reader
;       at the top of the file - the view showed lines 0..22 labelled
;       as the found lines. The block is gone; curPos stays on the
;       hit, and the cold repaint parses exactly the right lines.
;  177. HEX MODE NAVIGATION WAS TEXT MODE'S: Up/PgUp ran ScrUp AND
;       HexUp1 (curLine moved twice, through the TEXT cache), Down
;       was blocked by the totLines limit (a binary with 100 text
;       lines could not scroll past row 77 of its hex view), End
;       jumped by text lines and the scrollbar walked the text
;       scanner. ScrUp/ScrDn are hex-aware now (one row, hex EOF
;       checked against fileSize), End and the scrollbar map hex
;       rows, HexUp1/HexDn1 are gone (movement lives in ScrUp/ScrDn,
;       painting in DrwUp1/DrwDn1), and bookmarks skip the walk in
;       hex mode. Hex mode can show the first 65.536 rows (1 MiB).
;  178. A PRINT ERROR UNANCHORED THE READER: the PRN-error paths
;       returned with the DOS pointer and bBase reset to 0 while
;       curPos still pointed at the view - the next refill read from
;       the top of the file. Every exit of PrintFile now restores
;       curPos through SeekSoft.
;  179. BINARY DETECTION IGNORED HIGH BYTES AND PAID TWO SEEKS: the
;       >7Eh branch fell into "ok" on both paths (a file of pure FFh
;       was "text"), and the probe seeked to BOF twice although Init
;       had just left the fresh reader at BOF. Bytes >= 7Fh now count
;       toward the 5% binary threshold, the two seeks are gone, and
;       the probe leaves the first block buffered for CountLines.
;  180. 'V' SHOWED THE SAME TWO NUMBERS AS 'I': ShowStats now shows
;       lines, bytes AND the file's date/time (INT 21h AX=5700h),
;       using the svDate/svTime/sDate slots that 2.00 declared and
;       never touched.
;  181. 'G' GOES TO A LINE: 2.00's help advertised "Ctrl+Home goto
;       line N" but no handler existed; the AtoU parser and the
;       sAskGoto prompt were dead data. The G key now pops the prompt,
;       parses the number and jumps (clamped to the last top line).
;  182. THE VAPORWARE TOGGLES ARE GONE: 'W' (wrapOn) and Ctrl+K
;       (lnNumOn) toggled flags that nothing ever read, and 13 more
;       dead state/string/data slots (wrapTop, bmWrap, prnOn, nWords,
;       nChars, inWord, nBinBytes, svAttr, infoTab2, iLine2..iLine5,
;       hHexTab, sLines, sWords, sChars, sAttr, sAnyKey, paintRow)
;       shipped bytes for nothing - all removed, ~330 bytes less
;       image, and the help no longer promises features that do not
;       exist. Ctrl+Y / Alt+Y (bookmarks) stay: they work.
;  183. THE THREE vcValid/.if COMPOUND TESTS GO THROUGH A REGISTER:
;       ".if (vcValid && vcTop==curLine+1)" compares two memory
;       operands inside the HLL .if - ASMC 2.40+ accepts it, older
;       ASMC/JWasm builds do not. The explicit "mov ax,vcTop" form
;       assembles everywhere at zero cost.
;  184. HexDraw's "mov al,al" (a copy-paste no-op) is gone.
;  185. POPASK STORED THE COUNTER, NOT THE CHARACTER: the input loop
;       loaded askCnt into AX ("mov ax,word ptr askCnt") BEFORE the
;       "mov [bx],al" store, so the pattern buffer received 00 01 02
;       ... instead of the typed text - every find/scan/goto acted
;       on garbage (a search could never match what was typed). The
;       character now rides in DL across the count compare.
;  186. HEX MODE CRASHED THE VIEWER (ASMC "USES" SEMANTICS): a local
;       subroutine inside a "proc uses" body cannot end in "ret" -
;       the assembler expands EVERY ret of the procedure with the
;       saves' pops, so @@hexb's ret became 7 pops + ret and each of
;       its 36 calls per row ate 7 words of HexDraw's stack: HexDraw
;       returned through a garbage address into the PSP, walked the
;       zeros straight into the entry point and RE-RAN Init - Alt+H
;       and every binary file's auto hex view froze the machine.
;       The nibble painter is now its own proc (HexB, no USES), whose
;       ret is a plain ret.
;  187. POPASK'S RESTORE LOOP BROKE THE CX CONTRACT: AdvRow leaves
;       156-2*BP (76) in CX, and PopAsk returned that instead of the
;       typed count - every "mov srLen,cx" stored garbage. The count
;       is reloaded from askCnt after the loop.
;  188. HEX OFFSETS PAINTED 1F IN THEIR SECOND BYTE: HexDraw loaded
;       AH with ATTR_CONT before saving the offset's low word, so the
;       byte that AH held (offset bits 8-15) was destroyed and every
;       row address read 00001F00-style. The push now comes first.
;  189. THE SEARCH WALK NEVER WALKED: DoSearch read its line count as
;       "mov cx,ax" AFTER "call SeekSoft" - which clobbers AX - so the
;       count was SeekSoft's leftover (0 for any file under 64 KiB):
;       the scan read line 0 while its counter said curLine+1, and
;       every recorded line number was one past the truth. The count
;       is now captured before the call.
;  190. PgDn IN HEX MODE HUNG: ScrDn's hex branch scaled with
;       "mov cx,16 / mul cx", but Main's PgDn holds its loop counter
;       in CX - every ScrDn reset it to 16 and the loop never counted
;       down. The x16 goes through BX now (ScrUp/End/scrollbar keep
;       their contracts).
;  191. WRCNTROW DESTROYED ITS CALLERS' BX SINCE FIX 143 (v1.14): the
;       "push bx" that was supposed to save the slot cursor sat ONE
;       LINE TOO LATE - right after "mov bh,ATTR_CONT" - so it saved
;       the clobbered value and every call returned BX = 1Fxx. The
;       cold-fill slot cursor stuck at a wrong address, the remaining
;       22 rows parsed straight over the program's own state block,
;       and cache-hit paths painted stale slots (the 8086 build got
;       away with it by pure layout luck; the 386 build painted the
;       wrong top row after PgDn+Up). The push now precedes the load.
;  192. THE SEARCH LINE COUNTER LIVED IN BX - WHICH CACHEPOS CLOBBERS:
;       the positioning walk calls CachePos (its cache-slot index is BX)
;       before every RdLine, so the counter survived the walk as garbage
;       and every match landed on a nonsense line. The counter rides in
;       DI now (RdLine/MatchStr/KeyAvail all preserve it).
;  193. Version 2.01; the image stamp is "<4VIEW201>". SMART.INC
;       stays at v2.43.
;
; Revision 1.35 changes (171; the keyboard feels faster):
;  171. KEYBOARD TYPEMATIC SET TO MAXIMUM on AT+ (30 cps, 250 ms delay).
;       The IBM AT BIOS default is ~10 cps with 500 ms delay: a held
;       Down key scrolls only 10 lines/second, and the first auto-
;       repeat does not fire until 500 ms after the press - on a 10.000-
;       line file scrolling to the end takes ~16 seconds of holding.
;       INT 16h AX=0305h BL=00 sets 30 cps with 250 ms: held keys scroll
;       3x faster (30 lines/sec) and the repeat starts in half the time
;       (~8 seconds for the same file). The AT keyboard BIOS (INT 16h
;       AH=03h) is available on AT (286+) and later; PC/XT is detected
;       via INT 15h AH=0C0h (system config: model byte >= 0FDh =
;       PCjr/XT/PC) and left alone. Done restores the IBM AT default
;       (BL=22h: 500 ms, ~10 cps). ~30 bytes, both builds; the INT 16h
;       call is a safe no-op on machines without the AT keyboard BIOS.
;       Version 1.35; the image stamp is "<4VIEW200>". SMART.INC stays
;       at v2.43.
;
; Revision 1.34 changes (168-170; the ESC-abort fix, the 386 U2A and the
; running line count - a review pass found three improvements):
;  168. ESC NOW REALLY ABORTS THE LOAD (fix 162 was dead code). FillBuf's
;       peek of the BIOS keyboard ring read the keystroke word from
;       0:[bx+0040h] - but bx holds the ring HEAD VALUE (an offset into
;       segment 0040h, typically 001Eh..003Ch), and the linear address
;       of 0040:[head] is 0:0400h+head, NOT 0:0040h+head. The code read
;       0:005Eh..0:007Ch (random low memory) instead of 0:041Eh..0:043Ch
;       (the keyboard ring): the value was never 011Bh, so the ESC was
;       never detected and the load could not be interrupted. One byte:
;       [bx+0040h] -> [bx+0400h]. The fix 151 comment that originated the
;       error ("a DS=0 form would need [bx+0040h]") is also corrected.
;       Verified: a pending ESC now makes FillBuf return 0, RdLine unwinds
;       through its EOF exit, CountLines closes with the lines counted so
;       far and Main's .case 01h picks up the untouched ESC and quits
;       through Done.
;  169. THE 386 BUILD'S U2A USES NATIVE DIV. The fix 13 shift chain
;       (division by 10 via shifts and adds) wins on an 8086 (DIV r/m16
;       costs 144-162 cycles, SHL ~2), but on a 386 DIV r/m16 drops to
;       14-22 cycles and the balance flips: the chain's 10+ shifts and
;       the .while correction loop cost more. The 386 path is now five
;       DIV bx (one per digit); the 8086 path keeps the shift chain
;       untouched. Same output contract (digits pushed AH=0, fix 148).
;       U2A is called 2-3 times per DrwSt and once per ShowProg block
;       (fix 170), so the gain is small in absolute terms but the code
;       is simpler and the 386 target stops paying the 8086 tax.
;  170. THE RUNNING LINE COUNT IS SHOWN DURING THE LOAD. The status bar
;       showed "Loading <path>..." with blinking dots and a 20-cell bar;
;       on a big file the bar repaints only 12 times per 385 KB and a
;       30 MB file that saturates at line 65.535 leaves the bar stuck at
;       2 cells for the whole load - the only sign of life was the
;       blinking dots. ShowProg now paints "L:NNNNN" (right-aligned,
;       columns 50..56) next to the bar on every 32 KiB block: the
;       growing line count is immediately visible. StatLoad's name clamp
;       shrinks 54 -> 46 to make room; U2A writes to a 16-byte scratch
;       at stBuf+80 (StatLoad uses 0..49, DrwSt 0..64, so 80..95 is
;       free). ~30 bytes + ~200 cycles per block, both builds.
;       Version 1.34; the image stamp is "<4VIEW34>". SMART.INC stays
;       at v2.43.
;
; Revision 1.33 fixes (167; the 100% state no longer wrecks the screen):
;  167. THE BAR'S LAST REFILLS WIPED THE SCREEN AND FROZE THE VIEWER:
;       fix 166's pos clamp DESTROYED the copy it was about to shift:
;       "sub ax,progSize / sbb dx,progSize+2 / jb @@posok" left DX:AX
;       holding the WRAPPED DIFFERENCE (curPos-progSize) on the keep
;       path - the branch every honest refill takes, since curPos <
;       progSize mid-file - and the normalization shift then scaled
;       THAT. The quotient climbed past 20 as curPos neared the end
;       (measured on the real 386 COM: 21 cells at 98.4% of a 30 MB
;       file), "mov cx,20 / sub cx,si" wrapped to 0FFFFh and the
;       empty-rail REP STOSW swept 131 KB across the video segment
;       (B800:0FA0 forward, wrapping twice): the whole screen became
;       the A_STAT mid-shade dither - the reported uniform teal - with
;       only the just-painted filled cells surviving as the black block
;       at columns 59-78 of the status row. The last ~130 refills kept
;       repainting the same wreck (the load's tail reads as a hang at
;       3300 cycles/ms) and the header row, never repainted after
;       Init, stayed wiped for good. The clamp now runs AFTER the
;       shift, where one unsigned 16-bit compare does it: pos16 =
;       curPos>>SI is clamped against BX = progSize>>SI (min(a,b)>>s =
;       min(a>>s,b>>s), so the quotient is untouched for pos <= size
;       and exactly 20 past it; curPos itself stays read-only).
;       THE ESTIMATOR'S DIV GUARD WAS ALSO INVERTED (166): "jb @@avok"
;       jumped to the saturated path when DX < CX - the one case where
;       the division is SAFE - and fell into the DIV when DX >= CX,
;       the exact #DE case. For every real file the average was forced
;       to 0FFFFh, the estimate stayed above progSize and the 166
;       rescale never engaged at all (files whose lines average 64 KB+
;       took the #DE instead). jae restores the intent: the running
;       average divides while it fits a 16-bit quotient and saturates
;       only when it would not. Verified by the Unicorn emulation of
;       the real 386 COM - the 30 MB non-saturating file that wiped at
;       98.4% now sweeps 0..20 with the screen intact; the 30 MB
;       saturating file finally gets the rescaled denominator (progSize
;       shrinks to 65.535*avg once totLines hits 256) and its bar
;       spans the ~4.2 MB the scan really reads; the 72 KB-line file
;       divides without #DE; 300 KB and 200 KB regressions stay clean -
;       plus the listing diff of both COMs. Version 1.33. SMART.INC
;       stays at v2.43.
;
; Revision 1.32 fixes (166; the bar spans the scan's REAL work):
;  166. THE BAR CRAWLED, THEN JUMPED: with the 65.535-line saturation
;       (fix 10) a 30 MB text file's scan covers only ~13% of the
;       bytes, so the byte-based bar could reach just 2 of its 20
;       cells before the load ended - the fix-165 beat made the final
;       20/20 state visible, but the 2-to-20 jump stayed abrupt ("it
;       fills one cell, fills the other, then all of them"). The bar's
;       DENOMINATOR now rescales: once totLines crosses EST_AT (256)
;       lines, the running average (curPos/totLines, 32/16 DIV with a
;       #DE guard) estimates where the saturation will stop the scan
;       (est = 65.535 * avg, one 16x16 MUL) and progSize SHRINKS to
;       it - min(est, progSize), so the bar can only speed up, never
;       jump back. The sweep then spans the ~4 MB the load really
;       reads and completes at 20/20 without a jump. When the scan
;       outgrows the estimate (heterogeneous line lengths), curPos is
;       clamped to progSize BEFORE the normalization shift - a
;       register copy, curPos stays read-only - so the quotient stays
;       exact (<= 20) instead of wrapping out of the 16-bit window.
;       One shot per load (estDone), invisible at the trigger (both
;       denominators still paint ~0 cells there), free in STDIN mode
;       (progSize = 0 exits before it), and it composes with the 165
;       beat: an estimate miss that still stalls the bar below 15
;       cells keeps its completion hold. ~55 bytes + 1 data byte; the
;       per-refill cost is one byte test (estDone). Verified by the
;       refill-by-refill bar timeline for 5 line lengths (the jump is
;       gone: in every stationary case the last refills paint 19-20
;       cells), a 100.000-case random quotient sweep with the clamp
;       (always 0..20, no #DE, no MUL overflow), the 64 KB-line guard
;       case (DX >= CX) and the listing diff of both COMs. Version
;       1.32. SMART.INC stays at v2.43.
;
; Revision 1.31 fixes (165; the completion hold actually fires):
;  165. THE FIX-164 HOLD WAS DEAD CODE: its condition read barCells
;       AFTER the final paint - which had just overwritten the last
;       refill's count with exactly 20 - so "below 15" was never true
;       and the hold never ran: the bar still vanished from its last
;       sweep value (2 cells on the reported 30 MB file), 1.30 behaved
;       exactly like 1.29. The count is now SNAPPED into BL before the
;       final ShowProg (whose uses-list keeps BL alive across the
;       call) and the hold tests the snapshot: it fires exactly when
;       the sweep stopped below 15 cells. The beat is widened to 8
;       ticks (~440 ms) so the jump to the full bar is unambiguous.
;       Verified by an instruction-faithful trace of both tails (the
;       1.30 order holds 0 of the 6 traced scenarios - the proof of
;       the bug - the 1.31 order holds exactly the sub-75% ones), by
;       the re-run of the 1..4 GiB-1 quotient sweep (final paint =
;       exactly 20, no MUL overflow, no #DE) and by the listing diff
;       of both COM images. Version 1.31. SMART.INC stays at v2.43.
;
; Revision 1.30 fixes (164; the completed bar becomes perceptible):
;  164. THE COMPLETED BAR WAS INVISIBLE: fix 163 painted the final
;       20/20 cells, but that paint lasted only the microseconds DrwSt
;       needs to reach the status repaint - on the saturating case
;       (fix 10's 65.535-line early exit stops a 30 MB text scan ~13%
;       in, so the bar's honest sweep ends at 2 cells) the bar seemed
;       to vanish from 2 cells, "as if the load never finished". The
;       completion now gets a hold: ShowProg leaves its filled-cell
;       count in barCells, and CountLines - right after the final
;       paint - freezes ~6 BIOS ticks (~330 ms) when the last refill's
;       bar sat below 15 cells (75%): the jump to the full bar is the
;       visible "load done" beat exactly where the sweep stopped far
;       from it. Loads whose sweep reached 19-20 cells (any file over
;       ~640 KB) keep ending at full speed: the near-full bar was
;       already on screen for the whole last 32 KiB block. An ESC-
;       aborted scan holds too - the beat delays Done by ~330 ms,
;       harmless. The wait polls the BIOS tick word at 0:046Ch for 6
;       EDGES (wrap-safe, no DOS call; AX/SI are dead there), ~30
;       bytes both builds. Version 1.30. SMART.INC stays at v2.43.
;
; Revision 1.29 fixes (163; the load bar completes its sweep):
;  163. THE PROGRESS BAR NEVER PAINTED 100%: ShowProg repaints at every
;       FillBuf refill from curPos, but curPos is materialized ONCE PER
;       LINE (RdLine's @@dones), so the last paint always ran behind the
;       reads - and CountLines retired progSize without painting again.
;       Two freezes, both hit by a 30 MB text file:
;       - the scan SATURATES at line 65.535 (fix 10) and breaks out
;         MID-FILE: 65.535 lines of ~60 bytes is ~4 MB, so the bar froze
;         at ~13% of 20 cells and the load ended right there;
;       - a file whose last line lacks the trailing CRLF hits the EOF
;         refill mid-line, whose paint ran with the STALE line-start
;         curPos (~95%): only files ending in CRLF flashed 100%, by
;         luck of their refill falling between lines.
;       The fix is five instructions in CountLines: after the scan loop
;       curPos is forced to progSize and ShowProg runs ONE more time -
;       the quotient is exactly 20/20 cells whether the scan reached
;       the EOF or saturated mid-file; progSize is retired right after
;       and the existing curPos=0 reset follows, so nothing else moves.
;       An ESC-aborted scan flashes its forced 100% for the few
;       instructions before Done restores the screen. ~100 cycles once
;       per load, both builds.
;       Version 1.29. SMART.INC stays at v2.43.
;
; Revision 1.28 fixes (160-162; the follow-up performance pass - real
; and perceived. A full re-read of the 1.27 source; both builds
; re-assembled with ASMC and the COM images diffed against 1.27: the
; only diffs are the intended instructions, the version digits and
; the @Time stamp of the About box. The scanner state machine is
; untouched, so the fix-155 simulator (scripts/sim_store386_127.py)
; stays authoritative for the store/consume semantics):
;  160. THE -3 SCANNERS AND PAINT LOOPS STOP PAYING THE MICROCODED
;       STRING-OP TOLL: on a 386 LODSD costs ~12 cycles and STOSD ~11
;       (LODSB/STOSB the same) while MOV EAX,[SI] is 4 and MOV [DI],r
;       is 4 - the single (non-REP) string forms only pay off when REP
;       amortizes them, and none of these sites is REP. The four hot
;       sites move to MOV + pointer-add, 8086 code untouched:
;       - the count scan's LODSD (fix 79) becomes MOV EAX,[SI]/ADD
;         SI,4: ~1.5 cycles/byte less on the ~7.5 of the pre-scan that
;         IS the load pass (~20% off it);
;       - the store scan's LODSD + "mov eax,ebp"/STOSD (fixes 80/142)
;         become MOV EAX,[SI]/ADD SI,4 and MOV [DI],EBP/ADD DI,4: ~13
;         cycles less per stored dword on the parse PgDn/PgUp pay 23
;         times per page (the fix 142 park stays - the dword now
;         stores straight from EBP, the EAX feed is gone);
;       - the candidate re-scan tails (@@sr/@@dr) swap LODSB/STOSB for
;         MOV/INC: 6+6 instead of 12+11 per re-scanned byte (the
;         TAB-heavy lines);
;       - WrCntRow's two pair loops swap LODSW (12->6) and both STOSW
;         (11->5+2, ES override) on -3: ~14 cycles less per pair on
;         every painted row.
;  161. THE 8086 PAIR LOADS GO THROUGH MOV: LODSW is 16 cycles on an
;       8086, MOV AX,[SI] is 10 (8+EA 2) and ADD SI,2 is 4 - 2 cycles
;       less per pair. Applied to the four LODSW of the count scan's
;       8-byte unroll (the load pass: ~1 cycle/byte off the ~22 of fix
;       67), the store scanner's pair loop (fix 60's ~44.5/byte path;
;       the STOSB stores STAY: 11 beats MOV [DI],AL+INC DI 16, fix
;       60's own measurement) and WrCntRow's pair loops (shared code,
;       both builds win). The candidate contract is untouched: MOV
;       AX,[SI] leaves AL/AH and SI exactly where LODSW did (the @@c1
;       handler still finds P2 in AH, fix 141). The byte tails keep
;       LODSB everywhere: 12 beats 10+3 there.
;  162. ESC INTERRUPTS THE LOAD: the pre-scan is the one stretch where
;       4VIEW ignores the keyboard (an 8088 needs ~1.8 s for 385 KB;
;       fixes 70/86/156 made the wait visible and painted the first
;       view early, but ESC stayed queued until the WHOLE scan ended).
;       FillBuf now peeks the BIOS ring once per 32 KiB refill (zero
;       per-line cost) and, ONLY while the load pass runs (progSize
;       != 0 - fix 86's exact lifetime), a PENDING ESC - never
;       consumed - makes the refill report 0 bytes: RdLine unwinds
;       through its normal EOF exit, CountLines closes with the lines
;       counted so far, the first Draw paints the captured view and
;       Main's loop finds the untouched ESC and quits through the
;       normal path (Done restores the screen). The fake EOF is
;       unobservable: nothing can rely on the truncated totLines
;       before the queued ESC quits, a typed-ahead non-ESC key keeps
;       waiting, and the viewing refills (GoLine, cold fills, the
;       ScrUp rescan) are gated out by the progSize test. ~45 bytes
;       and ~100 cycles per block on both builds.
;       Version 1.28; the image stamp is "<4VIEW28>". SMART.INC stays
;       at v2.43.
;
; Revision 1.27 fixes (155-159; a full read of the 1.26 source plus a
; source-level Python re-simulation of the 386 store scanner over
; block-straddling corpora - scripts/sim_store386_127.py, the same
; method the 1.24 pass used; both builds re-assembled with ASMC and
; the changed sites diffed against the 1.26 images):
;  155. THE -3 BUILD TRUNCATED EVERY DISPLAY LINE CROSSING A 32 KiB
;       BLOCK EDGE (fix 142 regression). The store scanner's SWAR
;       rounds park the clean dword in EBP ("mov ebp,eax"), and BP
;       doubles as RdLine's store/consume flag - tested once per line
;       at @@fx. Fix 142's comment claimed "BP is read only at the @@fx
;       entry", but @@fx IS re-entered after every refill (fix 121:
;       @@rfin jumps there): a round that ends exactly at the block end
;       takes @@sloop's "jz @@refill" with BP = the last dword, FillBuf
;       reloads the block, and @@fx's "or bp,bp" then tests the dword's
;       LOW word - nonzero for any ASCII pair - and switches the REST
;       of the line to CONSUME mode: nothing more is stored, the slot's
;       length byte counts only the stored part and WrCntRow paints the
;       line cut at the 32 KiB multiple (curPos/vPos stay exact: the
;       consume scan still walks to the true EOL, only the text is
;       lost). Reachable from DrwCnt's and DrwDn1's cold fills, DrwUp1
;       and the ScrUp rescan - i.e. every PgDn/PgUp beyond the cache
;       and every Up across a boundary on the -3 build. The 8086 build
;       never touches BP in its store rounds and was always right (as
;       was the -3 count scan: @@fw/@@fwn use EAX/EDX only, so the load
;       pass never showed it). The store scanner's flag is logically 0
;       by construction (only @@sful can set it to 1, and it runs
;       BEFORE any round), so the round end restores it: "xor bp,bp"
;       after @@swn's DEC/JNZ, 2 bytes on -3, ~2 cycles per round
;       (a round is hundreds of bytes), and the refill continuation
;       keeps its mode for ANY line/block layout. The simulator
;       reproduces the truncation on 1.26's algorithm and 0 mismatches
;       with the fix over every corpus.
;  156. VIEW #1 IS PAINTED THE MOMENT IT IS CAPTURED (the reported
;       "dibuja la primera pantalla en cuanto este cargada"): CountLines
;       already parsed lines 0..22 in store mode into their vCache
;       slots (fixes 55/85), but the first paint waited for the WHOLE
;       pre-scan - a big file showed only the chrome, "Loading ..."
;       and the progress bar for the entire scan (~1.8 s per 385 KB on
;       an 8088@4.77, versus ~35 ms to parse 23 lines and paint them).
;       The capture-complete branch now calls RingPaint ONCE - the
;       totLines==LINES_VIS-1 test fires exactly once per file, the
;       slots and vPos entries are already consistent, curLine=0,
;       ringN=23 - and the pre-scan continues in count mode with the
;       bar repainting per block (FillBuf/ShowProg). RingPaint DIRECTLY,
;       NOT Draw/DrwCnt: mid-scan curPos is the start of line 23, NOT
;       of line 0, so DrwCnt's cold path would parse the WRONG 23 lines
;       into the slots and corrupt the capture; DrwBar would read
;       totLines=22 and paint a full thumb contradicting the bar; and
;       DrwSt would wipe the "Loading ..." text and the bar cells.
;       RingPaint touches rows 1..23 only: the status row keeps the
;       loading text, the blinking dots and the bar, the scrollbar stays
;       rail-only (honest: the size is not known yet) and the first
;       real Draw after the scan repaints everything with the true
;       numbers. STDIN keeps its FillStdin+Draw flow: a pipe may stall
;       mid-fill, and its first screen IS the first 23 lines.
;  157. RINGPAINT'S WRAP LIMIT VIA THE AH TRICK on the 8086: "mov
;       ax,ringN / shl ax,8" expanded to EIGHT 1-bit shifts (fix 95
;       hoisted the computation out of the row loop, but the chain
;       stayed). "mov ah,byte ptr ringN / xor al,al" is 2 instructions
;       for any ringN < 256 - the same addressing SLOTPTR uses; the -3
;       build keeps its single native "shl ax,8". ~16 bytes and ~16
;       cycles less per repaint on an 8086, zero change on -3.
;  158. RDLINE'S ENTRY NUL STORE IS DEAD: "mov byte ptr [di],0" ran
;       before the scanners, but RdLine has ONE exit (@@ret0) and the
;       shared @@dones epilogue ALWAYS writes the NUL at [di] and the
;       length byte before it - no path reads wDest mid-call. 3 bytes
;       and ~14 cycles per line off the load pass; the fix 97
;       write-before-read audit for lBuf now rests on the exit alone
;       (still before any paint).
;  159. DRWBAR'S "jz @@d" AFTER "sub bx,LINES_VIS" IS UNREACHABLE: the
;       thumb section only runs for totLines >= 24 (the "jbe @@f" above
;       routed totLines <= 23 to the full-thumb path), so bx =
;       totLines-23 >= 1 and the zero test never fired. 2 bytes less
;       (the same dead-code class as fix 147). Version 1.27; the image
;       stamp is "<4VIEW27>". SMART.INC stays at v2.43.
;
; Revision 1.26 fixes (152-154; the 1.25 audit - full read of the source
; plus a numeric re-verification of the arithmetic blocks: U2A over the
; whole 16-bit range, FastIMul for every constant -32768..65535 and
; FastMul for the factors this code uses, both against a 32-bit
; reference, zero failures; SMART.INC needs no change):
;  152. FULLPATH'S LENGTH CLAMP WAS INVERTED: the "ja @@okl" aimed the
;       65..128-char Truename results AT the copy (fName holds 65 bytes:
;       CX up to 128 overran it into lBuf, and DrwHdr's "mov cx,160 /
;       sub cx,di" row pad went NEGATIVE - shr cx,1 turned 0FF86h into
;       ~32.700 words and the rep stosw swept the whole video segment
;       the moment Init repainted the title after FullPath, both builds),
;       while the 0..64-char paths were force-clamped UP to a fixed
;       64-byte copy that only worked thanks to the embedded NUL. The
;       jump now goes to @@keep: a path that does not fit keeps the name
;       as typed (the documented behavior since 1.01), anything else
;       copies its own length. 3 bytes less, and the fName/title/
;       StatLoad layout contract holds by construction again.
;  153. THE TWO SLOT-WRAP TESTS ARE UNSIGNED BY OPCODE: the ".if (bx >=
;       offset vCache+LINES_VIS*SLOTSZ)" of DrwDn1's cold fill and
;       DrwCnt's repaint only compared unsigned because 0CA07h does not
;       fit SWORD (fix 149's exception to the signed-.if rule); explicit
;       cmp/jb keeps the branch unsigned for ANY image layout at an
;       identical byte count, joining the discipline of fixes 93/129/140.
;  154. BLKCP'S EVEN-COUNT CONTRACT DOCUMENTED (zero code change): the
;       copy runs MOVSW/MOVSD, so an odd CX would silently drop the tail
;       byte; every call site passes an even count (4000 for the page
;       save/restore, the popup rows, ringN*256 for the view buffer) and
;       CpyN serves any-count copies. Version 1.26; the image stamp is
;       "<4VIEW26>". SMART.INC stays at v2.43.
;
; Revision 1.25 changes (151; the idle key poll - the hottest loop of the
; program, ~1900 passes per keypress (fix 81) - verified by assembling
; both builds with ASMC and diffing the COM images: the only diffs are
; the intended bytes below):
;  151. KEYAVAIL SETS DS=0, NOT DS=0040h: the poll loaded the BIOS data
;       segment with "mov ax,0040h / mov ds,ax" (5 bytes, 4+2 cycles on
;       an 8086) although the ring head/tail words live just as well at
;       LINEAR 0:0041Ah/0:0041Ch: "xor ax,ax / mov ds,ax" is 4 bytes and
;       3+2 cycles, and the direct displacements only gain the segment
;       nibble (A1 1A 00 -> A1 1A 04, 3B 06 1C 00 -> 3B 06 1C 04) at
;       zero byte cost. 1 byte and 1 cycle less per expansion, 3
;       expansions per poll loop set (Main idle, End drain, mouse drag):
;       3 bytes per build, ~1900 cycles per keypress on an 8088, and the
;       386 build keeps its cycles (xor == mov imm there). ReadKey KEEPS
;       DS=0040h (fix 25): it dereferences the head VALUE in BX
;       ("mov ax,[bx]"), and a DS=0 form would need [bx+0400h] (the linear
;       base of segment 0040h is 0400h, not 0040h - fix 168) - 8B 87 00 04
;       vs 8B 07: 1 byte MORE and 4 cycles more on an 8086, net worse
;       in both builds. The image stamp moves to "<4VIEW25>".
;
; Revision 1.24 fixes (141-150; a full read of the 1.23 source against the
; machine simulation: every change was first proven equivalent by the
; scripts/sim_rdline_124.py and sim_wrcntrow_124.py models - block sizes
; 8, 16 and 32 to stress every block edge - and then checked at the BYTE
; level by assembling both builds with ASMC and diffing the COM images:
; the only diffs are the intended instructions below):
;  141. RDLINE'S @@c1 RE-READS [si-1] FOR NOTHING: the store scanner's P1-CR
;       handler tested the CRLF partner with "cmp byte ptr [si-1],10" - a
;       memory EA + read (~13-17 cycles on an 8086) - although the partner
;       is ALREADY LOADED in AH: @@c1 is reached only from @@sp, one
;       instruction after the LODSW that put P2 in AH (fix 54's own comment
;       says "the partner is the ALREADY LOADED AH"; the 1.23 code
;       contradicted it). "cmp ah,10" is behaviorally identical - proven by
;       the simulator, which asserts AH == [si-1] at every @@c1 - and 1 byte
;       less: ~13 cycles saved per CRLF line ending at an ODD slot of the
;       display parse, the most common line ending of DOS text. The runtime
;       assertion is dropped in 1.24: the single-line code cannot diverge.
;  142. THE 386 STORE SCANNER KEEPS THE DWORD IN EBP: after the SWAR test
;       said "no candidate", the clean dword was re-read from memory
;       ("mov eax,[si-4]" = 66 8B 44 FC: MOV r,m costs 4 cycles on a 386
;       against 2 for MOV r,r, plus a bus read racing the prefetch queue)
;       although LODSD had just fetched it. EBP is DEAD inside the scanner body
;       (BP's store/consume flag is read only at the @@fx entry - @@full,
;       reached from @@sful, never tests it), so "mov ebp,eax" parks the
;       dword in the register and "mov eax,ebp" feeds the STOSD: one bus
;       read less per stored dword on the parse that PgDn/PgUp pay 23
;       times per page. RdLine's uses list already restores BP. The
;       simulator runs the reload and the EBP forms through the same
;       corpora with identical output.
;  143. WRCNTROW'S PAIR LOOPS READ ONE LODSW PER TWO CELLS: the old pair
;       tested and stored each byte separately (11 instructions, ~73
;       cycles per pair on an 8086: LODSW + 4 CMP/Jcc + 2 STOSB + MOV +
;       LOOP). Both loops now build the two cells from ONE LODSW - BH
;       carries ATTR_CONT, "mov bl,ah" saves the second char and "mov
;       ah,bh" joins the attribute to the first: 6 instructions, ~63
;       cycles per pair (8086) and ~25% less on the -3 build. BX is the
;       callers' slot cursor (DrwCnt walks the view with it), so one
;       PUSH BX/POP BX pair guards the paint section - the documented
;       "clobbers AX CX SI DI only" contract is unchanged, and DX/BP
;       (RingPaint's wrap limit, DrwCnt's vPos cursor and row base) are
;       never touched. The 77-cell output is identical for every
;       (len, hPos, content) combination: sim_wrcntrow_124.py runs the
;       226.950-case matrix of both loops, 0 differences.
;  144. RDLINE'S @@refill WRITES A DEAD bIdx: "mov ax,si / sub ax,offset
;       bBuf / mov bIdx,ax" is 8 bytes that FillBuf always overwrites
;       ("mov bIdx,0" is unconditional in FillBuf) and that no continuation
;       reads: the EOF exit jumps to @@dones with bIdx=0 (correct - curPos
;       = the new bBase = EOF) and @@rfin recomputes everything from SI.
;       8 bytes and ~9 cycles per 32 KiB block removed.
;  145. THE ORPHAN @@eof LABEL IS GONE: nothing jumps to it since fix 107
;       routed the refill EOF through "xor dx,dx / jmp @@dones" (the label
;       only documented a path that no longer exists); @@donef falls
;       through to @@dones exactly as before. The fix 107 note lives at
;       the branch that forces DX.
;  146. COUNTLINES RESETS wDest ONLY WHEN IT MATTERS: the "mov
;       wDest,offset lBuf" after each captured line ran for lines 0..21
;       although the next capture re-arms wDest to its slot and RdLine
;       only needs a real wDest from line 23 on (count mode's @@dones
;       writes the NUL and the length byte there). The reset moved below
;       the == LINES_VIS-1 test: 6 bytes of code saved, 3 bytes of runtime
;       per captured line, behavior identical (the capture path re-arms
;       wDest before every stored RdLine).
;  147. MOUSEPOLL'S totLines CLAMP IS UNREACHABLE: row <= 22 puts the
;       clicked line at row*(tot-23)/22 <= tot-23, and tot-23 < totLines
;       always (tot > LINES_VIS is guaranteed by the jbe above) - the
;       "cmp ax,totLines / jb @@clp / mov ax,totLines / dec ax" never
;       fires (proven by brute force over tot 24..65535 x row 0..22:
;       0 cases reach the clamp, minimum margin 65534). The 4 bytes are
;       gone and the STRONGER invariant curLine <= totLines-23 - which
;       DrwBar's DIV and DrwSt's percent rely on - is what the code now
;       keeps.
;  148. U2A POPS THE DIGIT INTO AX: the digits are pushed with AH=0 (the
;       corrected remainder is < 10), so "pop ax / add al,'0' / stosb"
;       replaces "pop dx / add dl,'0' / mov al,dl / stosb": 2 bytes and
;       2 cycles less per digit, verified over all 65536 values against
;       the decimal reference (scripts/verify_u2a_clamp.py - the 1.23
;       algorithm is already exact for the whole 16-bit range).
;  149. VERIFICATION NOTE - THE .if SIGNEDNESS SCARE OF THE FIX 148 DRAFT:
;       the two "bx >= offset vCache+LINES_VIS*SLOTSZ" slot-wrap tests
;       were flagged as SIGNED-overflow risks (an image past 8000h would
;       flip the compare), but the ASMC listing of the 1.23 build shows
;       the emitted branch is ALREADY "jb" (unsigned): the constant
;       0CA07h does not fit SWORD, so ASMC classifies the compare as
;       unsigned, and with the threshold below 8000h every BX it can
;       reach is positive too - correct for ANY image layout. No byte is
;       changed; the finding retires the draft fix and documents the one
;       exception to the blanket "ASMC's .if is SIGNED" rule of fixes
;       93/129/140 (immediates above 7FFFh compare unsigned).
;  150. Version 1.24; the image stamp is "<4VIEW24>". SMART.INC stays at
;       v2.43 (audited as part of this pass: the FastMul 386 paths, the
;       shift macro bodies and the FastIMul chain are correct, and the
;       macros 4VIEW does not use cost nothing in the image).
;
; Revision 1.23 fixes (139-140; found with a byte-faithful 8086/386+DOS
; machine simulation running the FULL program twice per session and
; comparing the instruction streams, the DOS calls and the VIDEO PAGE
; between the two runs):
;  139. THE REPORTED LOAD HANG - "SE CUELGAN CARGANDO EL ARCHIVO" ON THE
;       SECOND LAUNCH, BOTH BUILDS. Fix 70's blink repaint of the loading
;       dots pushed the ABSOLUTE di (stBuf+offset) as if it were the
;       OFFSET, then added stBuf again: SI = 2*stBuf+dots landed INSIDE
;       bBuf, and DI = 24*160+2 + 2*(stBuf+dots) painted far past the
;       visible page. The .while (byte ptr [si]) therefore scanned the
;       buffered FILE BLOCK instead of the three dots - and the stosw of
;       every iteration wrote file characters (blink attribute) into the
;       video page, wrapping over ALL 25 rows on every 4 KiB pass. On the
;       FIRST launch the freshly allocated arena is zeroed, so the scan
;       exits after zero iterations and the load looks perfect; DOS gives
;       the SECOND launch the SAME memory block the first run released
;       WITHOUT zeroing it, bBuf still holds the previous run's file
;       bytes (a text file has no 00h), and the scan walks ~33 KB of RAM
;       (it stops on vCache, which Init clears) while sweeping the whole
;       screen with garbage for the ENTIRE load: the user sees a screen
;       full of blinking junk with the status text erased and reads it as
;       a hang. Both builds share StatLoad, hence both hang; the same
;       file matters only because it fills bBuf in run 1. THE FIX: push
;       the real OFFSET (sub ax,offset stBuf before the push), take SI
;       = stBuf+AX and DI = 24*160+2+2*AX. Same instruction count, the
;       dots finally blink WHERE fix 70 wanted them (visible now), and
;       the sweep is gone. Verified in the simulator: the second run's
;       video page during the load is byte-identical to the first's.
;  140. FullPath's length clamp joins fix 93's unsigned discipline:
;       .if (cx>64) is ASMC SIGNED; the Truename length is 0..128 so it
;       could never trigger the signed failure mode, but cmp/ja makes
;       the intent explicit at zero byte cost.
;
; Revision 1.22 fixes (133-138, the maximum-performance pass over the
; 1.21 source; see the full narratives at the end of this header):
;  133. The 386 SWAR zero test computes its tail with LEA+NOT instead
;       of MOV+SUB+NOT: EDX takes cand-01010101h while EAX KEEPS cand,
;       so the NOT eats the copy move and (cand-1)&~cand costs 3 ops
;       instead of 4; TEST doubles as the final mask (EAX is dead past
;       the branch). One op less per dword in BOTH 386 scanners.
;  134. LOOP is 11 cycles taken on a 386 while DEC+JNZ is 9 (and LOOP
;       stays the slow way on every later CPU); every loop the -3
;       build executes (both scanner tails, WrCntRow's two paint
;       loops, the @@t4b byte tail) is DEC/JNZ on -3 now. The 8086
;       build keeps LOOP everywhere - there LOOP (17) beats DEC+JNZ
;       (3+16) and fix 67's unroll-8 already halved its toll.
;  135. The consume re-scan tails (@@dr, @@t4b, BOTH builds) tested
;       AL twice: the JA branch preserves the CMP flags, so the second
;       "cmp al,3" before the JE was dead code - 2 bytes and 2 cycles
;       per re-scanned byte, gone.
;  136. RdLine's thirteen duplicated line-exit stubs (mov dx,1 / jmp
;       or dec si|inc si + mov dx,1 / jmp, three variants x four to
;       five copies) collapsed into the canonical @@lfx / @@decf /
;       @@cr4e / @@crd2: about 40 bytes less and one shared contract
;       ("what SI/DX state does each exit leave") stated once. The
;       hot exits stay zero-extra-hop: count-mode CRLF ends via
;       @@cr4e and LF via @@lfx directly.
;  137. The fix 131 CPU guard ends with JNZ over the fail path instead
;       of JZ + an explicit JMP (3 bytes less, same behavior).
;  138. Version 1.22; the image stamp is "<4VIEW22>". SMART.INC stays
;       at v2.43. A 2x SWAR unroll was modeled and REJECTED: the
;       pair-count accounting breaks under candidate parity shifts
;       (a whole-pair rescan fixes slot A but conflicts with the odd
;       dword peel's continuation), and ~110 bytes for ~7% did not
;       beat fixes 133+134, which deliver most of the win at ~zero
;       cost.
;
; Revision 1.21 fixes (129-132; see the full narratives at the end of
; this header, in the "Revision 1.21 fixes" block):
;  129. GetByte tested bIdx against bLen with ASMC's SIGNED .if - fix
;       118's BUFSZ=8000h makes a full block's bLen read as -32768, so
;       every mid-block peek of the unget path "refilled" 32 KiB early
;       and skipped the block: a CR at the last byte of a full block
;       loaded as garbage (proven by simulation: 2 lines instead of 7
;       on a 200 KB corpus). Now an unsigned cmp/jb, like fix 93 taught
;       everywhere else.
;  130. Fix 127's "exact at the block edge" claim was wrong: @@crhi's
;       GetByte advances bIdx PAST the ungot byte, so curPos = P+1 with
;       the ungot byte at P - every observer (vPos, CachePos, SeekSoft)
;       rode 1 byte late and a SeekSoft dropped the next line's first
;       character. @@dones now subtracts the pending unget (DEC never
;       touches CF, so the ADC into curPos+2 is unaffected; bIdx >= 1
;       whenever hFull is set, so the DEC cannot borrow).
;  131. THE 386 BUILD FROZE PRE-386 MACHINES AT STARTUP: the first
;       386-only instruction (Init's BLKFIL/BLKCP pop eax/movzx ecx)
;       derails any 8086/186/286 the moment Init starts - on an 8086
;       0Fh decodes as POP CS and the machine freezes with the screen
;       half-painted, exactly "la 386 se cuelga al arrancar", while the
;       8086 build runs everywhere (the same mismatch class as fix
;       105). A pushf/popf probe (pure 8086 instructions, ~20 cycles
;       once) now checks the CPU BEFORE any 386 instruction executes
;       and exits with "requires a 386" instead of freezing. Every
;       -3 startup path (BLKCP/BLKFIL/CpyN, both SWAR scanners, FastMul,
;       the block-edge unget/refill engine) was re-verified by a
;       byte-faithful machine simulation over the edge-case corpora:
;       no in-code infinite loop exists on -3; the freeze reproduced
;       only on a pre-386 CPU.
;
; Revision 1.20 fixes (the simplification/optimization pass over the 1.19
; source; see fixes 117-126 at the end of this header): Seek folds into
; SeekSoft and preserves CX, BUFSZ doubles to 32 KiB (free in the file
; since fix 115), Init clears only the view slots the mode uses, WrCntRow's
; paint loop unrolls by two, RdLine's refill shares the fresh-block
; recompute with the entry, DrwUp1's slot wrap is dec/jns, ParseCmd's two
; name loops merge into one, and the curPos save/restore sites use the
; SAVEPOS/RESTPOS macros (zero code change). The battery also caught a
; pre-existing 8086 bug: the consume scanner's CR-at-P2 case peeked
; through GetByte mid-block, leaving curPos 1 byte late (fix 127), and
; KeyAvail became a plain macro (the ASMC-only .INLINE PROTO form is
; gone, byte-identical binaries, fix 128).
;
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
; SMART.INC v2.43 must sit next to 4VIEW.ASM or on the include path.
; NOTE: the high level flow uses ASMC's .SWITCH (fix 24; JWasm and UASM
; do not implement it), so ASMC is the one assembler that builds the
; file as is.
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
;
; Revision 1.20 fixes:
; 117. SEEK FOLDS INTO SEEKSOFT: the real-seek body had exactly one caller
;      left (SeekSoft's @@hard jmp) and duplicated the isFile guard, the
;      hFull=0 (a DEAD store there: SeekSoft's entry had already cleared
;      it) and the bBase/bLen/bIdx reset. The body is now SeekSoft's
;      @@hard tail - and it PRESERVES CX: push cx/pop cx around the AH=42h
;      costs 2 bytes once, so NO caller clobbers CX any more. Main's PgUp
;      loop drops its push/pop (23 per press) and the "CX survives ScrDn
;      but only ScrUp can reach the CX-clobbering Seek" caveat of fixes
;      101/103 retires: both directions keep CX now.
; 118. BUFSZ 16 KiB -> 32 KiB. The old reason not to ("32 KiB would grow
;      the COM by 16 KiB", fix 41) died with fix 115: bBuf is a RAM
;      offset beyond the image, so the FILE stays ~6 KB. 12 DOS reads per
;      385 KB instead of 24 - half the AH=3Fh overhead and half the
;      @@refill round-restarts on the load pass. The segment is 64 KB for
;      a COM either way; BMEMTOP reaches 57.884 of 65.534 and the deepest
;      call chain (Init -> CountLines -> RdLine -> FillBuf -> ShowProg)
;      uses under 100 bytes, so ~7.6 KB of stack stay free.
; 119. INIT CLEARS ONLY THE SLOTS IN USE: vCache was always cleared
;      RSLOTS*SLOTSZ = 11.776 bytes, but file mode reads slots 0..22
;      (ringN = 23). The ringN setup moves ABOVE the clear and CX becomes
;      ringN*256: file mode clears 5.888 bytes - the 8086 load pass saves
;      ~62.000 cycles (~5 ms @ 12.5 MHz). STDIN still clears all 46. No
;      read exists below the ring in either mode (RingPaint wraps at
;      ringN, the file paths index 0..22).
; 120. WRCNTROW'S PAINT LOOP UNROLLED BY TWO: the 1..76-char rows (most
;      real lines - the 77-char @@full case was already paired) now eat
;      two chars per iteration: ~45.5 instead of ~54 8086 cycles per
;      char. shr cx,1 leaves the pair count and CF = odd char, the odd
;      char is painted first, jcxz catches the one-char lines. The pad
;      count still waits on the stack while LODSB runs. A 23-row repaint
;      with 40-char lines drops ~7.700 cycles.
; 121. RDLINE'S REFILL SHARES THE FRESH-BLOCK RECOMPUTE: the entry and
;      @@rfin both did "mov si,bBuf [+bIdx] / mov bx,bLen / add bx,bBuf /
;      mov ax,bx / sub ax,si / or bp,bp / jnz @@full". The block is now
;      @@fx behind the entry's "add si,bIdx" (FillBuf left bIdx=0, so
;      @@rfin just reloads SI and jumps there): 11 bytes less and the
;      @@full entry contract is stated once.
; 122. DRWUP1'S SLOT WRAP IS DEC/JNS: ".if (vSlot) dec .else mov 22" cost
;      cmp+je+dec+jmp+mov; dec vSlot / jns / mov 22 is 3 instructions (the
;      0 -> 0FFh wrap sets SF). Same result for every vSlot 0..22.
; 123. PARSECMD'S TWO NAME LOOPS MERGED INTO ONE: quoted and unquoted
;      names differ only in their terminator (quote vs space/tab). One
;      loop with BH as the quoted flag serves both, and LODSB reads both
;      (the unquoted path paid "mov al,[si] / inc si" - LODSB is the same
;      in 1 byte; SI is dead after the loop either way).
; 124. SAVEPOS/RESTPOS MACROS: the 32-bit curPos save/restore pattern was
;      written out at five save and three restore sites (DrwUp1, DrwDn1,
;      DrwCnt, ScrUp, CountLines). Two macros now emit exactly the
;      instructions they replace (the SLOTPTR/VPSTORE pattern of fix 74);
;      DrwCnt's AX/DX variant even loses 4 bytes - the AX form of
;      "mov reg,mem" is one byte shorter than the DX form.
; 125. DrwHdr's header comment still said "1.17" - now version-agnostic.
; 126. Version 1.20 (still SMART.INC v2.43); the image stamp is
;      "<4VIEW20>".
; 127. THE CONSUME SCANNER PARKED A BYTE AND SKEWED curPos BY 1: the
;      8086 unroll's CR-at-P2/P4/P6/P8 case jumped straight to @@crhi,
;      whose GetByte peek is only EXACT at a block edge (there the byte
;      lands at bIdx 0 of the fresh block, so curPos = its position).
;      MID-block, GetByte advanced bIdx PAST the byte it pushed into the
;      unget slot: RdLine exited with curPos = next line's start + 1 and
;      the next line's first char parked in hByte. The next RdLine
;      repainted the text fine, but every curPos OBSERVER in that window
;      saw the skew: GoLine's cache entries (End, scrollbar clicks) and
;      its final curPos, and SeekSoft - which clears the unget slot -
;      then re-anchors bIdx one byte INTO the line, so the first painted
;      row lost its first character. Only CR-only line endings were
;      exposed (CRLF consumes the LF, LF-only never reaches @@crhi), and
;      only when the CR sat at an EVEN slot of the 8-byte round. Found
;      by the new Unicorn battery (scripts/verify_120.py): GoLine walks
;      disagreed with the reference splitter by exactly 1 on 9 of 20
;      positions - byte-for-byte the same on the 1.19 binaries, so the
;      bug predates this pass. THE FIX: @@candhi's CR case gets its own
;      @@crh2 with an INLINE mid-block peek (like the store scanner's
;      @@c2); only si>=bx still falls to @@crhi. The 386 build is
;      untouched - its SWAR rounds re-scan candidates byte per byte.
; 128. KEYAVAIL IS A PLAIN MACRO: the .INLINE "PROTO asmcall { body }"
;      form was an ASMC-only extension nobody else parses. A macro
;      expands the same six instructions at the same three call sites,
;      so the emitted code is identical (verified: both builds differ
;      from the PROTO form in the About box time stamp only) and the
;      source loses its one hidden-language-feature dependency. The
;      .SWITCH PASCAL dispatcher of fix 24 stays - it is documented
;      ASMC high level flow, not an accident.
;
; Revision 1.21 fixes:
; 129. GETBYTE'S BLOCK TEST WAS SIGNED (an 118 fallout): fix 118 doubled
;      BUFSZ to 8000h, and ".if (bx>=bLen)" is a SIGNED compare in
;      ASMC (fixes 23/31/93 already knew) - a FULL 32 KiB block's bLen
;      is 8000h, which reads as -32768, so EVERY mid-block GetByte of
;      the unget path took the refill branch: bBase jumped a full
;      block ahead (the DOS pointer stays consistent - no crash) and
;      each consumed byte skipped up to 32 KiB of file. The path only
;      wakes for CR-at-block-edge / >254-char / STDIN-unget lines, so
;      plain CRLF text never noticed - but a CR in the LAST byte of a
;      full block turned every following line into garbage and the
;      line count with it (machine-simulated: a 200 KB corpus with CRs
;      at 32767/65535/... counted 2 lines instead of 7 on BOTH builds).
;      cmp bx,bLen / jb is the unsigned form fix 93 taught everywhere
;      else; one instruction pair, no .if expansion.
; 130. FIX 127'S BLOCK-EDGE CLAIM WAS FALSE - CURPOS RODE 1 BYTE LATE
;      WITH A PENDING UNGET. @@crhi parks the peeked byte in the unget
;      slot, but GetByte had already INC'd bIdx PAST it: curPos =
;      bBase+bIdx = P+1 while the ungot byte sits at P, so vPos line
;      starts, CachePos entries and every SeekSoft re-anchor landed 1
;      late - and SeekSoft (which clears hFull and re-reads from
;      bBuf) then SKIPPED the next line's first character. @@dones now
;      subtracts the pending unget after the curPos pair is stored
;      ("cmp hFull,0 / je / dec word ptr curPos"): DEC leaves CF
;      alone (the ADC into curPos+2 runs BEFORE the adjust, and bIdx
;      is always >= 1 when hFull is set, so the DEC cannot borrow
;      either). The invariant is now what SeekSoft's comment always
;      claimed: the unget slot holds the byte AT curPos. Verified by
;      simulation: the P/P+1 skew on the block-edge corpus is gone
;      and the line starts land exactly on the reference.
; 131. THE -3 BUILD FROZE PRE-386 MACHINES "AL ARRANCAR" - CPU GUARD.
;      Every 386-only startup path (Init's BLKFIL/BLKCP pop eax /
;      movzx ecx, CpyN's REP MOVSD, the LODSD/SWAR scanners, FastMul)
;      was re-verified instruction by instruction with a byte-faithful
;      machine simulation over the edge corpora (block-edge CR/CRLF,
;      254/255/256-char lines, 08h-0Fh storms, 200-300 KB files,
;      STDIN): the load pass is clean and NO in-code -3-only freeze
;      exists. The one reproducible startup freeze is running the -3
;      image on a lesser CPU - a real 8088/286, or an emulator
;      profile with cputype=8086/286 (the exact mismatch class of fix
;      105): the first 66h/0Fh byte (BLKFIL's pop eax, or BLKCP's
;      movzx ecx) derails instantly - 0Fh is POP CS on an 8086 - and
;      the machine hangs with the chrome half-drawn, while the 8086
;      build runs everywhere. The .startup code now probes the CPU
;      BEFORE any 386 instruction: the classic pushf/popf ladder
;      (clear flag bits 12-15: an 8086/186 keeps them stuck set; set
;      NT: a 286 clears it, a 386 keeps it) uses ONLY 8086-safe
;      instructions, so it executes on anything; a pre-386 CPU now
;      gets "This build requires a 386 or higher CPU." and exit code
;      1 instead of a frozen machine. On a real 386 the probe costs
;      ~20 cycles once and restores the caller's flags (NT cleared
;      back: a stuck NT breaks interrupt returns).
; 132. Version 1.21; the image stamp is "<4VIEW21>". SMART.INC stays
;      at v2.43 (re-verified: the shld/imul FastMul DX:AX contract and
;      the 8086 paths are correct and untouched this round).
;
; Revision 1.22 fixes:
; 133. THE 386 SWAR TAIL IS LEA+NOT (one op less per dword). Both
;      386 scanners closed the candidate test with
;      "mov edx,eax / sub eax,01010101h / not edx / and eax,edx /
;      and eax,80808080h / jcc": four ops after the cand AND. The
;      cand value only needs to survive ONCE - into the ~cand factor
;      - so the tail is now "lea edx,[eax-01010101h] / not eax /
;      and eax,edx / test eax,80808080h / jcc": LEA computes cand-1
;      into EDX while EAX KEEPS cand, the NOT flips EAX in place
;      (EDX is free after the AND), and TEST asks the branch question
;      without the dead AND clobber - same (cand-1)&~cand&mask, three
;      ops instead of four, one byte less per site. LODSD+8 ops+TEST
;      is the floor of this formula on the 386's 2-cycle ALU. Both
;      builds' 8086 paths are untouched (their LODSW halves test
;      bytes directly).
; 134. LOOP IS THE SLOW LOOP ON -3 (DEC/JNZ everywhere the 386 runs).
;      The 386 takes LOOP in 11 cycles but DEC r16 + JNZ in 2+7; the
;      486 (5 vs 2) and everything after only widen the gap (LOOP is
;      microcoded there). Every loop the -3 build executes is
;      DEC/JNZ now: the store scanner's dword tail (@@swn), the count
;      scanner's dword tail (@@fwn), WrCntRow's pair loops (@@pp
;      partial rows, @@p full rows - the hottest paint code) and the
;      @@t4b byte tail, all under if USE386 so the 8086 build keeps
;      its LOOP (17 cycles there, DEC+JNZ would be 3+16 - LOOP wins
;      on the 8086, and fix 67's unroll-8 already halved the toll).
;      Net: ~0.5 cycles/byte off both the load pass and every
;      repaint parse on 386+.
; 135. THE RE-SCAN TAILS TESTED AL TWICE (both builds). "@@dr" and
;      "@@t4b" ran "sub al,10 / cmp al,3 / ja data / cmp al,3 / je CR"
;      - but the JA branch preserves the CMP's flags, so the second
;      CMP recomputed the question the JE already answered: 2 bytes
;      and 2 cycles per re-scanned byte for nothing. Deleted; the
;      VT/FF fall-through still lands on the countdown tail.
; 136. THE 13 DUPLICATED LINE-EXIT STUBS ARE 4 CANONICALS. RdLine
;      grew one "mov dx,1 / jmp @@donef" (or dec si/inc si first)
;      stub per exit site - thirteen copies of three shapes. The
;      canonicals: @@lfx (consumed, SI already right - was @@stl,
;      @@c1e, @@l2, the CR-only tails of @@stc/@@c2/@@cr4/@@crh2 and
;      @@crlo's CRLF arm), @@decf (the partner byte opens the next
;      line - was @@c1, @@l1, @@crlo's CR arm), @@cr4e (CRLF eat -
;      was @@stce, @@c2e, @@crh2e) and @@crd2 (DX=1 to @@dones - was
;      @@slf, @@scrd). ~40 bytes less; the 8086 @@lflo keeps its
;      zero-hop DEC SI fall-through into @@lfx (fix 67's hot path),
;      and the count-mode hot exits stay direct: CRLF ends at
;      @@cr4e, LF at @@lfx. Store-mode exits pay one extra short
;      jump (~3 cycles per line, the 23-line capture gains nothing
;      measurable).
; 137. THE CPU GUARD FAIL PATH IS THE FALL-THROUGH. "jz @@oldcpu /
;      jmp @@cpusok" inverted to "jnz @@cpusok" with @@oldcpu right
;      below: 3 bytes less, the 386 pass path unchanged (one taken
;      JNZ), the pre-386 path one branch less.
; 138. Version 1.22; the image stamp is "<4VIEW22>". A 2x unroll of
;      the 386 SWAR loops was modeled and REJECTED before this
;      release: a candidate dword rescan consumes an untested dword,
;      so the pair accounting shifts parity and the round can
;      overrun its block-end bound; the whole-pair (dx=8) rescan
;      fixes slot A but the odd-dword peel then needs a different
;      continuation, a third SWAR copy and a duplicated byte-scan
;      body - ~110 bytes for ~7% on top of fixes 133+134. Not worth
;      it; the formula floor plus DEC/JNZ keeps the 386 load pass
;      where it needs to be.
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

VERMAJ      equ 2                       ; product version 2.02e
VMIN        equ 2
LINES_VIS   equ 23                      ; content rows 1..23 (title row 0,
                                        ; status row 24)
CACHE_SZ    equ 64                      ; scroll cache entries - a ring of
CACHE_MSK   equ CACHE_SZ-1              ; line starts since fix 100 (48
                                        ; were linear and shifted 180
                                        ; bytes per CachePos once full)
BUFSZ       equ 32768                   ; 32 KiB since fix 118 - free in
                                        ; the file since fix 115 (bBuf is a
                                        ; RAM offset): 12 reads per 385 KB
                                        ; (fix 42: buffered reads)
LINEWID     equ 77                      ; painted columns of a line
LBUFCAP     equ 254                     ; chars kept per line: the 256-byte
                                        ; slot is chars + NUL + the line's
                                        ; length byte at 255 (fix 66)
HPOSMAX     equ LBUFCAP-LINEWID         ; last useful horizontal window
                                        ; (177 < 256: WrCntRow compares
                                        ; hPos's low byte, fix 66)
EST_AT      equ 256                     ; lines read before ShowProg's
                                        ; running average rescales the
                                        ; bar's denominator (fix 166)
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
; FIX 154 (documentation, zero code change): BLKCP's count must be EVEN.
; The copy runs MOVSW/MOVSD and an odd CX would silently drop the tail
; byte. Every call site passes an even count (4000 for the page
; save/restore, the popup rows are (bp+2)*2, ringN*256 for the view
; buffer); CpyN is the any-count copy. Keep it in mind before reusing
; the macro anywhere else.
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
; SAVEPOS var / RESTPOS var - save the 32-bit curPos to var / restore it.
; The pattern was written out at five save and three restore sites
; (DrwUp1, DrwDn1, DrwCnt, ScrUp, CountLines); the macros emit exactly
; the instructions they replace (fix 124, the SLOTPTR/VPSTORE pattern
; of fix 74). Clobbers AX, flags dead.
;------------------------------------------------------------------------------
SAVEPOS  macro var
        mov ax,word ptr curPos
        mov word ptr var,ax
        mov ax,word ptr curPos+2
        mov word ptr var+2,ax
        endm

RESTPOS macro var
        mov ax,word ptr var
        mov word ptr curPos,ax
        mov ax,word ptr var+2
        mov word ptr curPos+2,ax
        endm

;------------------------------------------------------------------------------
; HEXROWS - compute hex row count = (fileSize + 15) / 16, capped at 65535.
; Result in AX (0..65535). On the 8086 build DX and CX (CL) are clobbered;
; on the 386+ build only EAX (AX) is clobbered. 2.02b: replaces 4 duplicated
; copies of this computation (Main End, MousePoll, DrwBar, DrwSt) with one
; source of truth. OPT: on 386+ a single native shr eax,4 replaces the
; 4-iteration shr/rcr loop (4 RCLs at ~9 cycles each on a 386 = ~36 cycles
; saved per call, 4 call sites = ~144 cycles per hex-mode frame).
;------------------------------------------------------------------------------
HEXROWS macro
        LOCAL hr_loop, hr_ok
        if USE386
        mov     eax,dword ptr fileSize       ; 386: one 32-bit load + shift
        add     eax,15                       ; no 32-bit overflow possible
        shr     eax,4                        ; for any real DOS file
        cmp     eax,0FFFFh                   ; cap at 65535 rows
        jbe     hr_ok
        mov     eax,0FFFFh
hr_ok:
        else
        mov     ax,word ptr fileSize
        mov     dx,word ptr fileSize+2
        add     ax,15
        adc     dx,0
        mov     cl,4
hr_loop: shr    dx,1
        rcr     ax,1
        dec     cl
        jnz     hr_loop
        or      dx,dx
        jz      hr_ok
        mov     ax,0FFFFh           ; >65535 rows: cap
hr_ok:
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

if USE386
        ; fix 131 - CPU GUARD: this image's first 386-only instruction
        ; (Init's BLKFIL/BLKCP pop eax / movzx ecx) derails any lesser
        ; CPU - 0Fh is POP CS on an 8086 - so a pre-386 machine froze
        ; "al arrancar" with the chrome half-painted. The probe below
        ; uses ONLY 8086-safe instructions (pushf/popf), runs on any
        ; CPU and turns the freeze into a message. ~20 cycles, once.
        pushf
        pop cx                          ; CX = the flags we came in with
        mov ax,cx
        and ax,0FFFh                    ; try to CLEAR flag bits 12-15
        push ax
        popf                            ; (IOPL+NT)
        pushf
        pop ax
        test ax,0F000h
        jnz @@oldcpu                    ; stuck set: 8086/80186
        or ax,4000h                     ; try to SET NT (bit 14)
        push ax
        popf
        pushf
        pop ax
        push cx
        popf                            ; the caller's flags back (NT off:
        test ax,4000h                   ; a stuck NT breaks interrupt returns)
        jnz @@cpusok                    ; NT stuck: a 386 (fix 137: the
@@oldcpu:                               ; fall-through IS the pre-386 path,
                                        ; the explicit JMP is gone)
        mov dx,offset s386
        mov ah,9
        int 21h
        mov ax,4C01h
        int 21h
@@cpusok:
endif

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
; KeyAvail - INLINE KEY POLL as a plain macro (fix 128: it was ASMC's
; .INLINE function feature - a PROTO with an asmcall body. The macro
; expands the same instructions at the same call sites: both builds
; stay byte-identical and the exotic PROTO form is gone. The .SWITCH
; dispatcher of fix 24 remains the one ASMC-specific construct).
; ZF=1 when the BIOS keyboard ring at 0040h is empty, ZF=0 when a key
; waits. The trailing pop ds does not touch the flags, so the result
; reaches the caller's .untilnz/.jnz directly (fixes 24/25/26).
; Clobbers AX. DS=0 since fix 151: the ring head/tail are reachable as
; 0:0041Ah/0:0041Ch - one byte and one cycle less per poll than loading
; DS=0040h (ReadKey stays on DS=0040h: it must dereference the head
; VALUE in BX against that segment).
;------------------------------------------------------------------------------
KeyAvail macro
        push ds
        xor ax,ax                       ; DS=0 (fix 151): segment 0040h
        mov ds,ax                       ; is linear 0:0040h, so head and
        mov ax,ds:[0041Ah]              ; tail are 0:041Ah / 0:041Ch -
        cmp ax,ds:[0041Ch]              ; head == tail: buffer empty
        pop ds
        endm

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
        xor bh,bh                       ; BH = 0: unquoted, ' '/9 end the
        .if (al=='"')                   ; name; BH = 1: quoted, '"' does
                inc si                  ; (fix 123: one loop for both -
                inc bh                  ; LODSB reads either, and SI is
        .endif                          ; dead after the loop anyway)
        mov cx,64
        .while (cx)
                lodsb
                .break .if (al==0Dh)
                .if (bh)
                        .break .if (al=='"')
                .else
                        .break .if (al==' ' || al==9)
                .endif
                stosb
                dec cx
        .endw
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
        ; the merged view buffer (fix 85): file mode paints slots 0..22
        ; (the mod-23 view cache), STDIN turns all 46 slots into its
        ; scrollback ring
        .if (isFile)
                mov ringN,LINES_VIS
        .else
                mov ringN,RSLOTS
        .endif
        mov di,offset vCache
        mov ah,byte ptr ringN
        xor al,al                       ; CX = ringN*256 (fix 119: file mode
        mov cx,ax                       ; clears 23 slots, not 46 - no read
        xor ax,ax                       ; exists below the ring) - AX = 0:
        BLKFIL                          ; the wide clear

        ; fix 171: accelerate keyboard typematic on AT+ (30 cps,
        ; 250 ms delay) for faster Up/Down/PgUp/PgDn scroll. The IBM
        ; AT default is ~10 cps with 500 ms: held keys scroll only 10
        ; lines/second and the first repeat takes 500 ms. INT 16h
        ; AX=0305h BL=00 sets 30 cps / 250 ms - 3x faster repeat and
        ; half the initial delay. PC/XT is detected via INT 15h
        ; AH=0C0h (system config: model byte >= 0FDh = PCjr/XT/PC)
        ; and left alone; Done restores the IBM default (BL=22h).
        mov svType,0                  ; assume no typematic change
        push es
        mov ax,0C00h                  ; INT 15h AH=0Ch: get system config
        int 15h
        jnc @@atk_chk                 ; CF=0: AT+, check model byte
        pop es                        ; PC/XT: function not supported
        jmp @@atk_done
@@atk_chk:
        mov al,byte ptr es:[bx+2]     ; 2.02f (fix 224): the MODEL byte of
        pop es                        ; the INT 15h C0h table sits at
                                      ; ES:BX+2 (offset 0 is the WORD
                                      ; length of the table, usually 8 or
                                      ; 10) - the 1.35 read the length's
                                      ; low byte, which is always below
                                      ; 0FDh, so the guard never excluded
                                      ; PCjr/XT/PC and the AT typematic
                                      ; rate was set on them too
        cmp al,0FDh                   ; >= 0FDh: PCjr/XT/PC (no AT kbd)
        jae @@atk_done
        ; AT+ detected: set typematic to maximum speed
        mov svType,1                  ; remember to restore on exit
        mov ax,0305h                  ; INT 16h AH=03h AL=05h: set rate
        xor bl,bl                     ; BL=0: 30 cps, 250 ms delay
        int 16h
@@atk_done:

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
                mov word ptr fileSize,ax
                mov word ptr fileSize+2,dx
                xor cx,cx
                xor dx,dx
                mov ax,4200h
                int 21h
                call FullPath           ; fName = fully qualified path
                call DrwHdr             ; title now shows the full path
                mov si,offset fName
                call StatLoad           ; "Loading <full path>..." (fix 30)
                call ShowProg           ; empty bar: the scan starts (86)
                call DetectBinary
                call CountLines
                .if (binFile)
                        mov hexMode,1
                .endif         ; also captures view #1 (fixes 55/85)
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
        cmp cx,64                       ; fName holds 64 chars + NUL:
        ja @@keep                       ; UNSIGNED (fix 140). FIX 152: the
                                        ; 1.25 "ja @@okl" was inverted - it
                                        ; aimed the >64-char paths AT the
                                        ; copy, so CX up to 128 overran
                                        ; fName into lBuf and DrwHdr's
                                        ; "mov cx,160 / sub cx,di" pad
                                        ; computed a NEGATIVE count whose
                                        ; shr/rep stosw swept the whole
                                        ; video segment the moment Init
                                        ; repainted the title after this
                                        ; call; the <=64 paths copied a
                                        ; fixed 64 bytes that only worked
                                        ; thanks to the embedded NUL.
                                        ; Too long: keep the name as typed
                                        ; (the documented 1.01 behavior),
                                        ; 3 bytes less
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
        .if (di > offset stBuf+46)     ; fix 170: clamp the name tighter
                mov di,offset stBuf+46 ; (46 = 8 "Loading " + 38 name) to
        .endif                        ; leave room for "L:NNNNN" at cols 50..56
        mov ax,di
        sub ax,offset stBuf            ; AX = the "..." char offset in
        push ax                         ; stBuf (fix 139: 1.22 pushed the
        mov si,offset sDots             ; ABSOLUTE di and re-added stBuf
        call Cpy                        ; on both uses - SI landed inside
        mov byte ptr [di],0             ; bBuf and the .while scanned the
        call PaintStat                  ; stale file block for ~33 KB while
        pop ax                          ; the stosw swept garbage over the
        mov si,offset stBuf            ; whole video page for the entire
        add si,ax                       ; load: the reported second-launch
        shl ax,1                       ; hang, both builds. Now the dots
        mov es,vSeg                     ; repaint is 3 iterations and the
        mov di,24*160+2                ; marker finally blinks where fix
        add di,ax                       ; 70 wanted it: column 1+the dots'
        mov ah,ATTR_STAT or 80h        ; offset of row 25, blink bit set
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
; the quotient still lands in 0..20 (curPos past a rescaled progSize
; is clamped to the SHIFTED size AFTER the shift - one unsigned
; compare, curPos stays read-only, fix 167: 1.32's pre-shift clamp
; shifted its own sub result on the keep path and the repaint swept
; the video segment). ONCE totLines
; crosses EST_AT lines, the running byte average predicts where the
; 65.535-line saturation will stop the scan and progSize SHRINKS to
; that estimate (166): the sweep then spans the work the load really
; does - the 30 MB file that crawled to 2 cells and jumped now fills
; smoothly across its ~4 MB scan. One shot per load, only ever
; shrinks (the bar may speed up, never jump back). Painted empty by
; Init when the
; load starts and by every FillBuf while the pre-scan runs - one
; repaint per 32 KiB block (118: 12 repaints on a 385 KB file), ~80
; cycles each on an 8086; CountLines
; paints the LAST one itself (curPos forced to the size: exactly 20
; cells, fix 163) and then clears progSize, so later refills (GoLine,
; cold Downs at a block edge) paint nothing. Every paint leaves its
; filled-cell count in barCells (164: the completion hold's input).
; Everything is in the uses
; list or saved explicitly: the FillBuf callers hold SI/DI live.
;------------------------------------------------------------------------------
ShowProg proc uses ax bx cx dx si di
        mov ax,word ptr progSize
        or ax,word ptr progSize+2      ; zero: no bar to paint
        jz @@done
        ; the denominator rescale (166): predict the scan's end from
        ; the running average and shrink progSize to it - the byte bar
        ; cannot show a saturating scan honestly otherwise (10+165)
        cmp estDone,0
        jne @@estd
        cmp totLines,EST_AT
        jb @@estd
        mov estDone,1                  ; one shot: even a no-shrink
                                        ; estimate is never re-run
        mov cx,totLines                ; the REAL count at this refill
        mov ax,word ptr curPos
        mov dx,word ptr curPos+2
        cmp dx,cx                      ; DX >= CX: the DIV would #DE
        jae @@avok                     ; (avg >= 64 KB per line: est -
        div cx                         ; 167: 1.32's jb was inverted and
        jmp @@estmul                   ; divided the #DE case itself)
@@avok: mov ax,0FFFFh                   ; avg saturated: the size test
@@estmul:                               ; below keeps the bar as is
        mov cx,0FFFFh                  ; the scan stops at line 65.535
        mul cx                         ; DX:AX = est (max FFFE0001h)
        cmp dx,word ptr progSize+2     ; only ever SHRINKS progSize
        ja @@estd                      ; (the bar may speed up, never
        jb @@estset                    ; jump back)
        cmp ax,word ptr progSize
        jae @@estd
@@estset:
        mov word ptr progSize,ax
        mov word ptr progSize+2,dx
@@estd: push es
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
        cmp ax,bx                      ; the rescale can leave curPos
        jbe @@nok                      ; PAST progSize (the scan outgrew
        mov ax,bx                      ; the estimate): clamp the SHIFTED
@@nok:                                  ; copy to the shifted size (167) -
                                        ; min(a,b)>>s = min(a>>s,b>>s), so
                                        ; the quotient is untouched for
                                        ; pos <= size and exactly 20 past
                                        ; it. 1.32 clamped BEFORE the shift
                                        ; with a sub/sbb whose keep path
                                        ; shifted the wrapped DIFFERENCE,
                                        ; not curPos: the quotient left
                                        ; 0..20 and the rail's rep stosw
                                        ; swept the video segment
        mov si,20
        mul si                         ; DX:AX = pos16*20
        div bx                         ; AX = filled cells, 0..20
        mov barCells,al                ; the hold's decision input (164)
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
        ; fix 170: running line count at columns 50..56 - "L:" plus a
        ; right-aligned 5-digit decimal of totLines, painted per 32 KiB
        ; block so the user sees progress during long loads. The bar
        ; alone (20 cells for the whole file) is too coarse on big
        ; files: 12 repaints for 385 KB, and a 30 MB file that saturates
        ; at line 65.535 leaves the bar stuck at 2 cells - the growing
        ; line count is the only visible sign of life. ~30 bytes + ~200
        ; cycles per block, both builds
        mov di,24*160+2+50*2           ; column 50
        mov ax,A_STAT or 'L'
        stosw                          ; 'L' at col 50
        mov al,':'
        stosw                          ; ':' at col 51
        mov cx,5                       ; clear the 5-cell field
        mov ax,A_STAT or ' '          ; (cols 52..56) to spaces
        rep stosw
        push es                        ; save vSeg for U2A
        push ds
        pop es                         ; ES=DS: U2A writes via STOSB
        mov di,offset stBuf+80         ; 16-byte scratch (stBuf is 96:
                                        ; StatLoad uses 0..49, DrwSt 0..64)
        mov ax,totLines
        call U2A                       ; DI = stBuf+80 + digit_count
        mov cx,di                      ; CX = end of digit string
        sub cx,offset stBuf+80         ; CX = digit count (1..5)
        pop es                         ; ES=vSeg again
        mov di,24*160+2+52*2           ; column 52 (field start)
        mov bx,5
        sub bx,cx                      ; BX = leading space count
        mov ax,A_STAT or ' '
        test bx,bx
        jz @@lnd                       ; no leading spaces needed
@@lnp:  stosw                          ; paint a leading space
        dec bx
        jnz @@lnp
@@lnd:  mov si,offset stBuf+80         ; SI = first digit
@@lnc:  lodsb                          ; AL = digit char, SI++
        mov ah,ATTR_STAT
        stosw                          ; paint at ES:DI, DI += 2
        loop @@lnc                     ; CX digits
        pop es
@@done: ret
ShowProg endp

;------------------------------------------------------------------------------
; SeekSoft - re-anchor the buffered reader at curPos WITHOUT touching DOS
; when curPos still lies inside the buffered 32 KiB block (118): only bIdx is
; rewound and the block is reused (fix 48). This is the hot path of
; Up/PgUp/repaints: 1.05 called the real Seek per line, which zeroed bLen
; and forced RdLine to refill 16 KiB - one PgUp inside a block made 23
; DOS seeks plus up to 23*16 KiB = 368 KiB of useless re-reading. The
; unget slot is cleared: its byte always sits at curPos and is re-read
; from the buffer, so the bIdx/cursor invariant stays exact. Three cases:
;   - inside the block: bIdx = curPos-bBase, no DOS call at all;
;   - exactly at the block end: empty the block (bLen=0/bIdx=0), the
;     DOS pointer already is there, the next read refills forward;
;   - outside: the real seek (INT 21h AH=42h) - the old Seek proc, folded
;     here in fix 117 (its only caller left was the jmp below; it repeated
;     the hFull=0 SeekSoft's entry had already done, and its CX clobber
;     was what forced Main's PgUp to push/pop around every ScrUp). CX
;     survives the DOS call now, so NO caller of this proc clobbers CX.
; Clobbers AX DX. Flags dead.
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
@@hard:                                 ; the real seek (fix 48's fallback)
        push cx                         ; CX survives (fix 117: PgUp needs
        mov bx,hFile                    ; it across ScrUp)
        mov ax,4200h
        mov cx,word ptr curPos+2
        mov dx,word ptr curPos
        int 21h
        pop cx
        mov ax,word ptr curPos
        mov word ptr bBase,ax
        mov ax,word ptr curPos+2
        mov word ptr bBase+2,ax
        mov bLen,0
        mov bIdx,0
        ret
SeekSoft endp

;------------------------------------------------------------------------------
; CountLines - pre-scan the whole file (buffered: fast). The speed of
; this pass is RdLine's: inline fetch, no per-byte curPos adds, no
; per-line unget round trip (fixes 14/37). Since fix 156 the first
; paint happens HERE: view #1 hits the screen the moment its 23 lines
; are captured, and the rest of the scan keeps running under the bar.
; Since 1.06 RdLine runs here in count mode (no text stores); since
; 1.07 (fix 54) the consume-only loop eats two bytes per iteration
; (~29 cycles/byte).
; NEW (fixes 55/85): the first LINES_VIS lines run in STORE mode parsed
; STRAIGHT into their vCache slots (no RingAppend copy pass any more:
; the proc is gone) and vPos records starts 0..22 plus entry 23 (the
; line below the view: the first Down's hot read) - so the initial
; Draw, Home AND the first Down all cost zero extra parses. The
; trailing line without EOL still counts exactly: at EOF the scan
; compares curPos with the saved line start (tmpPos), which the
; no-store mode would leave in an empty lBuf. The progress bar (fix
; 86) ends here: curPos is forced to the file size and ShowProg runs
; ONE last time - the sweep closes at exactly 20/20 cells whether the
; scan reached the EOF or saturated at line 65.535 mid-file (fix 163:
; the last refill's paint ran with the previous line's curPos, so the
; 100% state was never painted) - and THEN progSize is cleared so
; later FillBuf refills (GoLine, cold Downs at a block edge) paint
; nothing. When the LAST refill's bar (snapped into BL before the
; final paint, fix 165 - barCells reads 20 after it) sat below 15
; cells - the saturating case ends at 2 cells on a 30 MB file - the
; full bar is HELD for ~8 BIOS ticks (~440 ms, fixes 164/165): the
; jump to 20/20 is the perceptible "load done" beat before DrwSt
; wipes the row. Sweeps that already reached 15+ cells (any file
; over ~128 KB) needed no beat and keep the fast exit.
;------------------------------------------------------------------------------
CountLines proc
        mov totLines,0
        mov word ptr curPos,0
        mov word ptr curPos+2,0
        call SeekSoft
        .while (1)
                SAVEPOS tmpPos           ; tmpPos = start of this line
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
                        cmp totLines,LINES_VIS-1
                        jne @@aft               ; (fix 146: the next capture
                                                ; re-arms wDest - the reset
                                                ; only matters at line 22)
                        ; line 22, the last one of the view, was just read:
                        ; curPos IS the start of line 23 = the line below
                        ; the view, the first Down's hot read (fix 110: 1.17
                        ; stored it after reading line 23 = line 24's start)
                        mov wDest,offset lBuf   ; count mode's @@dones writes
                                                ; the NUL/length to wDest (146)
                        mov cntMode,1           ; count-only from here
                        mov si,LINES_VIS*4      ; vPos entry 23
                        VPSTORE si
                        call RingPaint          ; fix 156: view #1 on screen
                                                ; NOW - rows 1..23 from the
                                                ; slots; NOT Draw/DrwCnt (the
                                                ; curPos invariant is mid-scan
                                                ; here) and NOT DrwBar/DrwSt
                                                ; (totLines is still partial:
                                                ; they would fight the loading
                                                ; text and the bar). The pre-
                                                ; scan continues below
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
        mov bl,barCells                 ; the LAST refill's count (165):
                                        ; snap it BEFORE the final paint,
                                        ; which overwrites barCells with
                                        ; exactly 20 - the 1.30 hold read
                                        ; it after and never fired
        mov ax,word ptr progSize        ; the bar closes at 100% (163):
        mov word ptr curPos,ax          ; curPos = size - the last paint
        mov ax,word ptr progSize+2      ; inside FillBuf ran with the
        mov word ptr curPos+2,ax        ; previous line's curPos, and a
        call ShowProg                   ; saturated scan left it mid-file
        cmp bl,15                       ; the completion must be SEEN
        jae @@nob                       ; (164/165): a sweep that stop-
        push ds                         ; ped below 15 cells - the satu-
        xor ax,ax                       ; rating 30 MB file freezes at 2
        mov ds,ax                       ; - holds the full bar for 8 tick
        mov si,8                        ; edges (~440 ms) before DrwSt
@@tick: mov ax,ds:[046Ch]              ; wipes it. A sweep that reached
@@edge: cmp ax,ds:[046Ch]              ; 15+ cells (any file over ~128
        je @@edge                       ; KB) showed a near-full bar for
        dec si                          ; its whole last block: no beat,
        jnz @@tick                      ; the fast exit stays
        pop ds
@@nob:  mov cntMode,0
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
        if USE386
        mov ax,ringN                    ; the wrap limit (ringN*SLOTSZ +
        shl ax,8                        ; vCache) is loop-invariant: hoisted
        else                            ; here once (fix 95 - the per-row
        mov ah,byte ptr ringN           ; version paid a shl ax,8 chain x 23
        xor al,al                       ; rows); fix 157: the AH trick does
        endif                           ; it in 2 instructions on an 8086
        add ax,offset vCache            ; (ringN < 256); -3 keeps the native
        mov dx,ax                       ; immediate shift. DX is free:
        mov di,160+2                    ; WrCntRow never touches it
        mov cx,LINES_VIS
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
                KeyAvail              ; ZF=1: ring empty
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
                        call ScrUp      ; CX survives ScrUp too (fix 117:
                        or moved,al     ; Seek preserves it)
                .endf
        .case 51h                       ; PgDn
                .for (cx=LINES_VIS: cx: cx--)
                        call ScrDn      ; CX survives (RdLine's uses list,
                        or moved,al     ; SeekSoft 117; fix 101)
                .endf
        .case 47h                       ; Home
                xor al,al
                .if (isFile)
                        mov curLine,0
                        mov hPos,0
                        mov word ptr curPos,0
                        mov word ptr curPos+2,0
                        mov cCnt,0
                        mov vcValid,0
                        call SeekSoft
                        mov al,1
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
                .if (hexMode)           ; fix 177: the last hex ROW, not the
                        HEXROWS          ; AX = hex rows (2.02b: was inline)
                        sub ax,LINES_VIS
                        jae @@hset
                        xor ax,ax        ; dump fits the screen
@@hset:                   cmp ax,curLine
                        je @@hno
                        mov curLine,ax
                        mov al,1
@@hno:
                .elseif (isFile)
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
                                KeyAvail
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
                .if (hPos && !wrapOn)     ; 2.02: no h-scroll in wrap mode
                        dec hPos
                        mov al,1
                .endif
        .case 4Dh                       ; Right: one column right (47)
                xor al,al
                .if (!wrapOn)
                        mov ax,hPos
                        .if (ax < HPOSMAX)
                                inc hPos
                                mov al,1
                        .endif
                .endif
        .case 73h                       ; Ctrl+Left: ten columns (47)
                xor al,al
                .if (!wrapOn)
                        .if (hPos > 10)
                                sub hPos,10
                                mov al,1
                        .elseif (hPos)
                                mov hPos,0
                                mov al,1
                        .endif
                .endif
        .case 74h                       ; Ctrl+Right: ten columns (47)
                xor al,al
                .if (!wrapOn)
                        mov ax,hPos
                        .if (ax < HPOSMAX-10)
                                add hPos,10
                                mov al,1
                        .elseif (ax < HPOSMAX)
                                mov hPos,HPOSMAX
                                mov al,1
                        .endif
                .endif
        .case 19h
                .if (al==10h)
                        call PrintFile
                        xor al,al
                .endif
        .case 1Eh
                .if (al==41h || al==61h)
                        .if (srValid)
                                mov srBack,0
                                call DoSearch
                        .endif
                .endif
        .case 21h
                .if (al==46h || al==66h)
                        mov si,offset sAskFind
                        mov di,offset srPat
                        mov cx,31
                        call PopAsk
                        .if (cx)
                                mov srLen,cx
                                mov srBack,0
                                mov srCase,0
                                mov srValid,1
                                call DoSearch
                        .endif
                .endif
        .case 1Fh
                .if (al==53h || al==73h)
                        mov si,offset sAskScan
                        mov di,offset srPat
                        mov cx,31
                        call PopAsk
                        .if (cx)
                                mov srLen,cx
                                mov srBack,0
                                mov srCase,1
                                mov srValid,1
                                call DoSearch
                        .endif
                .endif
        .case 2Bh
                mov si,offset sAskFind
                mov di,offset srPat
                mov cx,31
                call PopAsk
                .if (cx)
                        mov srLen,cx
                        mov srBack,0
                        mov srCase,0
                        mov srValid,1
                        call DoSearch
                .endif
        .case 35h
                mov si,offset sAskScan
                mov di,offset srPat
                mov cx,31
                call PopAsk
                .if (cx)
                        mov srLen,cx
                        mov srBack,0
                        mov srCase,1
                        mov srValid,1
                        call DoSearch
                .endif
        .case 29h
                mov si,offset sAskFindB
                mov di,offset srPat
                mov cx,31
                call PopAsk
                .if (cx)
                        mov srLen,cx
                        mov srBack,1
                        mov srCase,0
                        mov srValid,1
                        call DoSearch
                .endif
        .case 28h
                mov si,offset sAskScanB
                mov di,offset srPat
                mov cx,31
                call PopAsk
                .if (cx)
                        mov srLen,cx
                        mov srBack,1
                        mov srCase,1
                        mov srValid,1
                        call DoSearch
                .endif
        .case 07h
                .if (al==5Eh)
                        mov si,offset sAskFindB
                        mov di,offset srPat
                        mov cx,31
                        call PopAsk
                        .if (cx)
                                mov srLen,cx
                                mov srBack,1
                                mov srCase,0
                                mov srValid,1
                                call DoSearch
                        .endif
                .endif
        .case 2Fh                       ; V/v: back-scan (was V=stats, removed)
                .if (al==56h || al==76h)
                        mov si,offset sAskScanB
                        mov di,offset srPat
                        mov cx,31
                        call PopAsk
                        .if (cx)
                                mov srLen,cx
                                mov srBack,1
                                mov srCase,1
                                mov srValid,1
                                call DoSearch
                        .endif
                .endif
        .case 17h
                .if (al==49h || al==69h)
                        call ShowInfo
                        xor al,al
                .endif
        .case 22h                       ; fix 181: G goes to a line - 2.00's
                .if (al==47h || al==67h)  ; help promised "Ctrl+Home goto
                        mov si,offset sAskGoto ; line N" with no handler
                        mov di,offset srPat ; behind it; the parser and the
                        mov cx,5              ; prompt existed unused
                        call PopAsk
                        .if (cx)
                                mov si,offset srPat
                                call AtoU
                                .if (!carry?)
                                        or ax,ax            ; typed 0 -> stay
                                        jz @@gd             ; on line 1 (a 16-bit
                                        dec ax              ; wrap of a huge
@@gd:                                   mov dx,totLines     ; input must NOT
                                                            ; floor: the clamp
                                                            ; below catches it)
                                        sub dx,LINES_VIS
                                        jae @@gc
                                        xor dx,dx          ; short file: top
@@gc:                                   cmp ax,dx
                                        jbe @@gk
                                        mov ax,dx          ; clamp to the
@@gk:                                   cmp ax,curLine     ; last top line
                                        jne @@go
                                        xor al,al          ; already there
                                        jmp @@gn
@@go:                                   mov curLine,ax
                                        mov vcValid,0
                                        call GoLine
                                        mov al,1
@@gn:
                                .else
                                        xor al,al
                                .endif
                        .else
                                xor al,al
                        .endif
                .endif
        .case 15h
                .if (al==19h)
                        call SetBm
                        xor al,al
                .elseif (al==0)
                        call GotoBm
                        mov al,1
                .endif
        .case 23h
                .if (al==0 && isFile)   ; hex view needs a seekable file
                        xor hexMode,1
                        mov vcValid,0
                        mov curLine,0
                        mov hPos,0
                        mov word ptr curPos,0
                        mov word ptr curPos+2,0
                        mov cCnt,0
                        mov al,1
                .endif
        .case 3Dh
                .if (srValid)
                        mov srBack,0
                        call DoSearch
                .endif
        .case 43h
                .if (srValid)
                        mov srBack,1
                        call DoSearch
                .endif
        .case 11h                       ; 2.02: 'W' toggles word wrap
                .if (al==57h || al==77h)
                        xor wrapOn,1
                        mov vcValid,0
                        mov curLine,0
                        mov hPos,0
                        mov cCnt,0
                        mov word ptr curPos,0
                        mov word ptr curPos+2,0
                        mov word ptr progSize,0
                        mov word ptr progSize+2,0
                        mov barCells,20          ; skip the completion hold
                        call SeekSoft
                        .if (isFile)
                                call CountLines   ; recount with new wrap
                        .endif
                        mov al,1
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
                mov bx,dx               ; BX = clicked row (saved)
                .if (hexMode)           ; fix 177: the thumb maps hex ROWS;
                                        ; no text walk - HexDraw seeks per
                                        ; row, so the jump is free
                        HEXROWS         ; AX = hex rows (2.02b: was inline)
                        cmp ax,LINES_VIS
                        jbe @@done       ; dump fits: no travel
                        sub ax,LINES_VIS
                        xchg ax,bx       ; AX = clicked row, BX = travel
                        mul bx           ; DX:AX = row*travel
                        mov bx,LINES_VIS-1
                        div bx           ; AX = target top row
                        mov curLine,ax
                        call Draw
                        jmp @@wr
                .endif
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
                                        ; (fix 147: the totLines clamp was
                                        ; dead - row <= 22 puts the line at
                                        ; tot-23 at most, always < totLines,
                                        ; so the stronger invariant that
                                        ; DrwBar/DrwSt rely on is kept)
                mov curLine,ax
                call GoLine
                call Draw
@@wr:           KeyAvail              ; ESC/keys abort the wait if the
                jnz @@wrdone            ; button sticks (BIOS ring, 25)
                int 28h                 ; DOS idle (26)
                mov ax,3
                int 33h
                test bl,1
                jnz @@wr                ; 2.02 fix: loop WHILE pressed (was jz -
                                        ; the inversion made the click auto-repeat
                                        ; and could hang if released mid-Draw)
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
        .if (hexMode)                  ; fix 177: hex rows, not text lines -
                .if (curLine)        ; 2.00 ran the TEXT cache logic on a
                        dec curLine        ; row index (and DrwUp1 then moved
                        mov al,1            ; it a SECOND time via HexUp1)
                .endif
                ret
        .endif
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
        SAVEPOS tmpPos
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
        .if (hexMode)                  ; fix 177: EOF is fileSize, not
                mov ax,curLine        ; totLines - 2.00 blocked a binary's
                add ax,LINES_VIS       ; hex view at its TEXT line count.
                jc @@s                  ; 2.02 fix: curLine near 65535 wraps the
                                        ; add - guard against it (was missing:
                                        ; the text branch has jc @@s, hex didn't)
                ; 2.02f (fix 228) OPT: x16 by shifts on the 8086 - MUL
                ; r16 costs ~118 cycles there, eight 1-bit shifts ~19;
                ; the 386 keeps MUL (about the same cost as the chain).
                ; BX and CX stay untouched either way: fix 191's
                ; contract (Main's PgDn counts the loop in CX) holds.
                if USE386
                mov bx,16              ; fix 191: the x16 goes through BX:
                mul bx                 ; Main's PgDn counts the loop in CX
                else                   ; and 2.00's "mov cx,16" reset it
                xor dx,dx
                shl ax,1               ; x2
                rcl dx,1
                shl ax,1               ; x4
                rcl dx,1
                shl ax,1               ; x8
                rcl dx,1
                shl ax,1               ; x16
                rcl dx,1
                endif
                cmp dx,word ptr fileSize+2   ; to 16 on every call - the
                ja @@s                  ; loop never counted down: PgDn in
                jb @@hdn                ; hex mode hung in an endless ScrDn
                cmp ax,word ptr fileSize
                jae @@s
@@hdn:          inc curLine
                mov al,1
                ret
        .endif
        .if (isFile)
                mov ax,curLine
                add ax,LINES_VIS
                jc @@s                  ; wrapped: definitely at the end
                cmp ax,totLines         ; unsigned: bottom reached (fix 23)
                jae @@s
                call CachePos
                mov cntMode,1           ; 2.02d: consume-only RdLine - ScrDn only
                call RdLine             ; needs the next line start (EOF check +
                mov cntMode,0           ; reader advance), not the text. The
                                        ; store scanner was ~44 cyc/byte, consume
                                        ; is ~22 - 2x faster, matching Up's speed
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
        .if (hexMode)
                call HexDraw            ; fix 177: movement already happened
                call DrwBar             ; in ScrUp - paint only
                call DrwSt
                ret
        .endif
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
                SAVEPOS savPos
                mov bx,curLine
                and bx,31
                shl bx,2                       ; BX = (curLine and 31)*4: vPos
                VPSTORE bx                     ; entry (fix 64: no [DX] on 8086)
                mov ax,vcTop                   ; fix 183: the compare goes
                .if (vcValid != 0 && ax==curLine+1) ; through a register -
                        ; hot (fix 64): the new top line takes the slot the old
                        ; bottom line (vcTop+22, slots are line mod 23) just left
                        dec vSlot                       ; slot -1, 22 <- 0FFh
                        jns @@vs                        ; (fix 122: dec/jns =
                        mov vSlot,LINES_VIS-1           ; 2 instructions less)
@@vs:
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
                RESTPOS savPos
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
        .if (hexMode)
                call HexDraw            ; fix 177: movement already happened
                call DrwBar             ; in ScrDn - paint only
                call DrwSt
                ret
        .endif
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
                SAVEPOS savPos
                mov ax,vcTop                   ; fix 183: register compare
                .if (vcValid != 0 && ax==curLine-1)
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
                        cmp bx,offset vCache+LINES_VIS*SLOTSZ
                        jb @@flc                 ; fix 153: UNSIGNED by
                        mov bx,offset vCache     ; opcode - the .if only
@@flc:                                          ; compared unsigned because
                                                ; 0CA07h does not fit SWORD
                                                ; (fix 149): same bytes, any
                                                ; image layout
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
                RESTPOS savPos
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
;                     77th char, one LODSW and six instructions per
;                     pair (fix 143; fix 99 had killed the lodsb/or/jz
;                     per byte, fix 143 kills the per-byte tests too);
;   1..LINEWID      : avail chars two per iteration (the odd one first,
;                     fix 120), then the pad cells in one REP STOSW
;                     (the pad count waits on the stack while LODSB
;                     runs);
;   len <= hPos     : the whole row is one REP STOSW.
; Clobbers AX CX SI DI only - DrwCnt holds its vPos cursor in DX,
; RingPaint its wrap limit there and both keep BX/BP live (fix 143
; parks BX around the paint section: the 1.14 contract stays, 99).
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
        push bx                         ; fix 191: save the caller's slot
        mov bh,ATTR_CONT                ; cursor BEFORE loading BH - fix
        jc @@full                       ; 143 placed the push one line too
                                        ; late, so every call returned with
                                        ; BX = 1Fxx: the slot cursor stuck,
                                        ; cold fills parsed rows over the
                                        ; program's own state block (the
                                        ; 1.14-1.35 builds shipped it)
        add si,hPos
        mov ch,0
        push cx                         ; the pad count waits on the stack
        mov cl,al                       ; while the pairs paint
        shr cx,1                        ; pairs, CF = odd char (fix 120:
        jnc @@pe                        ; two per iteration - the 77-char
        lodsb                           ; odd char goes first
        stosw
@@pe:   jcxz @@pd                       ; a 1-char line: no pairs
@@pp:   mov ax,[si]                     ; fix 161: 14 vs LODSW 16 on an
        add si,2                        ; 8086 (6 vs ~12 on -3): c1 -> AL,
        mov bl,ah                       ; c2 -> AH, it waits in BL
        mov ah,bh                       ; the attribute joins c1
        if USE386
        mov es:[di],ax                  ; fix 160: 5+2 vs STOSW ~11/cell
        add di,2
        mov al,bl
        mov es:[di],ax
        add di,2                        ; cell 2 (AH still ATTR_CONT)
        dec cx                          ; fix 134: DEC/JNZ on -3 - LOOP is
        jnz @@pp                        ; 11 cycles taken on a 386, the
        else                            ; pair is 9 (and worse on 486+)
        stosw                           ; cell 1
        mov al,bl
        stosw                           ; cell 2 (AH still ATTR_CONT)
        loop @@pp
        endif
@@pd:   pop cx                          ; pad the rest (CX=0: no-op)
        mov al,' '                      ; AH already carries ATTR_CONT
        rep stosw
        pop bx
        ret
@@full: add si,hPos                     ; window start: one ADD, no walk
        mov cx,38                       ; 38 pairs + the 77th char: no
@@p:    mov ax,[si]                     ; fix 161: 14 vs LODSW 16 on an
        add si,2                        ; 8086 (6 vs ~12 on -3). NUL probes
        mov bl,ah                       ; - the length byte already proved
        mov ah,bh                       ; these 77 chars are data (fix 99)
        if USE386
        mov es:[di],ax                  ; fix 160: 5+2 vs STOSW ~11/cell
        add di,2
        mov al,bl
        mov es:[di],ax
        add di,2
        dec cx                          ; fix 134: DEC/JNZ on -3 (LOOP is
        jnz @@p                         ; 11 cycles taken on a 386)
        else
        stosw
        mov al,bl
        stosw
        loop @@p
        endif
        lodsb                           ; the 77th char
        stosw
        pop bx
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
; FIX 162: a refill that runs while the load pass is live (progSize
; set, fix 86) peeks the BIOS keyboard ring first; a PENDING ESC
; returns 0 bytes - the scan unwinds through the normal EOF exits
; and the queued ESC quits via Main. The key is never consumed,
; non-ESC keys change nothing, and refills outside the load pass
; (progSize cleared by CountLines) never peek.
FillBuf proc uses bx cx dx
        mov bx,hFile
        mov ah,3Fh
        mov dx,offset bBuf
        mov cx,BUFSZ
        int 21h
        jnc @@esc                       ; CF=1: AX is an error code, not
        xor ax,ax                       ; a byte count: treat it as EOF (112)
        jmp @@ok
@@esc:  or ax,ax
        jz @@ok                         ; real EOF: nothing to peek at
        mov cx,ax                       ; CX parks the read count (CX is
        mov ax,word ptr progSize        ; dead here). fix 162: peek ONLY
        or ax,word ptr progSize+2       ; during the load pass (86: progSize
        jz @@rst                        ; is live exactly for the pre-scan)
        push ds
        xor ax,ax
        mov ds,ax                       ; DS=0: the BIOS ring at 0:041Ah
        mov bx,ds:[0041Ah]              ; head (fix 151's addressing)
        cmp bx,ds:[0041Ch]              ; head == tail: the ring is empty
        je @@pk1
        mov ax,ds:[bx+0400h]            ; fix 168: the queued keystroke word
        cmp ax,011Bh                    ; key lives at 0040:[head]); ESC =
        jne @@pk1                       ; AL=1Bh AH=01h = 011Bh
        xor cx,cx                       ; ESC waits: THIS refill reads 0 -
                                        ; RdLine unwinds through its normal
                                        ; EOF exit and the untouched ESC
                                        ; quits via Main right after the
                                        ; first Draw (.case 01h -> Done)
@@pk1:  pop ds
@@rst:  mov ax,cx                       ; the read count (or the fake 0)
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
; FIX 75: STDIN runs through the same 32 KiB engine as files (118) - hFile is
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
        cmp bx,bLen                     ; fix 129: UNSIGNED. Since fix 118
        jb @@gb                         ; BUFSZ is 8000h: a FULL block's
        mov ax,bLen                     ; bLen reads -32768 in ASMC's SIGNED
        add word ptr bBase,ax           ; .if, so every mid-block peek of
        adc word ptr bBase+2,0          ; the unget path "refilled" 32 KiB
        call FillBuf                    ; early and skipped the block - one
        .if (!bLen)                     ; GetByte per byte, up to 32 KiB of
                stc                     ; file gone each (a CR in the last
                ret                     ; byte of a full block loaded as
        .endif                          ; garbage). jb/jae is what fix 93
        xor bx,bx                       ; taught everywhere else.
@@gb:   mov al,byte ptr bBuf[bx]
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
; per 32 KiB (FillBuf) plus this scan; BUFSZ is 32 KiB since fix 118 -
; free in the file since fix 115 moved bBuf to RAM (12 reads per
; 385 KB; the 16 KiB of COM growth fix 41 worried about is gone).
;------------------------------------------------------------------------------
RdLine proc uses bx cx dx si di bp
        push es
        push ds
        pop es                          ; ES = DS: the store loop uses
        mov di,wDest                    ; STOSB (fixes 60/63); the caller's
        mov cx,LBUFCAP                  ; ES is restored at the single exit
        .if (wrapOn)                    ; 2.02f (fix 226): wrap caps the
                mov cx,LINEWID          ; SLOW path too - with a pending
        .endif                          ; unget byte it used to store up
                                        ; to LBUFCAP chars into ONE visual
                                        ; row and silently ate the rest of
                                        ; the logical line
                                        ; wDest = lBuf unless DrwCnt aims
                                        ; a view-cache slot at it (fix 63).
                                        ; NO entry NUL (fix 158): the single
                                        ; exit's @@dones always writes it
                                        ; before @@ret0
        xor dx,dx                       ; exit reason: 0 = EOF, 1 = EOL
        cmp hFull,0
        jne @@slowin                    ; a byte waits in the unget slot

        ; --- fast path: straight from bBuf (fix 41) ---
        xor bp,bp                       ; 0: storing, 1: consume-only
        .if (cntMode && !wrapOn)        ; 2.02: wrap uses the store scanner
                mov bp,1                ; even in count mode (capacity = LINEWID)
        .endif
        mov si,offset bBuf
        add si,bIdx
@@fx:   mov bx,bLen                     ; the fresh-block recompute of the
        add bx,offset bBuf              ; refill lives here too (fix 121:
        mov ax,bx                       ; FillBuf left bIdx=0, so @@rfin
        sub ax,si                       ; reloads SI and jumps here)
        or bp,bp                        ; AX = bytes left: @@full's entry
        jnz @@full                      ; contract (fix 84: 1.11 jumped
                                        ; there with the CALLER'S AX -
                                        ; CountLines got away with the
                                        ; curPos high word, but GoLine
                                        ; passes curPos low: at a
                                        ; block-straddling line the scan
                                        ; marched past BX through the whole
                                        ; segment, up to a 64 KiB runaway
                                        ; on the 386 - the scroll-down
                                        ; hang; the 8086 walked wrong
                                        ; since fix 76 too)

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
        .if (wrapOn)                   ; 2.02: wrap caps at LINEWID
                add cx,LINEWID
        .else
                add cx,LBUFCAP          ; target end: lBuf or a vCache
        .endif
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
@@sw:   mov eax,[si]                    ; fix 160: MOV+ADD instead of LODSD
        add si,4                        ; (~12 vs 4+2 on a 386). fix 142:
        mov ebp,eax                     ; the dword stays in EBP - BP's
        mov edx,eax                     ; flag is read only at the @@fx
        xor eax,0A0A0A0Ah               ; entry - this is the parse that
        xor edx,0D0D0D0Dh               ; PgDn/PgUp and the no-cache
        and eax,edx                     ; repaints pay 23 times per page.
        lea edx,[eax-01010101h]         ; fix 133: EDX = cand-1 while EAX
        not eax                         ; KEEPS cand - the NOT eats the copy
        and eax,edx                     ; move, so (cand-1)&~cand costs 3
        test eax,80808080h             ; ops, not 4 (TEST doubles as the
        jnz @@swh                       ; mask: EAX is dead past the branch
        mov [di],ebp                    ; before @@dones). fix 160: the dword
        add di,4                        ; stores STRAIGHT from EBP - one
                                        ; STOSD was ~11 plus the fix 142 EAX
                                        ; feed, the MOV form writes the same
                                        ; 4 bytes in 4+2 (ES=DS: the same
                                        ; memory). The 0-3 residue bytes
                                        ; re-round through
@@swn:  dec cx                          ; @@sloop, which enters @@swr:
        jnz @@sw                        ; fix 134: DEC/JNZ, not LOOP - LOOP
        xor bp,bp                       ; fix 155: the store flag back to 0
        jmp @@sloop                     ; once per round - fix 142 parks the
                                        ; dword in EBP and a refill re-enters
                                        ; @@fx (121), whose "or bp,bp" must
                                        ; not test the dword or the rest of
                                        ; the line switches to consume mode
                                        ; and truncates at the block edge.
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
@@sr:   mov al,[si]                     ; fix 160: 4+2 vs LODSB ~12
        inc si
        cmp al,13
        je @@stc                        ; CR: shared peek exit
        cmp al,10
        je @@lfx                        ; LF: shared exit (canonical, 136)
        mov [di],al                     ; fix 160: 4+2 vs STOSB ~11 (ES=DS)
        inc di
        dec dx
        jnz @@sr
        jmp @@swn                       ; dword done: count it with CX
@@swr:
        endif
        shr ax,1                        ; AX = words of this round
        mov cx,ax
        jcxz @@st                       ; one odd byte: tail check
@@sp:   mov ax,[si]                     ; fix 161: 10+4 = 14 on an 8086 vs
        add si,2                        ; LODSW 16 (6 vs ~12 on -3);
                                        ; P1 = AL, P2 = AH
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
        je @@lfx                        ; LF: consumed (fix 136: the four
        stosb                           ; identical exit stubs became one
        jmp @@sloop                     ; canonical @@lfx)
@@stc:  cmp si,bx                       ; CR: peek the next byte
        jae @@crhi                      ; block edge / EOF: GetByte
        cmp byte ptr [si],10
        je @@cr4e                       ; CRLF: eat it (canonical)
        jmp @@lfx                       ; CR only (canonical)
@@c1:   cmp ah,10                       ; P1 CR: P2 is ALREADY IN AH (fix
        je @@lfx                        ; 141: the [si-1] reload cost ~13
        jmp @@decf                      ; cycles per CRLF line for nothing)
@@l1:   jmp @@decf                      ; P1 LF: P2 opens the next line
@@c2:   cmp si,bx                       ; P2 CR: peek the next byte
        jae @@crhi                      ; block edge / EOF: GetByte
        cmp byte ptr [si],10
        je @@cr4e                       ; CRLF: eat it (canonical)
        jmp @@lfx                       ; CR only: SI already right
@@l2:   jmp @@lfx                       ; P2 LF: consumed
@@sful: .if (wrapOn)                   ; 2.02: wrap stops at LINEWID - the
                mov dx,1              ; rest of the logical line becomes the
                jmp @@donef           ; next visual row (no consume pass)
        .endif
        mov ax,bx
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
@@fw:   mov eax,[si]                    ; fix 160: 4+2 instead of LODSD ~12:
        add si,4                        ; ~20% off the pre-scan. cand =
        mov edx,eax                     ; (v^0A0A0A0Ah)&(v^0D0D0D0Dh) has
        xor eax,0A0A0A0Ah               ; a zero byte exactly when the
        xor edx,0D0D0D0Dh               ; data byte lies in 08h..0Fh (a
        and eax,edx                     ; superset of CR/LF: no false
        lea edx,[eax-01010101h]         ; negatives). Fix 133: EDX = cand-
        not eax                         ; 01010101h while EAX KEEPS cand -
        and eax,edx                     ; the NOT eats the copy move, the
        test eax,80808080h             ; (cand-1)&~cand tail is 3 ops, not
        jz @@fwn                        ; 4, and TEST doubles as the mask
        sub si,4                        ; ~10.6 cycles/byte: the pre-scan
        mov dx,4                        ; of a 385 KB file drops ~30% on
@@dr:   mov al,[si]                     ; fix 160: 4+2 vs LODSB ~12 per
        inc si                          ; re-scanned byte. DX is free here:
        sub al,10                       ; no exit has run, it is still the
        cmp al,3                        ; entry 0 and every exit below
        ja @@drn                        ; writes it before @@dones.
        je @@cr4                        ; CR: the shared peek handler (fix
        or al,al                        ; 135: the JA branch kept the CMP's
        jz @@lfx                        ; flags - the second CMP was dead)
@@drn:  dec dx
        jnz @@dr
@@fwn:  dec cx                           ; fix 134: DEC/JNZ, not LOOP (11
        jnz @@fw                         ; cycles taken on a 386)
        jmp @@t4                        ; the 0-3 residue bytes
        else
        shr cx,3                        ; CX = 8-byte units (fix 67:
        jz @@t4                         ; unroll-8 halves the LOOP toll;
                                        ; fix 87: the unroll and its
                                        ; candidate handlers now live INSIDE
                                        ; the 8086 branch - 1.11 assembled
                                        ; them unreferenced on -3)
@@f8:   mov ax,[si]                     ; fix 161: 14 vs LODSW 16 per pair
        add si,2                        ; (P1 = AL, P2 = AH)
        sub al,10
        cmp al,3                        ; P1 in 0Ah..0Dh?
        jbe @@candlo
        sub ah,10
        cmp ah,3                        ; P2 in 0Ah..0Dh?
        jbe @@candhi
        mov ax,[si]                     ; fix 161: 14 vs LODSW 16; P3/P4:
        add si,2                        ; the same pair contract
        sub al,10                       ; (AL = P-10, AH = the partner
        cmp al,3                        ; byte, SI past the pair), so the
        jbe @@candlo                    ; shared @@candlo/@@candhi
        sub ah,10                       ; handlers serve all eight halves
        cmp ah,3
        jbe @@candhi
        mov ax,[si]                     ; fix 161: 14 vs LODSW 16. P5/P6
        add si,2
        sub al,10
        cmp al,3
        jbe @@candlo
        sub ah,10
        cmp ah,3
        jbe @@candhi
        mov ax,[si]                     ; fix 161: 14 vs LODSW 16. P7/P8
        add si,2
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
        je @@cr4                        ; CR: the peek decides the eat
        or al,al                        ; (fix 135: the second CMP was dead
        jz @@lfx                        ; - the JA kept the CMP's flags)
@@t4n:  if USE386
        dec cx                          ; fix 134: DEC/JNZ on -3 (LOOP is
        jnz @@t4b                       ; 11 cycles taken on a 386)
        else
        loop @@t4b                      ; VT/FF: plain data
        endif
        jmp @@refill
@@cr4:  cmp si,bx
        jae @@crhi                      ; block edge / EOF: GetByte peek
        cmp byte ptr [si],10
        je @@cr4e                       ; CRLF: eat it (canonical, 136)
        jmp @@lfx                       ; CR only (canonical, 136)
@@cr4e: inc si                          ; canonical CRLF exit (fix 136):
        mov dx,1                        ; eat the LF, the line ended
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
        je @@crh2                       ; CR at P2: peek the next byte
        or ah,ah
        jz @@lfx                        ; LF at P2: consumed with the pair
        jmp @@next                      ; VT/FF: both were data
@@crh2: cmp si,bx                       ; mid-block: peek INLINE (fix 127:
        jae @@crhi                      ; the @@crhi GetByte path parks
        cmp byte ptr [si],10            ; the byte in the unget slot with
        je @@cr4e                       ; bIdx one PAST it - 1.20 left
        jmp @@lfx                       ; curPos 1 byte late there (fix
                                        ; 130 repairs it at @@dones); the
                                        ; INLINE peek never touches bIdx,
                                        ; so it is exact by construction
                                        ; (fix 127's own claim) and stays
                                        ; the fast path; @@crhi only sees
                                        ; the true block edge / EOF. The
@@crlo:                                 ; exits merge into the common
        cmp ah,10                       ; canonicals (fix 136): @@cr4e eats
        je @@lfx                        ; the CRLF pair, @@lfx ends the
        jmp @@decf                      ; line with SI right, @@decf steps
@@lflo:                                 ; SI back onto the partner byte
        dec si
        endif
@@lfx:  mov dx,1                        ; canonical exit (fix 136): the byte
        jmp @@donef                     ; was consumed, SI already sits on
@@decf: dec si                          ; the next line's first byte. The
        mov dx,1                        ; canonical DEC variant serves the
        jmp @@donef                     ; P1 LF / P1-P2 CR-only exits: the
                                        ; 13 duplicated stubs of 1.21
                                        ; became jumps to two canonicals
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
        cmp hFull,0                     ; fix 130: the unget slot holds
        je @@unadj                      ; the byte AT curPos - GetByte had
        mov ax,word ptr curPos          ; INC'd bIdx PAST it, so fix 127's
        sub ax,1                        ; "exact at the block edge" was off
        mov word ptr curPos,ax          ; by one for every observer (vPos,
        mov ax,word ptr curPos+2        ; CachePos, SeekSoft) while a peek
        sbb ax,0                        ; was pending. 2.02f (fix 225): the
        mov word ptr curPos+2,ax        ; adjust is a REAL 32-bit decrement
@@unadj:                                ; - the 1-word DEC wrapped a curPos
        or dx,dx                        ; low word of 0 (bBase+bIdx on a 64
                                        ; KiB boundary) into +FFFF instead
                                        ; of borrowing from the high word:
                                        ; the reader jumped 64 KiB forward
                                        ; at the next SeekSoft. sub/sbb
                                        ; borrows correctly.
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
        mov ax,bLen                     ; fix 144: the bIdx sync here was
        add word ptr bBase,ax           ; dead - FillBuf always writes
        adc word ptr bBase+2,0          ; bIdx=0 and both continuations
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
        mov si,offset bBuf              ; bIdx = 0 here (FillBuf): reload
        jmp @@fx                        ; SI, share the recompute (fix 121)
@@slowin:                               ; the unget slot only: byte per byte
                                        ; (STDIN is buffered too, fix 75)
        call GetByte
        jc @@dones                      ; EOF (DX=0: partial lines count)
        cmp al,10
        je @@slf
        cmp al,13
        je @@scr                        ; CR: peek the next byte (the
        jcxz @@swrp                     ; unget slot may hold it again)
        mov [di],al
        inc di
        dec cx
@@ssk:  jmp @@slowin
@@swrp: .if (wrapOn)                    ; 2.02f (fix 226): row full in wrap
                mov hByte,al            ; mode: unget the byte - it opens
                mov hFull,1             ; the next visual row (the non-wrap
                mov dx,1                ; path CONSUMES it, the >capacity
                jmp @@dones             ; tail behavior of fix 54)
        .endif
        jmp @@ssk
@@slf:  jmp @@crd2                       ; LF: the line ended (fix 136:
                                        ; both @@slowin exits share the
                                        ; canonical @@crd2)
@@scr:  call GetByte                    ; block edge / EOF / STDIN safe
        jc @@scrd
        cmp al,10
        je @@scrd                       ; CRLF: both consumed
        mov hByte,al                    ; fix 7: keep the byte (inline,
        mov hFull,1                     ; fix 56)
@@scrd: jmp @@crd2
RdLine endp

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
        .if (hexMode)
                call HexDraw
                call DrwBar
                call DrwSt
        .else
                call DrwCnt
                call DrwBar
                call DrwSt
        .endif
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
; DrwHdr - title bar: "4VIEW[386] x.xx - <path\name>" (or STDIN). Painted by
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
        mov ax,curLine                  ; fix 183: register compare
        .if (!isFile || (vcValid != 0 && ax==vcTop))
                ; the merged buffer already holds this view (fix 85):
                ; STDIN's ring, or the file view-cache hit (fix 63) -
                ; paint the slots, zero file access
                call RingPaint
                ret
        .endif
        mov es,vSeg
        SAVEPOS savPos
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
                cmp bx,offset vCache+LINES_VIS*SLOTSZ
                jb @@cwc                 ; fix 153: same UNSIGNED compare,
                mov bx,offset vCache     ; now by opcode for ANY image
@@cwc:                                  ; layout (the .if relied on
                                        ; 0CA07h not fitting SWORD,
                                        ; fix 149)
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
        RESTPOS savPos
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
        ; 2.02: hex mode computes hexRows = (fileSize+15)/16 then uses
        ; the SAME thumb code as text mode. The old hex branch had a
        ; jbe @@f that jumped to @@hcap (the next @@ label) instead of
        ; the full-thumb @@f in the text section - a label resolution
        ; bug that broke the thumb for small files and complicated the
        ; code for no benefit.
        mov ax,totLines
        .if (hexMode)
                HEXROWS                 ; AX = hex rows (2.02b: was inline)
        .endif
        ; AX = effective total (totLines text / hexRows hex)
        or ax,ax
        jz @@d
        cmp ax,LINES_VIS        ; unsigned: whole file on screen?
        jbe @@f
        ; 2.02a fix: save effective total on STACK, not in BX -
        ; FastMul 22 may use BX as a temp on the 8086 build (shift-and-add
        ; for 22=16+4+2 needs a temp register), and saving in BX before
        ; FastMul left garbage in the divisor → #DE → hang.
        push ax                 ; save effective total on stack
        mov ax,curLine
        FastMul 22              ; DX:AX = curLine*22
        pop bx                  ; BX = effective total (safe from FastMul)
        sub bx,LINES_VIS        ; BX = effective total - LINES_VIS (>= 1)
        div bx                  ; AX = thumb row (0..LINES_VIS-1)
        ; 2.02c: removed dead .if (ax>=LINES_VIS) clamp - the quotient
        ; is bounded to 0..22 because curLine <= effective_total-LINES_VIS
        ; so curLine*22/(eff-LINES_VIS) <= 22 (same class as fix 159)
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
        .if (hexMode)                   ; 2.02: hex mode shows byte offset
                mov di,offset stBuf     ; and byte-based percentage, not
                mov si,offset sOff      ; text line numbers
                call Cpy
                ; byte offset = curLine << 4 via FastMul 16 (2.02f fix
                ; 229): the 386 build gets the native movzx/shl/shld
                ; (3 instructions vs the 8 shl/rcl pairs, ~12 cycles
                ; less per DrwSt); the 8086 expansion is byte-identical
                ; to the chain it replaces (xor dx,dx + 4 shl/rcl pairs)
                mov ax,curLine
                FastMul 16
                call U2A32              ; 32-bit decimal
                mov al,'/'
                stosb
                mov ax,word ptr fileSize
                mov dx,word ptr fileSize+2
                call U2A32
                mov ax,'  '
                stosw
                ; percentage = curLine*100 / hexRows
                HEXROWS                 ; AX = hex rows (2.02b: was inline)
                or ax,ax
                jz @@np                  ; empty file
                ; 2.02a fix: save hexRows on STACK, not BX - FastMul 100
                ; may clobber BX on the 8086 build (same bug as DrwBar)
                push ax                  ; save hexRows on stack
                mov ax,curLine
                FastMul 100
                pop bx                   ; BX = hexRows (safe from FastMul)
                div bx
                call U2A
                mov al,'%'
                stosb
                jmp @@np
        .endif
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
        ; fix 171: restore typematic rate to IBM AT default
        .if (svType)
                mov ax,0305h          ; INT 16h AH=03h AL=05h
                mov bl,22h            ; 500 ms delay, ~10 cps (AT default)
                int 16h
        .endif
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
; U2A - unsigned AX -> decimal ASCIZ at ES:DI.
; 386+ (fix 169): five DIV bx (one per digit). DIV r/m16 costs 14-22
; cycles on a 386 - cheaper than the fix 13 shift chain (10+ shifts
; plus the .while correction loop) and far simpler.
; 8086 (fix 13): division by 10 with shifts and adds
; (q = ((x>>1)+(x>>2) + corrections) >> 3, exact for the whole 16-bit
; range): on a real 8086 SHL costs ~2 cycles while DIV r/m16 costs
; ~144-162 - the chain wins by ~6x. The >>8 step copies AH into AL
; instead of eight one-bit shifts (fix 38).
; Both paths push digits AH=0 (fix 148: one pop feeds the digit
; straight into the string), most-significant first.
;------------------------------------------------------------------------------
U2A proc uses bx cx dx si
        if USE386
        mov bx,10                       ; divisor
        xor cx,cx                       ; digit count
@@d3:   xor dx,dx                       ; DX:AX = 0:quotient-so-far
        div bx                          ; AX = quotient, DX = remainder (0..9)
        push dx                         ; the digit (AH=0 on the push)
        inc cx
        or ax,ax                        ; quotient = 0? done
        jnz @@d3
@@o3:   pop ax                          ; fix 148: the digits are pushed
        add al,'0'                      ; with AH=0 - one pop feeds the
        stosb                           ; digit straight into the string
        loop @@o3
        ret
        else
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
@@o:    pop ax                          ; fix 148: the digits are pushed
        add al,'0'                      ; with AH=0 - one pop feeds the
        stosb                           ; digit straight into the string
        loop @@o
        ret
        endif
U2A endp

;==============================================================================
; 2.00 NEW PROCS
;==============================================================================

PopAsk proc uses bx dx si di bp
        mov askMax,cx
        mov word ptr askBuf,di
        mov word ptr askCnt,0
        mov bp,40
        mov ax,78
        sub ax,bp
        shr ax,1
        mov popCol,ax
        mov ax,21
        sub ax,4
        shr ax,1
        mov popRow,ax
        mov di,popRow
        shl di,5
        mov ax,di
        shl ax,2
        add di,ax
        mov ax,popCol
        shl ax,1
        add di,ax
        mov popOff,di
        .if (mPres)
                mov ax,2
                int 33h
        .endif
        mov dx,4
        push es, ds                   ; the save loop - SI becomes its video
        push si                       ; cursor, so fix 173 parks the prompt
        mov si,popOff                 ; pointer on the stack: 2.00 painted
        mov ax,vSeg                   ; the prompt row from CODE BYTES
        mov ds,ax                     ; (garbage) once the loop was done
        mov ax,ss
        mov es,ax
        mov di,offset popSave
        .repeat
                mov cx,bp
                add cx,2
                add cx,cx
                BLKCP
                AdvRow si
                dec dx
        .untilz
        pop si                        ; fix 173: the prompt pointer back
        pop ds
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
        mov ah,ATTR_POP
        mov al,0BAh
        stosw
        mov cx,bp
@@pl:   mov al,[si]
        or al,al
        jz @@pd
        stosw
        inc si
        loop @@pl
@@pd:   mov al,' '
        rep stosw
        mov al,0BAh
        stosw
        AdvRow di
        mov ah,ATTR_POP
        mov al,0BAh
        stosw
        mov ax,A_POP or ' '
        mov cx,bp
        rep stosw
        mov al,0BAh
        stosw
        AdvRow di
        mov ah,ATTR_POP
        mov al,0C8h
        stosw
        mov al,0CDh
        mov cx,bp
        rep stosw
        mov al,0BCh
        stosw
@@in:   call ReadKey
        .if (al==0Dh)
                jmp @@done
        .endif
        .if (al==1Bh)
                mov word ptr askCnt,0
                jmp @@done
        .endif
        .if (al==8)
                mov ax,word ptr askCnt
                or ax,ax
                jz @@in
                dec word ptr askCnt
                call AskPaint
                jmp @@in
        .endif
        mov dl,al                   ; fix 186: park the CHARACTER - 2.00
        mov ax,word ptr askCnt     ; loaded askCnt into AX first, so the
        cmp ax,askMax              ; "mov [bx],al" store wrote the COUNTER
        jae @@in                   ; (00 01 02 ...) instead of the typed
        mov bx,word ptr askBuf    ; text: every search pattern and every
        add bx,ax                  ; goto number was garbage
        mov [bx],dl
        inc word ptr askCnt
        call AskPaint
        jmp @@in
@@done: mov cx,word ptr askCnt
        mov bx,word ptr askBuf
        add bx,cx
        mov byte ptr [bx],0
        mov ax,vSeg
        mov es,ax
        mov di,popOff
        mov si,offset popSave
        mov dx,4
        .repeat
                mov cx,bp
                add cx,2
                add cx,cx
                BLKCP
                AdvRow di
                dec dx
        .untilz
        .if (mPres)                   ; show the mouse BEFORE snapping CX:
                mov ax,1              ; 2.02: INT 33h AX=1 should preserve CX
                int 33h               ; but some clone drivers are sloppy -
        .endif                        ; reload the count LAST so it is safe
        mov cx,word ptr askCnt        ; fix 188: AdvRow leaves 156-2*BP in CX
                                        ; - 2.00 returned that instead of the
                                        ; count, so srLen took garbage values
        pop es
        ret
PopAsk endp

AskPaint proc uses ax bx cx dx si di
        mov es,vSeg
        mov di,popRow
        add di,2
        shl di,5
        mov ax,di
        shl ax,2
        add di,ax
        mov ax,popCol
        inc ax
        shl ax,1
        add di,ax
        mov cx,40
        mov bx,word ptr askBuf
        mov si,0
        mov ah,ATTR_POP
        mov dx,word ptr askCnt          ; 2.02f (fix 223): paint EXACTLY the
        mov cx,dx                       ; typed chars - the NUL terminator
        jcxz @@bl                       ; is only written at @@done, so the
@@l:    mov al,[bx+si]                  ; old scan-to-NUL repainted STALE
        stosw                           ; bytes after a backspace and kept
        inc si                          ; characters of a previous prompt
        loop @@l                        ; when the buffer (srPat) was reused
@@bl:   mov cx,40                       ; with a shorter text; then pad
        sub cx,dx                       ; the rest of the 40-cell field
        mov al,' '
        rep stosw
@@pd2:  ret
AskPaint endp

AtoU proc uses bx cx dx
        xor bx,bx
        xor cx,cx
@@l:    mov al,[si]
        cmp al,'0'
        jb @@d
        cmp al,'9'
        ja @@d
        sub al,'0'
        cbw
        xchg ax,bx
        mov cx,10
        mul cx
        add ax,bx
        xchg ax,bx
        inc si
        jmp @@l          ; 2.02b: removed dead "inc cx" (cx was set to 10
                         ; by "mov cx,10" above, inc made it 11 but the
                         ; "mov cx,10" on the next iteration reset it)
@@d:    mov ax,bx
        or cx,cx
        stc
        jz @@e
        clc
@@e:    ret
AtoU endp


U2A32 proc uses ax bx cx dx si
        mov si,10
        xor cx,cx
@@l:    push ax
        mov ax,dx
        xor dx,dx
        div si
        mov bx,ax
        pop ax
        div si
        push dx
        mov dx,bx
        or bx,ax                       ; fix 172: test the 32-bit quotient
        jz @@e                         ; WITHOUT destroying DX:AX - BX holds
        inc cx                         ; the high quotient and is dead here.
        jmp @@l                        ; 2.00's "or dx,ax" left DX = high|low
                                        ; and the next iteration divided the
                                        ; mangled pair: the value never hit
                                        ; 0:0, the loop pushed one word per
                                        ; round until SP walked through the
                                        ; whole segment and the program
                                        ; itself - 'I' and 'V' hung the
                                        ; viewer (the reported cuelgue)
@@e:    inc cx
@@o:    pop ax
        add al,'0'
        stosb
        loop @@o
        ret
U2A32 endp

ShowInfo proc
        push ax
        push bx
        push cx
        push dx
        push di
        push si
        push es
        push ds
        pop es
        ; Build the info lines into infoBuf (7 slots of 80 bytes each).
        ; PopLine clips to the popup width, so overflow is safe.
        ; Line 1: "File: <name>"
        mov di,offset infoBuf
        mov si,offset sIFile
        call Cpy
        mov si,offset fName
        .if (!isFile)
                mov si,offset sSTDIN
        .endif
        call Cpy
        mov byte ptr [di],0
        ; Line 2: "Size: <bytes> bytes"
        mov di,offset infoBuf+80
        mov si,offset sSize
        call Cpy
        mov ax,word ptr fileSize
        mov dx,word ptr fileSize+2
        call U2A32
        mov si,offset sBytes
        call Cpy
        mov byte ptr [di],0
        ; Line 3: "Date: <dd-mm-yyyy hh:mm>" (file date/time, INT 21h 5700h)
        mov di,offset infoBuf+160
        .if (isFile)
                mov bx,hFile
                mov ax,5700h
                int 21h
                .if (!carry?)
                        mov svDate,cx
                        mov svTime,dx
                        mov si,offset sIDate
                        call Cpy
                        mov bx,svDate        ; cache in BX (U2A preserves it)
                        mov ax,bx
                        and ax,1Fh            ; day of month
                        call U2A
                        mov al,'-'
                        stosb
                        mov ax,bx
                        shr ax,5              ; month (SMART.INC: faster than mov cl,5)
                        and ax,0Fh
                        call U2A
                        mov al,'-'
                        stosb
                        mov ax,bx
                        shr ax,9              ; year - 1980 (SMART.INC macro)
                        add ax,1980
                        call U2A
                        mov al,' '
                        stosb
                        mov bx,svTime         ; cache in BX
                        mov ax,bx
                        shr ax,11             ; hour (SMART.INC macro)
                        call U2A
                        mov al,':'
                        stosb
                        mov ax,bx
                        shr ax,5              ; minute
                        and ax,3Fh
                        call U2A
                .endif
        .endif
        mov byte ptr [di],0
        ; Line 4: "Lines: <totLines>"
        mov di,offset infoBuf+240
        mov si,offset sILines
        call Cpy
        mov ax,totLines
        call U2A
        mov byte ptr [di],0
        ; Line 5: "Position: line <curLine+1>"
        mov di,offset infoBuf+320
        mov si,offset sIPos
        call Cpy
        mov ax,curLine
        inc ax
        call U2A
        mov byte ptr [di],0
        ; Line 6: blank
        mov byte ptr infoBuf+400,0
        ; Line 7: mode
        mov di,offset infoBuf+480
        .if (hexMode)
                mov si,offset sIHex
        .else
                mov si,offset sIText
        .endif
        call Cpy
        mov byte ptr [di],0
        ; Show the popup (7 lines, width 44)
        mov bx,offset infoTab
        mov cx,7
        mov dx,44
        call PopUp
        pop es
        pop si
        pop di
        pop dx
        pop cx
        pop bx
        pop ax
        ret
ShowInfo endp

PrintFile proc
        .if (!isFile)
                ret
        .endif
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push es
        SAVEPOS prnSave               ; fix 178: saved before anything can
        mov dx,offset sPRN            ; fail, restored on every exit - the
        mov ax,3D01h                  ; 2.00 error paths returned with the
        int 21h                       ; reader anchored at BOF while curPos
        jc @@err                      ; still pointed at the view, so the
        mov word ptr prnH,ax          ; next refill served the file's top
        mov bx,hFile
        xor cx,cx
        xor dx,dx
        mov ax,4200h
        int 21h
        mov word ptr bBase,0
        mov word ptr bBase+2,0
        mov bLen,0
        mov bIdx,0
        mov hFull,0
@@l:    mov bx,hFile
        mov ah,3Fh
        mov dx,offset bBuf
        mov cx,BUFSZ
        int 21h
        jc @@err2
        or ax,ax
        jz @@eof
        mov cx,ax
        mov bx,word ptr prnH
        mov ah,40h
        mov dx,offset bBuf
        int 21h
        jc @@err2
        jmp @@l
@@eof:  mov bx,word ptr prnH
        mov ah,40h
        mov dx,offset sFF
        mov cx,1
        int 21h
        mov bx,word ptr prnH
        mov ah,3Eh
        int 21h
        RESTPOS prnSave
        call SeekSoft
        jmp @@pf_exit
@@err2: mov bx,word ptr prnH
        mov ah,3Eh
        int 21h
@@err:  RESTPOS prnSave               ; fix 178
        call SeekSoft
        mov bx,offset errTab
        mov cx,3
        mov dx,30
        call PopUp
@@pf_exit:
        pop es
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret
PrintFile endp

DoSearch proc
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        .if (!isFile || !srValid)
                xor al,al
                jmp @@ds_exit
        .endif
        SAVEPOS srSave
        mov ax,curLine
        .if (srBack)
                or ax,ax
                jz @@nf                  ; on line 0: nothing above
                xor ax,ax                ; fix 174: back scans from BOF and
        .else                          ; keeps the LAST match < curLine
                inc ax
                cmp ax,totLines
                jae @@nf            ; 2.02b fix: UNSIGNED (was .if SIGNED -
                                    ; files >= 32768 lines read totLines as
                                    ; negative, so the forward search from
                                    ; any early line silently reported "not
                                    ; found" without scanning a single line)
        .endif
        ; ---- walk to the scan's first line. FIX 174: BX counts ABSOLUTE
        ; lines from here on. 2.00 counted from 0 while the reader was
        ; already positioned past curLine lines, so every match was
        ; recorded as a BX-relative "line" and a forward hit could land
        ; the view nowhere (a word on every line reported a match that
        ; moved nothing).
        ; FIX 190: the walk count was read as "mov cx,ax" AFTER
        ; "call SeekSoft" - which clobbers AX - so the walk count was
        ; SeekSoft's leftover (0 for any file under 64 KiB): the walk
        ; never walked, the scan read line 0 while BX said curLine+1,
        ; and every recorded line number was one past the truth.
        mov cx,ax                     ; start line (0 back / curLine+1
        mov di,ax                     ; fwd), captured BEFORE SeekSoft.
                                        ; fix 192: the line counter rides
                                        ; in DI - CachePos clobbers BX (its
                                        ; cache-slot index) and 2.00's BX
                                        ; counter was garbage after the walk
        mov word ptr curPos,0
        mov word ptr curPos+2,0
        mov cCnt,0
        call SeekSoft
        mov cntMode,1
        .while (cx)
                call CachePos
                call RdLine
                .break .if (!al)
                dec cx
        .endw
        mov cntMode,0
        mov wDest,offset lBuf
        mov bp,0FFFFh                 ; DI = the line the reader sits on
@@l:    KeyAvail
        jz @@cont
        push ds
        xor ax,ax
        mov ds,ax
        mov si,ds:[0041Ah]
        mov ax,ds:[si+0400h]
        cmp ax,011Bh
        pop ds
        jz @@abort
        push ds
        xor ax,ax
        mov ds,ax
        mov si,ds:[0041Ah]
        add si,2
        cmp si,003Eh
        jb @@c1
        mov si,001Eh
@@c1:   mov ds:[0041Ah],si
        pop ds
@@cont: call RdLine                    ; 2.02: dead SAVEPOS srSave2 removed
                                        ; (srSave2 was written but never read)
        .if (!al)
                jmp @@done
        .endif
        mov si,offset lBuf
        mov cx,srLen
        call MatchStr
        .if (al)
                .if (srBack)
                        mov bp,di      ; keep the highest match below
                .else                 ; the view: the scan ends there
                        mov bp,di
                        jmp @@done
                .endif
        .endif
@@skip: inc di
        .if (srBack)                  ; fix 174: the back scan stops at the
                cmp di,curLine        ; view's line - 2.00 walked to EOF
                jae @@done
        .endif
        .if (di == 0FFFFh)
                jmp @@done
        .endif
        jmp @@l
@@done: mov cntMode,0
        mov wDest,offset lBuf
        cmp bp,0FFFFh
        je @@nf
        mov curLine,bp
        mov vcValid,0
        mov word ptr curPos,0
        mov word ptr curPos+2,0
        mov cCnt,0
        call SeekSoft
        mov cx,bp
        mov cntMode,1
        .while (cx)
                call CachePos
                call RdLine
                .break .if (!al)
                dec cx
        .endw
        mov cntMode,0
        mov al,1                      ; fix 176: NO curPos reset after the
        jmp @@ds_exit                 ; walk - it left the reader ON the
                                        ; found line; 2.00's copy-pasted
                                        ; "curPos=0 / SeekSoft" re-anchored
                                        ; at BOF and the view showed lines
                                        ; 0..22 labelled as the hit
@@abort:mov cntMode,0
        mov wDest,offset lBuf
        RESTPOS srSave                ; fix 175: the abort exit left curPos
        call SeekSoft                 ; deep inside the scan while curLine
        xor al,al                     ; stayed put - the next Down painted
        jmp @@ds_exit                 ; middle-of-file lines. Re-anchor.
@@nf:   RESTPOS srSave
        call SeekSoft
        mov bx,offset nfTab
        mov cx,3
        mov dx,28
        call PopUp
        xor al,al
@@ds_exit:
        pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        ret
DoSearch endp

MatchStr proc
        push bx
        push cx
        push dx
        push si
        push di
        .if (cx == 0)
                xor al,al
                jmp @@ms_exit
        .endif
        mov bx,si
@@outer:
        mov si,bx
        mov di,0
@@inner:
        lodsb
        or al,al
        jz @@nofound
        mov dl,srPat[di]
        .if (srCase)
                cmp al,dl
        .else
                ; 2.02f (fix 230) OPT: the two UpCase CALLs inlined -
                ; the scan loop paid 2x (call+ret+cmps), ~40 cycles per
                ; compared character on an 8086, for every character of
                ; every scanned line. Same logic, zero calls.
                cmp al,'a'
                jb @@mu1
                cmp al,'z'
                ja @@mu1
                sub al,20h
@@mu1:          xchg al,dl              ; the pattern char takes AL's place
                cmp al,'a'
                jb @@mu2
                cmp al,'z'
                ja @@mu2
                sub al,20h
@@mu2:          cmp al,dl
        .endif
        jne @@advance
        inc di
        cmp di,cx
        jb @@inner
        mov al,1
        jmp @@ms_exit
@@advance:
        inc bx
        mov al,[bx]
        or al,al
        jnz @@outer
@@nofound:
        xor al,al
@@ms_exit:
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        ret
MatchStr endp

; (UpCase was folded into MatchStr's inner loop by fix 230: it had no
; other caller, and the CALL/RET pair it cost per compared character
; dominated the insensitive search scan.)

SetBm proc
        mov ax,curLine
        mov bmLine,ax
        mov ax,hPos
        mov bmHPos,ax
        mov bmValid,1
        ret
SetBm endp

GotoBm proc
        .if (!bmValid)
                ret
        .endif
        mov ax,bmLine
        mov curLine,ax
        mov ax,bmHPos
        mov hPos,ax
        mov vcValid,0
        .if (hexMode)           ; fix 177: hex rows address directly -
                xor al,al            ; HexDraw seeks per row, no text walk
                ret
        .endif
        call GoLine
        ret
GotoBm endp

DetectBinary proc
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push es
        .if (!isFile)
                jmp @@exit
        .endif
        push ds
        pop es
        ; fix 179: Init leaves the fresh reader at BOF (DOS pointer =
        ; bBase = curPos = 0, bLen = 0) - 2.00 seeked to BOF twice for
        ; nothing. The probe reads through GetByte/FillBuf, so the first
        ; 32 KiB block STAYS buffered and CountLines scans it without
        ; paying a single extra DOS read.
        mov di,offset hxBuf
        mov cx,512
@@rl:   call GetByte            ; OPT: GetByte preserves CX (only BX,AX;
        jc @@done               ; FillBuf saves CX via uses) - push/pop
        mov [di],al             ; was redundant
        inc di
        loop @@rl
@@done: mov cx,di
        sub cx,offset hxBuf
        .if (cx == 0)
                jmp @@rst
        .endif
        mov di,cx
        mov si,offset hxBuf
        xor dx,dx
@@cl:   lodsb
        cmp al,9
        jb @@bin                   ; 0..8: control
        cmp al,13
        jbe @@ok                   ; 9..13: TAB/LF/VT/FF/CR
        cmp al,20h
        jb @@bin                   ; 14..31: control
        cmp al,7Eh
        jbe @@ok                   ; 32..126: printable
@@bin:  inc dx                     ; fix 179: >= 7Fh counts too - 2.00's
@@ok:   loop @@cl                  ; "jbe/jmp ok" made EVERY byte "ok" and
                                        ; a file of pure FFh was "text"
        mov ax,dx
        mov bx,20
        mul bx
        cmp ax,di
        jb @@rst
        mov binFile,1
@@rst:  mov bIdx,0                  ; fix 179: rewind INSIDE the buffered
        mov hFull,0                 ; block: no seek, no refill - CountLines
        mov word ptr curPos,0       ; reuses the block the probe loaded
        mov word ptr curPos+2,0
@@exit: pop es
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret
DetectBinary endp

HexDraw proc uses ax bx cx dx si di bp
        ; 2.02: complete rewrite. The 2.01 HexDraw had three defects
        ; visible in the screenshot: (a) the separate 23-row clear loop
        ; painted cols 1-77 but the per-row paint then wrote from col 1
        ; again with stosw whose DI was recomputed from BP - rows past
        ; EOF were left as the clear's spaces but the address column
        ; of data rows showed "0000" because curPos was read AFTER
        ; GetByte had advanced bIdx through 16 bytes and the reader's
        ; curPos invariant (bBase+bIdx) had drifted from the row start
        ; stored in @@read; (b) no ASCII gutter was painted when the
        ; hex-byte loop's stosw count miscalculated the column budget;
        ; (c) DrwSt showed text-line numbers (meaningless in hex mode).
        ; The rewrite paints one row per iteration: compute offset,
        ; blank the row if past EOF, else seek+read+paint in one pass.
        ; The address is captured BEFORE GetByte touches the reader.
        mov es,vSeg
        xor bp,bp
@@row:  ; byte offset = (curLine + bp) * 16 = (curLine+bp) << 4
        if USE386
        ; OPT: 386 native 32-bit ops - movzx zero-extends both operands
        ; so curLine+bp cannot overflow 32 bits; one shl eax,4 replaces
        ; 4 shl/rcl pairs (~40 cycles saved per row, ~920 per hex frame)
        movzx   eax,word ptr curLine
        movzx   edx,bp
        add     eax,edx               ; eax = curLine+bp (32-bit)
        shl     eax,4                 ; eax = (curLine+bp) * 16
        cmp     eax,dword ptr fileSize
        jae     @@blank               ; past EOF
        mov     dword ptr curPos,eax  ; capture BEFORE GetByte moves reader
        else
        mov     ax,curLine
        add     ax,bp
        mov     dx,0              ; 2.02b: MOV (not xor) preserves CF from add
        adc     dx,0              ; propagate carry if curLine+bp > 65535
        shl     ax,1             ; x2
        rcl     dx,1
        shl     ax,1             ; x4
        rcl     dx,1
        shl     ax,1             ; x8
        rcl     dx,1
        shl     ax,1             ; x16
        rcl     dx,1
        ; past EOF? -> blank row
        cmp     dx,word ptr fileSize+2
        ja      @@blank
        jb      @@read
        cmp     ax,word ptr fileSize
        jae     @@blank
@@read: ; capture the row's byte offset BEFORE GetByte moves the reader
        mov     word ptr curPos,ax
        mov     word ptr curPos+2,dx
        endif
        call SeekSoft
        ; 2.02f (fix 227) OPT: when the whole row lies inside the
        ; buffered block, copy the 16 bytes STRAIGHT from bBuf - 16
        ; GetByte calls (call+ret plus the bIdx/bLen tests each,
        ; ~40 cycles per byte on an 8086) become one REP MOVS
        ; (~9 cycles per byte on an 8086, ~1 on a 386: ~480 cycles
        ; less per hex row on an 8086, ~11K per 23-row frame). The
        ; reader state is identical (bIdx += 16, hFull = 0: SeekSoft
        ; just cleared it) and the GetByte path below still handles
        ; the block edge, the refill and the EOF padding.
        mov     ax,bLen
        sub     ax,bIdx                 ; bytes left in the block
        cmp     ax,16
        jb      @@rl                    ; short: the GetByte path
        push    es
        push    ds
        pop     es                      ; ES=DS: bBuf -> hxBuf copy
        mov     si,bIdx
        add     si,offset bBuf
        mov     di,offset hxBuf
        mov     cx,16
        BLKCP                           ; widest copy of the build (even)
        pop     es
        add     bIdx,16                 ; same invariant GetByte leaves
        jmp     @@paint
@@rl:   mov di,offset hxBuf
        mov cx,16
@@rl1:  call GetByte            ; OPT: GetByte preserves CX (only clobbers
        jc @@pad                ; BX,AX; FillBuf saves CX via uses list) -
                                ; the push/pop was redundant
        mov [di],al
        inc di
        if USE386
        dec cx
        jnz @@rl1
        else
        loop @@rl1
        endif
        jmp @@paint
@@pad:  xor al,al
@@padl: mov [di],al
        inc di
        if USE386
        dec cx
        jnz @@padl
        else
        loop @@padl
        endif
@@paint:
        ; video offset = 160 + 2 + bp*160 = 162 + (bp<<7) + (bp<<5)
        mov ax,bp
        shl ax,5                 ; bp*32
        mov di,ax
        shl ax,2                 ; bp*128
        add di,ax               ; di = bp*160
        add di,160+2
        ; address: 8 hex digits from the captured curPos (untouched by
        ; GetByte - it lives in memory, read here after the read loop)
        mov ax,word ptr curPos
        mov dx,word ptr curPos+2
        mov cx,ax               ; park low word in CX (HexB preserves CX)
        mov ah,ATTR_CONT        ; attribute for the whole row
        mov al,dh
        call HexB               ; bits 24-31
        mov al,dl
        call HexB               ; bits 16-23
        mov al,ch
        call HexB               ; bits 8-15
        mov al,cl
        call HexB               ; bits 0-7
        ; separator: 2 spaces
        mov al,' '
        stosw
        stosw
        ; 16 hex bytes, each "XX " (2 hex digits + 1 space)
        mov si,offset hxBuf
        mov cx,16
@@bl:   lodsb
        call HexB
        mov al,' '
        stosw
        if USE386
        dec cx
        jnz @@bl
        else
        loop @@bl
        endif
        ; ASCII gutter: 16 chars, unprintables -> '.'
        mov si,offset hxBuf
        mov cx,16
@@al:   lodsb
        cmp al,20h
        jb @@ad
        cmp al,7Eh
        jbe @@ap
@@ad:   mov al,'.'
@@ap:   stosw
        if USE386
        dec cx
        jnz @@al
        else
        loop @@al
        endif
        jmp @@next
@@blank:
        ; past EOF: clear this row's content cells to spaces
        mov ax,bp
        shl ax,5
        mov di,ax
        shl ax,2
        add di,ax
        add di,160+2
        mov ax,A_CONT or ' '
        mov cx,LINEWID
        rep stosw
@@next: inc bp
        cmp bp,LINES_VIS
        jb @@row
        ret
HexDraw endp

;------------------------------------------------------------------------------
; HexB - paint AL as two hex digits at ES:DI (AH = attribute). fix 187:
; this was HexDraw's LOCAL "@@hexb" subroutine, but a "proc uses" body
; gets EVERY "ret" expanded with the register pops (ASMC/MASM USES
; semantics) - the local ret became 7 pops + ret and each of the 36
; calls per row ate 7 words of CALLER stack: HexDraw returned through
; a garbage address into the PSP, walked the zeros straight into the
; entry point and RE-RAN Init - Alt+H and every binary file's auto
; hex view crashed the viewer. As its own proc (no USES) its ret is a
; plain ret again.
;------------------------------------------------------------------------------
HexB proc
        mov bl,al
        shr al,4                 ; SMART.INC: native on 386, 4 shifts on 8086
        add al,'0'
        cmp al,'9'
        jbe @@h1
        add al,7
@@h1:   stosw
        mov al,bl
        and al,0Fh
        add al,'0'
        cmp al,'9'
        jbe @@h2
        add al,7
@@h2:   stosw
        ret
HexB endp


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
barCells        db 0                    ; ShowProg's last fill count (164)
estDone         db 0                    ; the 166 rescale is one-shot
cntMode         db 0                    ; RdLine consume-only pass (49)
vSlot           db 0                    ; view cache: top row's slot (63)
vcTop           dw 0                    ; view cache: top line number (63)
vcValid         db 0                    ; slots hold lines vcTop..+22 (63)
popRow          dw 0
popCol          dw 0
popLines        dw 0
popOff          dw 0            ; pop-up corner offset, reused 3x (fix 33)
; --- 2.00 new state (fix 182: the wrap/line-number/word-count plans
; and their 13 dead slots are gone - nothing ever read them) ---
hexMode         db 0
binFile         db 0
wrapOn          db 0                    ; 2.02: word wrap toggle ('W')
bmLine          dw 0
bmHPos          dw 0
bmValid         db 0
srPat           db 32 dup(0)
srLen           dw 0
srBack          db 0
srCase          db 0
srValid         db 0
fileSize        dd 0
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
svType          db 0            ; fix 171: typematic rate changed,
                                ; restore on exit (AT+ only)
sSTDIN          db "STDIN",0
if USE386
sHdr1           db "4VIEW386 ",'0'+VERMAJ,".",'0'+VMIN/10,'0'+VMIN mod 10," - ",0
else
sHdr1           db "4VIEW ",'0'+VERMAJ,".",'0'+VMIN/10,'0'+VMIN mod 10," - ",0
endif
sLoad           db "Loading ",0
sDots           db "...",0
sLn             db "Line ",0
sOff            db "Off ",0            ; 2.02: hex mode status prefix
sKey            db "   ",24,25,27,26," PgUp PgDn F1=Help F10=About ESC",0
sErr            db "Cannot open file.",13,10,'$'
if USE386
s386            db "This build requires a 386 or higher CPU.",13,10,'$'
endif
; help lines: printed by ShowHelp and drawn inside the F1 window (fix 21)
helpTab         dw a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12,a13,a14,a15,a16,a17,a18,a19
if USE386
a1              db "4VIEW386 ",'0'+VERMAJ,".",'0'+VMIN/10,'0'+VMIN mod 10," - text viewer for DOS",0
else
a1              db "4VIEW ",'0'+VERMAJ,".",'0'+VMIN/10,'0'+VMIN mod 10," - text viewer for DOS",0
endif
a2              db "Copyright (c) 2025-2026 Javier G. Chamorro",0
a3              db 0
a4              db "Navigation:",0
a5              db " Up/Dn PgUp/Dn Left/Right scroll",0
a6              db " Home/End top/bottom of file",0
a7              db 0
a8              db "Search (LIST-style):",0
a9              db " F find   S scan   A F3 again",0
a10             db " ` ^ back-find  ' v back-scan   F9",0
a11             db " G goto line N",0
a12             db 0
a13             db "View:",0
a14             db " Alt+H hex view of the file",0
a15             db " I info   Ctrl+P print",0
a16             db " W toggle word wrap",0
a17             db "Ctrl+Y mark  Alt+Y recall",0
if USE386
a18             db "F1 help  F10 about  ESC exit  4VIEW386",0
else
a18             db "F1 help  F10 about  ESC exit  4VIEW",0
endif
a19             db "Mouse: wheel/click scrolls the view",0
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
; --- 2.00 new data ---
askMax          dw 0
askBuf          dw 0
askCnt          dw 0
srSave          dd 0
prnSave         dd 0
prnH            dw 0
svDate          dw 0            ; ShowInfo: file date (INT 21h 5700h)
svTime          dw 0            ; ShowInfo: file time
nfTab           dw nf1,nf2,sBlank
errTab          dw err1,err2,sBlank
sBlank          db 0
sSize           db "Size: ",0
sBytes          db " bytes",0
sPRN            db "PRN",0
sFF             db 0Ch
nf1             db "*** Text not found ***",0
nf2             db 0
err1            db "Print error",0
err2            db 0
sAskFind        db "Find:",0
sAskScan        db "Scan:",0
sAskGoto        db "Go to line:",0
sAskFindB       db "Find back:",0
sAskScanB       db "Scan back:",0
; --- 2.02: info popup strings ---
sIFile          db "File: ",0
sILines         db "Lines: ",0
sIPos           db "Position: line ",0
sIDate          db "Date: ",0
sIHex           db "Mode: Hex view",0
sIText          db "Mode: Text view",0
infoTab         dw offset infoBuf, offset infoBuf+80, offset infoBuf+160, offset infoBuf+240, offset infoBuf+320, offset infoBuf+400, offset infoBuf+480
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
; lives ~7.6 KB above BMEMTOP at the top of the segment (24 KB until
; fix 118 doubled BUFSZ).
FILEEND         db "<4VIEW202>",0       ; last initialized bytes: the
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
hxBuf           equ tBuf+128           ; 512 bytes (2.02b: was 16, overflowed
                                        ; by DetectBinary's 512-byte probe)
infoBuf         equ hxBuf+512           ; 560 bytes: 7 lines * 80 (2.02c info popup)
BMEMTOP         equ infoBuf+560        ; last RAM byte the program owns
end