@echo off
setlocal
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js est necessaire. Installez la version LTS depuis https://nodejs.org puis relancez.
  pause
  exit /b 1
)
if not exist .env (
  copy .env.example .env >nul
  echo Fichier .env cree. Ajoutez votre cle API OpenAI dans ce fichier, puis relancez ce script.
  notepad .env
  pause
  exit /b 0
)
start "JARVIS HUD local" http://127.0.0.1:4175
node server.mjs
pause
