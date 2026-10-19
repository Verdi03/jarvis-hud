@echo off
setlocal
cd /d "%~dp0"
if not exist .env (
  copy .env.example .env >nul
  echo Fichier .env cree. Complete OPENAI_API_KEY et N8N_MCP_AUTH_VALUE puis relance.
  notepad .env
  pause
  exit /b 0
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0serveur-jarvis.ps1"
pause
