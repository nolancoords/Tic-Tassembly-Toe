# Tic-Tac-Toe — x86 NASM Assembly (Win32)

A fully graphical Tic-Tac-Toe game written in pure x86 assembly using
the Win32 GDI API.

The original code, called tictactoe_lc3.asm, is the original school project meant to be run in pensim. 

The main code should be assembled if you have the full file. Continue reader to learn how to run.

---

## What you need to install

### 1. NASM  (assembler)
Download the Windows installer from:  
https://www.nasm.us/pub/nasm/releasebuilds/?C=M;O=D  
Pick the latest `nasm-X.XX.XX-installer-x64.exe`.  
During install, tick **"Add to PATH"**.

### 2. Linker — pick ONE of the following:

#### Option A: GoLink  ← recommended (tiny, made for Win32 asm)
Download a single `.exe` from:  
https://www.godevtool.com/  
Drop `golink.exe` anywhere in your PATH  
(e.g. `C:\Windows\System32` or next to `tictactoe.asm`).

#### Option B: MinGW-w64  (if you already have it / prefer it)
Install via https://winlibs.com or `winget install MinGW.MinGW`  
Make sure the `bin` folder is on your PATH and that you have the
32-bit multilib (`-m32`) support installed.

---

## How to build

Double-click `build.bat` **or** open a Command Prompt in this folder:

```
build.bat
```

The script tries GoLink first, then gcc.  
On success you get **`tictactoe.exe`** in the same folder.

---

## How to play

Run `tictactoe.exe` — a 540×580 window appears.

| Key | Action |
|-----|--------|
| `1`–`9` | Place piece in that grid cell (numpad layout shown below) |
| `SPACE` | Restart after game ends |

**Cell layout** (matches the number keys):
```
 1 | 2 | 3
---+---+---
 4 | 5 | 6
---+---+---
 7 | 8 | 9
```

- **X always goes first** (drawn in red/orange).
- **O** is drawn in blue.
- When three in a row is achieved a **thick green line** is drawn through the winning cells.
- At game end the status bar shows the result and prompts **Press SPACE to play again**.

---

## User data / customization

Four DWORDs at the top of the `.bss` section are reserved for you:

```asm
userData    resd 8
; [0] = X win count  (auto-incremented)
; [1] = O win count  (auto-incremented)
; [2..7] = free — add your own features here
```

To access them in the code:
```asm
mov eax, [userData + 0*4]   ; X wins
mov eax, [userData + 2*4]   ; your custom slot 0
```

---

## File layout

```
tictactoe.asm   main source (fully commented)
build.bat       one-click build script
README.md       this file
```

