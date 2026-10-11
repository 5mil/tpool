@echo off
if exist "%~dp0Thimble.exe" (
  start "" "%~dp0Thimble.exe"
) else (
  start "" "%~dp0windows\Thimble.exe"
)

