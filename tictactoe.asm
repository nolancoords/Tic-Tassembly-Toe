; ============================================================
;  Tic-Tac-Toe in x86 NASM for Windows
;  Pure Win32 GDI — no C runtime, just vibes and syscalls.
;
;  Build:
;    nasm -f win32 tictactoe.asm -o tictactoe.obj
;    golink /entry _WinMain@16 tictactoe.obj kernel32.dll user32.dll gdi32.dll
;
;  Keys 1-9 place your piece (numpad layout).
;  SPACE restarts after the game ends.
;  X always goes first.
; ============================================================

bits 32
global _WinMain@16

extern _GetModuleHandleA@4
extern _RegisterClassExA@4
extern _CreateWindowExA@48
extern _ShowWindow@8
extern _UpdateWindow@4
extern _GetMessageA@16
extern _TranslateMessage@4
extern _DispatchMessageA@4
extern _PostQuitMessage@4
extern _DefWindowProcA@16
extern _LoadCursorA@8
extern _BeginPaint@8
extern _EndPaint@8
extern _InvalidateRect@12
extern _GetClientRect@8
extern _SetTextColor@8
extern _SetBkMode@8
extern _CreateFontA@56
extern _DeleteObject@4
extern _SelectObject@8
extern _MoveToEx@16
extern _LineTo@12
extern _CreatePen@12
extern _Ellipse@20
extern _FillRect@12
extern _CreateSolidBrush@4
extern _DrawTextA@20
extern _GetStockObject@4

; ============================================================
section .data

className   db "TicTacToe", 0
windowTitle db "Tic-Tac-Toe  [1-9 to play]", 0

WIN_W   equ 540
WIN_H   equ 580
CELL    equ 160
MARGIN  equ 30
LINE_W  equ 1
HALF    equ 55

; Win32 COLORREF = 0x00BBGGRR
COL_BG   equ 0x00E8F0F5
COL_GRID equ 0x00E8F0F5 
COL_X    equ 0x00E8F0F5  
COL_O    equ 0x00E8F0F5  
COL_WIN  equ 0x0000AA00 
COL_TEXT equ 0x00E8F0F5 

PLAYER_X equ 1
PLAYER_O equ 2

; ── precomputed pixel centers for all 9 cells ───────────────
; Each entry is two dwords: cx, cy.
; Computed as: cx = MARGIN + (col * CELL) + CELL/2
;              cy = MARGIN + (row * CELL) + CELL/2
; Laid out row-major so index matches board[] index directly.
; This is the same idea as your LC-3 CELL_OFFSETS table —
; one lookup, no math, nothing gets clobbered mid-draw.
;
;  cell 0 (row0,col0)  cell 1 (row0,col1)  cell 2 (row0,col2)
;  cell 3 (row1,col0)  cell 4 (row1,col1)  cell 5 (row1,col2)
;  cell 6 (row2,col0)  cell 7 (row2,col1)  cell 8 (row2,col2)
;
cellCX: dd (MARGIN + 0*CELL + CELL/2)   ; cell 0 cx
        dd (MARGIN + 1*CELL + CELL/2)   ; cell 1 cx
        dd (MARGIN + 2*CELL + CELL/2)   ; cell 2 cx
        dd (MARGIN + 0*CELL + CELL/2)   ; cell 3 cx
        dd (MARGIN + 1*CELL + CELL/2)   ; cell 4 cx
        dd (MARGIN + 2*CELL + CELL/2)   ; cell 5 cx
        dd (MARGIN + 0*CELL + CELL/2)   ; cell 6 cx
        dd (MARGIN + 1*CELL + CELL/2)   ; cell 7 cx
        dd (MARGIN + 2*CELL + CELL/2)   ; cell 8 cx

cellCY: dd (MARGIN + 0*CELL + CELL/2)   ; cell 0 cy
        dd (MARGIN + 0*CELL + CELL/2)   ; cell 1 cy
        dd (MARGIN + 0*CELL + CELL/2)   ; cell 2 cy
        dd (MARGIN + 1*CELL + CELL/2)   ; cell 3 cy
        dd (MARGIN + 1*CELL + CELL/2)   ; cell 4 cy
        dd (MARGIN + 1*CELL + CELL/2)   ; cell 5 cy
        dd (MARGIN + 2*CELL + CELL/2)   ; cell 6 cy
        dd (MARGIN + 2*CELL + CELL/2)   ; cell 7 cy
        dd (MARGIN + 2*CELL + CELL/2)   ; cell 8 cy

; 8 winning trios, 3 bytes each, cells 0-8 row-major
winTable:
    db 0,1,2   ; top row
    db 3,4,5   ; middle row
    db 6,7,8   ; bottom row
    db 0,3,6   ; left col
    db 1,4,7   ; center col
    db 2,5,8   ; right col
    db 0,4,8   ; diagonal
    db 2,4,6   ; anti-diagonal

msgXTurn db "X's turn", 0
msgOTurn db "O's turn", 0
msgXWins db "X WINS!   Press SPACE to play again", 0
msgOWins db "O WINS!   Press SPACE to play again", 0
msgDraw  db "DRAW!     Press SPACE to play again", 0

; ============================================================
section .bss

; --- your scratch space (8 dwords) -------------------------
; [0] = X win count  (auto-incremented each game)
; [1] = O win count  (auto-incremented each game)
; [2..7] = free — scores, game counter, options, etc.
userData    resd 8

hInstance   resd 1
hWnd        resd 1

; WNDCLASSEX fields in order (48 bytes in 32-bit mode)
wc_cbSize           resd 1
wc_style            resd 1
wc_lpfnWndProc      resd 1
wc_cbClsExtra       resd 1
wc_cbWndExtra       resd 1
wc_hInstance        resd 1
wc_hIcon            resd 1
wc_hCursor          resd 1
wc_hbrBackground    resd 1
wc_lpszMenuName     resd 1
wc_lpszClassName    resd 1
wc_hIconSm          resd 1

; MSG struct
msg_hwnd    resd 1
msg_message resd 1
msg_wParam  resd 1
msg_lParam  resd 1
msg_time    resd 1
msg_ptx     resd 1
msg_pty     resd 1

; PAINTSTRUCT — hDC at offset 0
ps         resb 64
clientRect resb 16
textRect   resb 16

; ── game state ──────────────────────────────────────────────
; Same idea as your LC-3 xA000/xA200 areas — each has its own
; named home and we always read/write by name, never by offset
; from some other label.
board       resb 9   ; 0=empty, 1=X, 2=O — one byte per cell
currentTurn resb 1   ; PLAYER_X or PLAYER_O
gameOver    resb 1   ; 0 = live, 1 = done
winner      resb 1   ; PLAYER_X, PLAYER_O, or 0 for draw
winLine     resb 1   ; index 0-7 into winTable, 0xFF = nobody won

; ── winning line pixel coords, written once when game ends ──
; Stored here so the paint handler just reads them — no math,
; no register juggling, same discipline as CELL_OFFSETS lookup.
winPt0x resd 1
winPt0y resd 1
winPt1x resd 1
winPt1y resd 1

; ── scratch saved-register slots (like your D_R0..D_R6) ─────
; Used by helpers that need to preserve caller registers.
cc_arg  resd 1   ; cellLookup input: cell index
cc_cx   resd 1   ; cellLookup output: center X
cc_cy   resd 1   ; cellLookup output: center Y

; ============================================================
section .text

; ============================================================
;  WinMain
; ============================================================
_WinMain@16:
    push ebp
    mov  ebp, esp

    push 0
    call _GetModuleHandleA@4
    mov  [hInstance], eax

    mov  dword [wc_cbSize],        48
    mov  dword [wc_style],         3
    mov  dword [wc_lpfnWndProc],   WndProc
    mov  dword [wc_cbClsExtra],    0
    mov  dword [wc_cbWndExtra],    0
    mov  eax, [hInstance]
    mov  [wc_hInstance],           eax
    mov  dword [wc_hIcon],         0
    mov  dword [wc_hbrBackground], 0     
    mov  dword [wc_lpszMenuName],  0
    mov  dword [wc_lpszClassName], className
    mov  dword [wc_hIconSm],       0

    push 32512
    push 0
    call _LoadCursorA@8
    mov  [wc_hCursor], eax

    push wc_cbSize
    call _RegisterClassExA@4

    push 0
    push dword [hInstance]
    push 0
    push 0
    push WIN_H
    push WIN_W
    push 100
    push 100
    push 0x00CF0000
    push windowTitle
    push className
    push 0
    call _CreateWindowExA@48
    mov  [hWnd], eax

    push 1
    push dword [hWnd]
    call _ShowWindow@8
    push dword [hWnd]
    call _UpdateWindow@4

    call initGame

.loop:
    push 0
    push 0
    push 0
    push msg_hwnd
    call _GetMessageA@16
    test eax, eax
    jz   .done
    push msg_hwnd
    call _TranslateMessage@4
    push msg_hwnd
    call _DispatchMessageA@4
    jmp  .loop

.done:
    mov  eax, [msg_wParam]
    pop  ebp
    ret  16


; ============================================================
;  initGame — wipe the board, reset all state
; ============================================================
initGame:
    xor  al, al
    mov  byte [board+0], al
    mov  byte [board+1], al
    mov  byte [board+2], al
    mov  byte [board+3], al
    mov  byte [board+4], al
    mov  byte [board+5], al
    mov  byte [board+6], al
    mov  byte [board+7], al
    mov  byte [board+8], al
    mov  byte [currentTurn], PLAYER_X
    mov  byte [gameOver],    0
    mov  byte [winner],      0
    mov  byte [winLine],     0xFF
    ; clear cached win endpoints too
    mov  dword [winPt0x], 0
    mov  dword [winPt0y], 0
    mov  dword [winPt1x], 0
    mov  dword [winPt1y], 0
    ret


; ============================================================
;  cellLookup — reads pixel center from the precomputed tables
;  in:  [cc_arg] = cell index (0-8)
;  out: [cc_cx]  = center X pixel
;       [cc_cy]  = center Y pixel
;  Trashes eax, ecx only. No division, no register surprises.
; ============================================================
cellLookup:
    mov  ecx, [cc_arg]
    mov  eax, [cellCX + ecx*4]
    mov  [cc_cx], eax
    mov  eax, [cellCY + ecx*4]
    mov  [cc_cy], eax
    ret


; ============================================================
;  checkWin
;  returns  1 = someone won (winner + winLine written)
;           0 = draw
;          -1 = still going
; ============================================================
checkWin:
    push ebx
    push esi
    push edi
    xor  edi, edi

.tryCombo:
    cmp  edi, 8
    jge  .checkDraw

    mov  eax, edi
    mov  ecx, 3
    mul  ecx
    lea  esi, [winTable]
    add  esi, eax

    movzx eax, byte [esi+0]
    movzx ebx, byte [esi+1]
    movzx ecx, byte [esi+2]
    movzx eax, byte [board + eax]
    movzx ebx, byte [board + ebx]
    movzx ecx, byte [board + ecx]

    test  al, al
    jz    .nextCombo
    cmp   al, bl
    jne   .nextCombo
    cmp   al, cl
    jne   .nextCombo

    mov   byte [winner], al
    mov   eax, edi
    mov   byte [winLine], al
    mov   eax, 1
    jmp   .cwDone

.nextCombo:
    inc  edi
    jmp  .tryCombo

.checkDraw:
    xor  ecx, ecx
.scanBoard:
    cmp  ecx, 9
    jge  .itsDraw
    movzx eax, byte [board + ecx]
    test  eax, eax
    jz    .stillGoing
    inc   ecx
    jmp   .scanBoard
.itsDraw:
    mov  byte [winner], 0
    xor  eax, eax
    jmp  .cwDone
.stillGoing:
    mov  eax, -1
.cwDone:
    pop  edi
    pop  esi
    pop  ebx
    ret


; ============================================================
;  WndProc
;  [ebp+8]  hWnd
;  [ebp+12] uMsg
;  [ebp+16] wParam
;  [ebp+20] lParam
;  [ebp-4]  local: saved hDC
; ============================================================
WndProc:
    push ebp
    mov  ebp, esp
    sub  esp, 4
    push ebx
    push esi
    push edi

    mov  eax, [ebp+12]

    cmp  eax, 0x0002
    je   .onDestroy
    cmp  eax, 0x000F
    je   .onPaint
    cmp  eax, 0x0100
    je   .onKey

    push dword [ebp+20]
    push dword [ebp+16]
    push dword [ebp+12]
    push dword [ebp+8]
    call _DefWindowProcA@16
    jmp  .leave

.onDestroy:
    push 0
    call _PostQuitMessage@4
    xor  eax, eax
    jmp  .leave


; ====== KEY HANDLER =========================================
.onKey:
    mov  ebx, [ebp+16]

    cmp  ebx, 0x20
    jne  .notSpace
    cmp  byte [gameOver], 1
    jne  .ignoreKey
    call initGame
    push 0
    push 0
    push dword [ebp+8]
    call _InvalidateRect@12
    xor  eax, eax
    jmp  .leave

.notSpace:
    cmp  byte [gameOver], 1
    je   .ignoreKey
    cmp  ebx, 0x31
    jl   .ignoreKey
    cmp  ebx, 0x39
    jg   .ignoreKey

    sub  ebx, 0x31

    movzx eax, byte [board + ebx]
    test  eax, eax
    jnz   .ignoreKey

    movzx eax, byte [currentTurn]
    mov   byte [board + ebx], al

    call  checkWin
    cmp   eax, -1
    je    .flipTurn

    mov   byte [gameOver], 1

    ; cache the winning line endpoints now, once, into named memory
    ; so the paint handler never has to compute anything
    movzx ecx, byte [winLine]
    cmp   ecx, 0xFF
    je    .skipWinPts

    mov   eax, ecx
    mov   ecx, 3
    mul   ecx                   ; eax = winLine * 3
    lea   esi, [winTable]
    add   esi, eax              ; esi → trio

    movzx ecx, byte [esi+0]     ; first cell of the winning trio
    mov   [cc_arg], ecx
    call  cellLookup
    mov   eax, [cc_cx]
    mov   [winPt0x], eax
    mov   eax, [cc_cy]
    mov   [winPt0y], eax

    movzx ecx, byte [esi+2]     ; last cell of the winning trio
    mov   [cc_arg], ecx
    call  cellLookup
    mov   eax, [cc_cx]
    mov   [winPt1x], eax
    mov   eax, [cc_cy]
    mov   [winPt1y], eax

.skipWinPts:
    movzx ecx, byte [winner]
    cmp   ecx, PLAYER_X
    jne   .notXWin
    inc   dword [userData + 0]
.notXWin:
    cmp   ecx, PLAYER_O
    jne   .doRedraw
    inc   dword [userData + 4]
    jmp   .doRedraw

.flipTurn:
    movzx eax, byte [currentTurn]
    xor   eax, 3
    mov   byte [currentTurn], al

.doRedraw:
    push 0
    push 0
    push dword [ebp+8]
    call _InvalidateRect@12

.ignoreKey:
    xor  eax, eax
    jmp  .leave


; ====== PAINT HANDLER =======================================
.onPaint:
    push ps
    push dword [ebp+8]
    call _BeginPaint@8
    mov  [ebp-4], eax
    mov  esi, eax               ; esi = hDC throughout

    ; --- background -----------------------------------------
    push COL_BG
    call _CreateSolidBrush@4
    mov  edi, eax

    push clientRect
    push dword [ebp+8]
    call _GetClientRect@8

    push edi
    push clientRect
    push esi
    call _FillRect@12

    push edi
    call _DeleteObject@4

    ; --- grid lines -----------------------------------------
    push LINE_W
    push 0
    push COL_GRID
    call _CreatePen@12
    mov  edi, eax

    push edi
    push esi
    call _SelectObject@8
    mov  ebx, eax               ; save old pen

    ; --- VERTICAL LINE 1 (Left Col Boundary) ---
    push 0
    push (MARGIN + CELL*3)     ; Y bottom
    push (MARGIN + CELL)       ; X left-column
    push esi
    call _MoveToEx@16
    
    push MARGIN                 ; Y top
    push (MARGIN + CELL)       ; X left-column
    push esi
    call _LineTo@12

    ; --- VERTICAL LINE 2 (Right Col Boundary) ---
    push 0
    push (MARGIN + CELL*3)     ; Y bottom
    push (MARGIN + CELL*2)     ; X right-column
    push esi
    call _MoveToEx@16
    
    push MARGIN                 ; Y top
    push (MARGIN + CELL*2)     ; X right-column
    push esi
    call _LineTo@12

    ; --- HORIZONTAL LINE 1 (Top Row Boundary) ---
    push 0
    push (MARGIN + CELL)       ; Y top-row
    push (MARGIN + CELL*3)     ; X right-edge
    push esi
    call _MoveToEx@16
    
    push (MARGIN + CELL)       ; Y top-row
    push MARGIN                 ; X left-edge
    push esi
    call _LineTo@12

    ; --- HORIZONTAL LINE 2 (Bottom Row Boundary) ---
    push 0
    push (MARGIN + CELL*2)     ; Y bottom-row
    push (MARGIN + CELL*3)     ; X right-edge
    push esi
    call _MoveToEx@16
    
    push (MARGIN + CELL*2)     ; Y bottom-row
    push MARGIN                 ; X left-edge
    push esi
    call _LineTo@12

    ; --- cleanup pen ---
    push ebx
    push esi
    call _SelectObject@8
    push edi
    call _DeleteObject@4

    ; --- pieces ---------------------------------------------
    ; Walk cells 0-8. Cell counter lives on the stack so it
    ; survives all the register traffic inside each draw block.
    push 0                      ; cell counter

.pieceLoop:
    mov  ecx, [esp]
    cmp  ecx, 9
    jge  .pieceLoopDone

    movzx eax, byte [board + ecx]
    test  eax, eax
    jz    .pieceCellNext

    ; look up this cell's pixel center into named slots
    mov  [cc_arg], ecx
    push eax                    ; save piece type across cellLookup
    call cellLookup             ; writes cc_cx, cc_cy — no register side effects
    pop  eax                    ; restore piece type

    mov  esi, [ebp-4]           ; reload hDC (cellLookup is clean but be safe)

    cmp  al, PLAYER_X
    je   .doPieceX

    ; --- draw O ---------------------------------------------
    push 4
    push 0
    push COL_O
    call _CreatePen@12
    mov  edi, eax

    push edi
    push esi
    call _SelectObject@8
    push eax                    ; old pen

    push 5                      ; NULL_BRUSH — interior stays clear
    call _GetStockObject@4
    push eax
    push esi
    call _SelectObject@8
    push eax                    ; old brush

    ; read coords from named slots — no register math needed
    mov  eax, [cc_cy]
    add  eax, HALF
    push eax                    ; bottom
    mov  eax, [cc_cx]
    add  eax, HALF
    push eax                    ; right
    mov  eax, [cc_cy]
    sub  eax, HALF
    push eax                    ; top
    mov  eax, [cc_cx]
    sub  eax, HALF
    push eax                    ; left
    push esi
    call _Ellipse@20

    pop  eax                    ; old brush
    push eax
    push esi
    call _SelectObject@8

    pop  eax                    ; old pen
    push eax
    push esi
    call _SelectObject@8

    push edi
    call _DeleteObject@4

    jmp  .pieceCellNext

    ; --- draw X ---------------------------------------------
.doPieceX:
    push 4
    push 0
    push COL_X
    call _CreatePen@12
    mov  edi, eax

    push edi
    push esi
    call _SelectObject@8
    push eax                    ; old pen

    ; top-left to bottom-right
    mov  eax, [cc_cx]
    sub  eax, HALF
    mov  ebx, [cc_cy]
    sub  ebx, HALF
    push 0
    push ebx
    push eax
    push esi
    call _MoveToEx@16

    mov  eax, [cc_cx]
    add  eax, HALF
    mov  ebx, [cc_cy]
    add  ebx, HALF
    push ebx
    push eax
    push esi
    call _LineTo@12

    ; top-right to bottom-left
    mov  eax, [cc_cx]
    add  eax, HALF
    mov  ebx, [cc_cy]
    sub  ebx, HALF
    push 0
    push ebx
    push eax
    push esi
    call _MoveToEx@16

    mov  eax, [cc_cx]
    sub  eax, HALF
    mov  ebx, [cc_cy]
    add  ebx, HALF
    push ebx
    push eax
    push esi
    call _LineTo@12

    pop  eax
    push eax
    push esi
    call _SelectObject@8

    push edi
    call _DeleteObject@4

.pieceCellNext:
    inc  dword [esp]
    mov  esi, [ebp-4]
    jmp  .pieceLoop

.pieceLoopDone:
    add  esp, 4
    mov  esi, [ebp-4]

    ; --- winning line ---------------------------------------
    ; winPt0x/y and winPt1x/y were already written by the key
    ; handler the moment the game ended just read and draw.
    cmp  byte [gameOver], 1
    jne  .doStatusBar
    movzx eax, byte [winLine]
    cmp   eax, 0xFF
    je    .doStatusBar          ; it was a draw, no line

    push 8
    push 0
    push COL_WIN
    call _CreatePen@12
    mov  edi, eax

    push edi
    push esi
    call _SelectObject@8
    push eax                    ; old pen

    push 0
    push dword [winPt0y]
    push dword [winPt0x]
    push esi
    call _MoveToEx@16

    push dword [winPt1y]
    push dword [winPt1x]
    push esi
    call _LineTo@12

    pop  eax
    push eax
    push esi
    call _SelectObject@8
    push edi
    call _DeleteObject@4

    ; --- status text ----------------------------------------
.doStatusBar:
    mov  esi, [ebp-4]

    push 1                      ; TRANSPARENT — don't paint behind the text
    push esi
    call _SetBkMode@8

    push COL_TEXT
    push esi
    call _SetTextColor@8

    cmp  byte [gameOver], 1
    je   .pickEndMsg
    cmp  byte [currentTurn], PLAYER_X
    je   .showXTurn
    mov  ebx, msgOTurn
    jmp  .gotMsg
.showXTurn:
    mov  ebx, msgXTurn
    jmp  .gotMsg
.pickEndMsg:
    movzx eax, byte [winner]
    cmp   eax, PLAYER_X
    je    .showXWins
    cmp   eax, PLAYER_O
    je    .showOWins
    mov   ebx, msgDraw
    jmp   .gotMsg
.showXWins:
    mov   ebx, msgXWins
    jmp   .gotMsg
.showOWins:
    mov   ebx, msgOWins

.gotMsg:
    push 0      ; pitch & family
    push 0      ; quality
    push 0      ; clip precision
    push 0      ; output precision
    push 0      ; charset
    push 0      ; strikeout
    push 0      ; underline
    push 0      ; italic
    push 700    ; FW_BOLD
    push 0      ; orientation
    push 0      ; escapement
    push 0      ; angle
    push 0      ; width (auto)
    push 22     ; height
    call _CreateFontA@56
    mov  edi, eax

    push edi
    push esi
    call _SelectObject@8
    push eax                    ; old font

    mov  dword [textRect+0],  0
    mov  dword [textRect+4],  (MARGIN + CELL*3 + 10)
    mov  dword [textRect+8],  WIN_W
    mov  dword [textRect+12], WIN_H

    push 0x25                   ; DT_CENTER|DT_VCENTER|DT_SINGLELINE
    push textRect
    push -1
    push ebx
    push esi
    call _DrawTextA@20

    pop  eax
    push eax
    push esi
    call _SelectObject@8
    push edi
    call _DeleteObject@4

    push ps
    push dword [ebp+8]
    call _EndPaint@8

    xor  eax, eax

.leave:
    pop  edi
    pop  esi
    pop  ebx
    add  esp, 4
    pop  ebp
    ret  16