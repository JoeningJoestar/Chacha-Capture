@echo off
setlocal EnableExtensions
title Chacha Capture - Player Mode
cd /d "%~dp0"

set "TRACKER_PY=.venv-player\Scripts\python.exe"
if not exist "%TRACKER_PY%" if exist .venv\Scripts\python.exe (
  echo [INFO] .venv-player was not found; using the existing .venv.
  set "TRACKER_PY=.venv\Scripts\python.exe"
)
if not exist "%TRACKER_PY%" (
  echo [ERROR] Run install_player_windows.bat first.
  pause
  exit /b 1
)

echo [INFO] Player mode. Close other camera apps first.
"%TRACKER_PY%" player_tracker.py --preview --width 640 --height 480 --fps 30 --processing-width 480 %*
if errorlevel 1 pause
