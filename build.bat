@echo off
REM =====================================================
REM  build.bat  –  assemble and link tictactoe.asm
REM  Requires NASM and GoLink (or MinGW gcc) in PATH
REM =====================================================

echo [1/2] Assembling with NASM...
nasm -f win32 tictactoe.asm -o tictactoe.obj
if errorlevel 1 (
    echo NASM failed. Make sure nasm.exe is in your PATH.
    pause
    exit /b 1
)

echo [2/2] Linking...

REM ---- Option A: GoLink (recommended, smallest exe) ----
where golink >nul 2>&1
if not errorlevel 1 (
    golink /entry _WinMain@16 tictactoe.obj kernel32.dll user32.dll gdi32.dll
    if not errorlevel 1 (
        echo.
        echo  SUCCESS: tictactoe.exe built with GoLink
        echo  Run:     tictactoe.exe
        pause
        exit /b 0
    )
)

REM ---- Option B: MinGW gcc (if GoLink not found) ------
where gcc >nul 2>&1
if not errorlevel 1 (
    gcc -m32 tictactoe.obj -o tictactoe.exe -luser32 -lgdi32 -lkernel32 -mwindows
    if not errorlevel 1 (
        echo.
        echo  SUCCESS: tictactoe.exe built with gcc
        echo  Run:     tictactoe.exe
        pause
        exit /b 0
    )
)

echo.
echo  ERROR: Neither GoLink nor gcc (MinGW) found.
echo  See README.md for install instructions.
pause
exit /b 1
