@echo off
setlocal EnableExtensions
title Chacha Capture - Camera List
cd /d "%~dp0"

set "TRACKER_PY=.venv-player\Scripts\python.exe"
if not exist "%TRACKER_PY%" if exist .venv\Scripts\python.exe set "TRACKER_PY=.venv\Scripts\python.exe"
if not exist "%TRACKER_PY%" (
  echo [ERROR] Run install_player_windows.bat first.
  pause
  exit /b 1
)

"%TRACKER_PY%" player_tracker.py --list-cameras
pause
