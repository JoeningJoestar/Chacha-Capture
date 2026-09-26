@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "VENV_DIR=%~dp0.venv-player"
set "VENV_PYTHON=%VENV_DIR%\Scripts\python.exe"

if exist "%VENV_PYTHON%" (
  "%VENV_PYTHON%" -c "import sys, struct; raise SystemExit(0 if sys.version_info[:2] in ((3,10),(3,11),(3,12)) and struct.calcsize('P') * 8 == 64 else 1)" >nul 2>nul
  if not errorlevel 1 goto install_dependencies
  echo [WARN] The existing .venv-player uses an unsupported Python version.
)

set "PYTHON_VERSION="
where py >nul 2>nul
if errorlevel 1 goto try_python_command

py -3.10 -c "import sys, struct; raise SystemExit(0 if struct.calcsize('P') * 8 == 64 else 1)" >nul 2>nul
if not errorlevel 1 set "PYTHON_VERSION=3.10"
if defined PYTHON_VERSION goto create_environment

py -3.11 -c "import sys, struct; raise SystemExit(0 if struct.calcsize('P') * 8 == 64 else 1)" >nul 2>nul
if not errorlevel 1 set "PYTHON_VERSION=3.11"
if defined PYTHON_VERSION goto create_environment

py -3.12 -c "import sys, struct; raise SystemExit(0 if struct.calcsize('P') * 8 == 64 else 1)" >nul 2>nul
if not errorlevel 1 set "PYTHON_VERSION=3.12"
if defined PYTHON_VERSION goto create_environment

:try_python_command
where python >nul 2>nul
if errorlevel 1 goto no_python
python -c "import sys, struct; raise SystemExit(0 if sys.version_info[:2] in ((3,10),(3,11),(3,12)) and struct.calcsize('P') * 8 == 64 else 1)" >nul 2>nul
if errorlevel 1 goto no_python
goto create_environment_system

:no_python
echo [ERROR] Python 3.10, 3.11, or 3.12 was not found.
echo         Install 64-bit Python 3.10 and enable the Python Launcher.
pause
exit /b 1

:create_environment
echo [INFO] Creating the .venv-player environment with Python %PYTHON_VERSION%.
py -%PYTHON_VERSION% -m venv "%VENV_DIR%"
if errorlevel 1 goto environment_failed
goto install_dependencies

:create_environment_system
echo [INFO] Creating the .venv-player environment with the system Python.
python -m venv "%VENV_DIR%"
if errorlevel 1 goto environment_failed

:install_dependencies
if not exist "%VENV_PYTHON%" goto environment_failed
"%VENV_PYTHON%" -m pip install --upgrade pip
if errorlevel 1 goto dependency_failed
"%VENV_PYTHON%" -m pip install -r "%~dp0requirements-player.txt"
if errorlevel 1 goto dependency_failed

echo.
echo Chacha Capture installation complete.
echo Run start_player_tracker.bat to start face and head tracking.
pause
exit /b 0

:environment_failed
echo [ERROR] Failed to create the .venv-player environment.
pause
exit /b 1

:dependency_failed
echo [ERROR] Dependency installation failed. Check the Python version and network.
pause
exit /b 1
