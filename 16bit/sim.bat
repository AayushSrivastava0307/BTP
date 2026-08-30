@echo off
REM ===========================================================================
REM  sim.bat -- one-click ModelSim run for the 16-bit LeNet-5
REM
REM    sim.bat            compile + simulate all 900 frames -> result.log
REM    sim.bat 20         same, but only the first 20 frames (fast check)
REM    sim.bat gui        open the ModelSim GUI instead
REM
REM  ModelSim Intel FPGA Starter Edition is not on PATH by default, so this
REM  script points at it directly.  Edit MSIM_BIN if your install moves.
REM ===========================================================================

set "MSIM_BIN=C:\intelFPGA_lite\20.1\modelsim_ase\win32aloem"

if not exist "%MSIM_BIN%\vsim.exe" (
    echo ERROR: ModelSim not found at %MSIM_BIN%
    echo Edit MSIM_BIN at the top of this file to point at your install.
    exit /b 1
)

cd /d "%~dp0"

if not exist "test_900f.yuv" (
    echo test_900f.yuv missing - generating it from test_900.png ...
    python png_to_yuv.py || exit /b 1
)

if /I "%~1"=="gui" (
    "%MSIM_BIN%\vsim.exe" -do run.do
    exit /b 0
)

if "%~1"=="" (
    "%MSIM_BIN%\vsim.exe" -c -l result.log -do run.do
) else (
    "%MSIM_BIN%\vsim.exe" -c -l result.log -do "set NFRAMES %~1; do run.do"
)

echo.
echo ---- simulation finished, transcript in result.log ----
python score.py result.log
