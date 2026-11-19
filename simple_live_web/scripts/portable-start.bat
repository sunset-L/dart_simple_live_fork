@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
title Simple Live Web Portable
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-windows.ps1" -Portable %*
if errorlevel 1 (
  echo.
  echo 启动失败，请查看上方提示及 README.md。
  pause
  exit /b 1
)
endlocal
