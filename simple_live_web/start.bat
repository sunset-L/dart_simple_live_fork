@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
title Simple Live Web
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-windows.ps1" %*
if errorlevel 1 (
  echo.
  echo 启动失败，请查看上方提示和 README.md。
  echo 如目录不可写，请将完整仓库移到个人可写目录。
  echo 如工具安装或脚本执行被限制，请手动安装 Node.js、完整 Dart SDK 和 Git 后重新打开。
  echo Node.js: https://nodejs.org/en/download
  echo Dart SDK: https://dart.dev/get-dart/archive
  echo Git: https://git-scm.com/download/win
  pause
  exit /b 1
)
endlocal
