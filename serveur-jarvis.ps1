# JARVIS local Realtime gateway. Windows PowerShell 5.1+, no Node.js or external packages.
# Serves ONLY index.html. It never maps arbitrary paths and never serves .env.
$ErrorActionPreference = "Stop"
$Root = [System.IO.Path]::GetFullPath($PSScriptRoot)
$EnvPath = Join-Path $Root ".env"
$Port = 4173
$OpenAiKey = $env:OPENAI_API_KEY
$N8nMcpUrl = $env:N8N_MCP_URL
$N8nAuthHeader = $env:N8N_MCP_AUTH_HEADER
$N8nAuthValue = $env:N8N_MCP_AUTH_VALUE

if (-not $N8nMcpUrl) { $N8nMcpUrl = "https://verdi-izuba-ipay.app.n8n.cloud/mcp/jarvis-readonly-20261019" }
if (-not $N8nAuthHeader) { $N8nAuthHeader = "Authorization" }

if (Test-Path -LiteralPath $EnvPath -PathType Leaf) {
  foreach ($line in Get-Content -LiteralPath $EnvPath) {
    if ($line -match '^\s*OPENAI_API_KEY\s*=\s*(.*?)\s*
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
function Invoke-McpRpc([string]$Method, $Params, [string]$SessionId = $null, [int]$Id = 1) {
  if (-not $N8nAuthValue) { throw "N8N_MCP_AUTH_VALUE manquant dans .env." }
  $headers = @{ Accept = "application/json, text/event-stream"; "MCP-Protocol-Version" = "2025-03-26" }
  $headers[$N8nAuthHeader] = $N8nAuthValue
  if ($SessionId) { $headers["Mcp-Session-Id"] = $SessionId }
  $payload = @{ jsonrpc = "2.0"; id = $Id; method = $Method }
  if ($null -ne $Params) { $payload.params = $Params }
  $body = $payload | ConvertTo-Json -Depth 20 -Compress
  $response = Invoke-WebRequest -UseBasicParsing -Uri $N8nMcpUrl -Method Post -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 30
  $content = [string]$response.Content
  if ($response.Headers["Content-Type"] -like "*text/event-stream*") {
    $dataLine = ($content -split "`n" | Where-Object { $_ -like "data:*" } | Select-Object -Last 1)
    if ($dataLine) { $content = $dataLine.Substring(5).Trim() }
  }
  $parsed = $null
  if ($content) { $parsed = $content | ConvertFrom-Json }
  return @{ payload = $parsed; sessionId = [string]$response.Headers["Mcp-Session-Id"] }
}
function Invoke-JarvisMcpTool($InputObject) {
  $name = [string]$InputObject.name
  $args = $InputObject.arguments
  $allowed = @("jarvis_readonly_jarvis_search_gmail", "jarvis_readonly_jarvis_list_calendar_events", "jarvis_readonly_jarvis_search_drive")
  if ($name -notin $allowed) { throw "Outil non autorisé." }
  if ($null -eq $args) { $args = @{} }
  if ($name -eq "jarvis_readonly_jarvis_search_gmail" -and (-not $args.query -or $args.query.Length -gt 200)) { throw "Requête Gmail invalide." }
  if ($name -eq "jarvis_readonly_jarvis_search_drive" -and (-not $args.name_query -or $args.name_query.Length -gt 100)) { throw "Recherche Drive invalide." }
  if ($name -eq "jarvis_readonly_jarvis_list_calendar_events") {
    $start = [DateTimeOffset]::Parse([string]$args.start_time)
    $end = [DateTimeOffset]::Parse([string]$args.end_time)
    if ($end -le $start -or ($end - $start).TotalDays -gt 31) { throw "Période Agenda invalide (maximum 31 jours)." }
  }
  $init = Invoke-McpRpc "initialize" @{ protocolVersion = "2025-03-26"; capabilities = @{}; clientInfo = @{ name = "jarvis-local-hud"; version = "0.1.0" } } $null 1
  if ($init.payload.error) { throw "Initialisation MCP refusée." }
  $sid = $init.sessionId
  $null = Invoke-McpRpc "notifications/initialized" $null $sid 0
  $call = Invoke-McpRpc "tools/call" @{ name = $name; arguments = $args } $sid 2
  if ($call.payload.error) { throw "Appel MCP refusé." }
  return $call.payload.result
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
        instructions = "Tu es JARVIS, assistant vocal de Verdi. Réponds en français oral naturel et bref. Tu as trois outils Google strictement en lecture seule. Utilise-les seulement quand la demande nécessite ces données et annonce clairement le résultat retourné. Pour le test fictif demandé, recherche uniquement le sujet JARVIS_FAUX_TEST_NE_DOIT_PAS_EXISTer_20261019. N'envoie, ne modifie et ne supprime rien. N'invente jamais un résultat. Demande une approbation avant toute action d'écriture ou dépense."
        tools = @(
          @{ type = "function"; name = "jarvis_readonly_jarvis_search_gmail"; description = "Recherche en lecture seule dans Gmail. Pour le test fictif, utilise exactement le sujet JARVIS_FAUX_TEST_NE_DOIT_PAS_EXISTer_20261019."; parameters = @{ type = "object"; properties = @{ query = @{ type = "string"; description = "Requête Gmail. Limite serveur : 10 résultats." } }; required = @("query"); additionalProperties = $false } },
          @{ type = "function"; name = "jarvis_readonly_jarvis_list_calendar_events"; description = "Liste en lecture seule les événements Calendar dans la période fournie (31 jours maximum)."; parameters = @{ type = "object"; properties = @{ start_time = @{ type = "string"; description = "Date ISO 8601 de début." }; end_time = @{ type = "string"; description = "Date ISO 8601 de fin, 31 jours maximum." } }; required = @("start_time","end_time"); additionalProperties = $false } },
          @{ type = "function"; name = "jarvis_readonly_jarvis_search_drive"; description = "Recherche en lecture seule des noms de fichiers Drive, sans ouvrir leur contenu."; parameters = @{ type = "object"; properties = @{ name_query = @{ type = "string"; description = "Nom ou fragment du nom du fichier." } }; required = @("name_query"); additionalProperties = $false } }
        )
        tool_choice = "auto"
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
    if ($Request.HttpMethod -eq "POST" -and $Path -eq "/api/mcp/tool") {
      $origin = $Request.Headers["Origin"]
      if ($origin -ne "http://127.0.0.1:$Port") { Send-Json $Response @{error="Origine refusée"} 403; continue }
      if (-not $N8nAuthValue) { Send-Json $Response @{error="Configure le credential MCP local dans .env."} 503; continue }
      try {
        $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
        $inputObject = $reader.ReadToEnd() | ConvertFrom-Json
        $result = Invoke-JarvisMcpTool $inputObject
        Send-Json $Response @{ok=$true; result=$result}
      } catch {
        Send-Json $Response @{ok=$false; error="Appel de l'outil en lecture seule échoué."} 502
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
 -and $Matches[1]) { $OpenAiKey = $Matches[1].Trim('"').Trim("'") }
    if ($line -match '^\s*N8N_MCP_URL\s*=\s*(.*?)\s*
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
 -and $Matches[1]) { $N8nMcpUrl = $Matches[1].Trim('"').Trim("'") }
    if ($line -match '^\s*N8N_MCP_AUTH_HEADER\s*=\s*(.*?)\s*
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
 -and $Matches[1]) { $N8nAuthHeader = $Matches[1].Trim('"').Trim("'") }
    if ($line -match '^\s*N8N_MCP_AUTH_VALUE\s*=\s*(.*?)\s*
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
 -and $Matches[1]) { $N8nAuthValue = $Matches[1].Trim('"').Trim("'") }
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
