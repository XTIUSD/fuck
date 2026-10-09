@echo off
setlocal
cd /d "%~dp0"
if not exist "model.gguf" (
  echo Missing model.gguf next to this bat.
  exit /b 1
)
if not exist "mmproj.gguf" (
  echo Missing mmproj.gguf next to this bat.
  exit /b 1
)
if not exist "llama-server.exe" (
  echo Missing llama-server.exe next to this bat.
  exit /b 1
)
if not exist "x.exe" (
  echo Missing x.exe next to this bat.
  exit /b 1
)
rem Loopback only. No cloud host is set.
start "" llama-server.exe -m "%~dp0model.gguf" --mmproj "%~dp0mmproj.gguf" --host 127.0.0.1 --port 8080 -c 4096 -ngl 0
timeout /t 8 /nobreak >nul
start "" "%~dp0x.exe"
