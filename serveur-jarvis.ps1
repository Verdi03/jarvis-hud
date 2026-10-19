# JARVIS local Realtime gateway. Windows PowerShell 5.1+, no Node.js or external packages.
# Serves ONLY index.html. It never maps arbitrary paths and never serves .env.
$ErrorActionPreference = "Stop"
$Root = [System.IO.Path]::GetFullPath($PSScriptRoot)
$EnvPath = Join-Path $Root ".env"
$Port = 4173
$OpenAiKey = $env:OPENAI_API_KEY

if (Test-Path -LiteralPath $EnvPath -PathType Leaf) {
  foreach ($line in Get-Content -LiteralPath $EnvPath) {
    if ($line -match '^\s*OPENAI_API_KEY\s*=\s*(.*?)\s*$' -and $Matches[1]) {
      $OpenAiKey = $Matches[1].Trim('"').Trim("'")
    }
  }
}

$Listener = [System.Net.HttpListener]::new()
$Listener.Prefixes.Add("http://127.0.0.1:$Port/")
try { $Listener.Start() } catch {
  Write-Host "Le port 4173 est déjà utilisé. Ferme l'autre serveur JARVIS." -ForegroundColor Yellow
  Read-Host "Entrée pour fermer"
  exit 1
}
Write-Host "JARVIS disponible sur http://127.0.0.1:$Port/"
Write-Host "Clé OpenAI détectée : $([bool]$OpenAiKey). La clé permanente reste côté serveur."
Write-Host "Ctrl+C arrête JARVIS."

function Send-Bytes($Response, [byte[]]$Bytes, [string]$Type, [int]$Status = 200) {
  $Response.StatusCode = $Status
  $Response.ContentType = $Type
  $Response.Headers.Add("X-Content-Type-Options", "nosniff")
  $Response.Headers.Add("Cache-Control", "no-store")
  $Response.ContentLength64 = $Bytes.Length
  $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
  $Response.Close()
}
function Send-Json($Response, $Object, [int]$Status = 200) {
  $json = $Object | ConvertTo-Json -Depth 12 -Compress
  Send-Bytes $Response ([System.Text.Encoding]::UTF8.GetBytes($json)) "application/json; charset=utf-8" $Status
}

while ($Listener.IsListening) {
  $Context = $Listener.GetContext()
  $Request = $Context.Request
  $Response = $Context.Response
  try {
    $Path = $Request.Url.AbsolutePath
    if ($Request.HttpMethod -eq "GET" -and $Path -eq "/api/health") {
      Send-Json $Response @{status="ok"; openai_key_configured=[bool]$OpenAiKey; host="127.0.0.1"}
      continue
    }
    if ($Request.HttpMethod -eq "POST" -and $Path -eq "/api/realtime/session") {
      $origin = $Request.Headers["Origin"]
      if ($origin -and $origin -ne "http://127.0.0.1:$Port") {
        Send-Json $Response @{error="Origine refusée"} 403
        continue
      }
      if (-not $OpenAiKey) { Send-Json $Response @{error="OPENAI_API_KEY manquante dans .env"} 503; continue }
      $sessionConfig = @{
        type = "realtime"
        model = "gpt-realtime"
        instructions = "Tu es JARVIS, assistant personnel vocal de Verdi. Réponds en français oral naturel et brièvement. Ne prétends jamais avoir lu un compte ou effectué une action sans résultat vérifié d'un outil. Demande une approbation explicite avant tout envoi, modification, suppression, publication ou dépense. Aucun outil métier n'est encore activé."
        audio = @{
          input = @{
            transcription = @{model="gpt-4o-mini-transcribe"; language="fr"}
            noise_reduction = @{type="near_field"}
            turn_detection = @{type="semantic_vad"; eagerness="medium"; create_response=$true; interrupt_response=$true}
          }
          output = @{voice="marin"}
        }
      }
      $body = @{
        expires_after = @{anchor="created_at"; seconds=600}
        session = $sessionConfig
      } | ConvertTo-Json -Depth 12
      try {
        $session = Invoke-RestMethod -Uri "https://api.openai.com/v1/realtime/client_secrets" -Method Post -Headers @{Authorization="Bearer $OpenAiKey"} -ContentType "application/json" -Body $body -TimeoutSec 30
        Send-Json $Response @{value=$session.value; expires_at=$session.expires_at}
      } catch {
        Write-Warning "OpenAI Realtime session creation failed."
        Send-Json $Response @{error="Impossible de créer la session Realtime. Vérifie l'accès API et le quota."} 502
      }
      continue
    }
    if ($Request.HttpMethod -in @("GET","HEAD") -and $Path -in @("/","/index.html")) {
      $html = [System.IO.File]::ReadAllBytes((Join-Path $Root "index.html"))
      if ($Request.HttpMethod -eq "HEAD") {
        $Response.StatusCode = 200
        $Response.ContentType = "text/html; charset=utf-8"
        $Response.ContentLength64 = $html.Length
        $Response.Close()
      } else {
        Send-Bytes $Response $html "text/html; charset=utf-8"
      }
      continue
    }
    Send-Json $Response @{error="Introuvable"} 404
  } catch {
    try { Send-Json $Response @{error="Erreur locale JARVIS"} 500 } catch {}
  }
}
