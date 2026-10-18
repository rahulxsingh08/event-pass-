@echo off
setlocal
cd /d "%~dp0"

if not exist "node_modules" (
  echo Installing CampusPass dependencies...
  call npm install
  if errorlevel 1 (
    echo Dependency installation failed. Check your internet connection and try again.
    pause
    exit /b 1
  )
)

start "CampusPass Dev Server" /D "%~dp0" cmd /k "npm run dev -- --host 127.0.0.1"
timeout /t 3 /nobreak >nul
start "" "http://127.0.0.1:5173/"
endlocal
