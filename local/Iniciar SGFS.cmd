@echo off
setlocal
where node.exe >nul 2>nul
if errorlevel 1 (
  echo Instale o Node.js 24 e adicione node.exe ao PATH.
  pause
  exit /b 1
)
node.exe "%~dp0iniciar-windows.mjs"
set "sgfs_status=%errorlevel%"
if not "%sgfs_status%"=="0" pause
exit /b %sgfs_status%
