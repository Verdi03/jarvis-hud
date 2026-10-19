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
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) { continue }
    $parts = $line -split "=", 2
    if ($parts.Count -ne 2) { continue }
    $key = $parts[0].Trim()
    $value = $parts[1].Trim().Trim([char]34).Trim([char]39)
    switch ($key) {
      "OPENAI_API_KEY" { if ($value) { $OpenAiKey = $value } }
      "N8N_MCP_URL" { if ($value) { $N8nMcpUrl = $value } }
      "N8N_MCP_AUTH_HEADER" { if ($value) { $N8nAuthHeader = $value } }
      "N8N_MCP_AUTH_VALUE" { if ($value) { $N8nAuthValue = $value } }
    }
  }
}

$Listener = [System.Net.HttpListener]::new()
$Listener.Prefixes.Add("http://127.0.0.1:$Port/")
try { $Listener.Start() } catch {
  Write-Host "Le port 4173 est deja utilise. Ferme l'autre serveur JARVIS." -ForegroundColor Yellow
  Read-Host "Entree pour fermer"
  exit 1
}
Write-Host "JARVIS disponible sur http://127.0.0.1:$Port/"
Write-Host "Cle OpenAI detectee : $([bool]$OpenAiKey). La cle permanente reste cote serveur."
Write-Host "Ctrl+C arrete JARVIS."

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
  $payload = @{ jsonrpc = "2.0"; method = $Method }
  if ($Method -ne "notifications/initialized") { $payload.id = $Id }
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
  if ([string]$InputObject.name -ne "jarvis_test_mcp_readonly") { throw "Outil non autorise." }
  if ([string]$InputObject.arguments.test_code -ne "JARVIS-MCP-TEST-20261019") { throw "Code de test invalide." }
  $query = 'subject:"JARVIS_FAUX_TEST_NE_DOIT_PAS_EXISTer_20261019"'
  $init = Invoke-McpRpc "initialize" @{ protocolVersion = "2025-03-26"; capabilities = @{}; clientInfo = @{ name = "jarvis-local-hud"; version = "0.1.0" } } $null 1
  if ($init.payload.error) { throw "Initialisation MCP refusee." }
  $sid = $init.sessionId
  $null = Invoke-McpRpc "notifications/initialized" $null $sid 0
  $call = Invoke-McpRpc "tools/call" @{ name = "jarvis_readonly_jarvis_search_gmail"; arguments = @{ query = $query } } $sid 2
  if ($call.payload.error -or $call.payload.result.isError) { throw "Appel MCP fictif refuse." }
  # Return only a fixed receipt; never pass Gmail content to the Realtime model.
  return @{ status = "completed"; test = "fictitious_read_only_call"; result_content_forwarded = $false }
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
        Send-Json $Response @{error="Origine refusee"} 403
        continue
      }
      if (-not $OpenAiKey) { Send-Json $Response @{error="OPENAI_API_KEY manquante dans .env"} 503; continue }
      $sessionConfig = @{
        type = "realtime"
        model = "gpt-realtime"
        instructions = "Tu es JARVIS, assistant personnel vocal de Verdi. Reponds en francais oral naturel et brievement. N'utilise aucun outil et ne pretends pas avoir lu un compte ou effectue une action. Demande une validation explicite avant tout envoi, modification, suppression, publication ou depense."
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
        $apiStatus = 0
        $apiErrorCode = ""
        $apiErrorMessage = ""
        try {
          $apiResponse = $_.Exception.Response
          if ($apiResponse) {
            $apiStatus = [int]$apiResponse.StatusCode
            $apiStream = $apiResponse.GetResponseStream()
            if ($apiStream) {
              $apiReader = [System.IO.StreamReader]::new($apiStream)
              $apiRaw = $apiReader.ReadToEnd()
              $apiReader.Close()
              if ($apiRaw) {
                $apiError = $apiRaw | ConvertFrom-Json
                if ($apiError.error) {
                  $apiErrorCode = [string]$apiError.error.code
                  $apiErrorMessage = [string]$apiError.error.message
                }
              }
            }
          }
        } catch {}
        if ($apiErrorMessage.Length -gt 300) { $apiErrorMessage = $apiErrorMessage.Substring(0, 300) }
        $apiErrorMessage = $apiErrorMessage -replace 'sk-[A-Za-z0-9_-]+', '[cle masquee]'
        $diagnostic = "HTTP $apiStatus"
        if ($apiErrorCode) { $diagnostic += " / $apiErrorCode" }
        if ($apiErrorMessage) { $diagnostic += "  -  $apiErrorMessage" }
        Write-Warning "OpenAI Realtime refusee : $diagnostic"
        Send-Json $Response @{error="OpenAI Realtime refusee : $diagnostic"} 502
      }
      continue
    }
    if ($Request.HttpMethod -eq "POST" -and $Path -eq "/api/mcp/tool") {
      $origin = $Request.Headers["Origin"]
      if ($origin -ne "http://127.0.0.1:$Port") { Send-Json $Response @{error="Origine refusee"} 403; continue }
      if (-not $N8nAuthValue) { Send-Json $Response @{error="Configure le credential MCP local dans .env."} 503; continue }
      try {
        $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
        $inputObject = $reader.ReadToEnd() | ConvertFrom-Json
        $result = Invoke-JarvisMcpTool $inputObject
        Send-Json $Response @{ok=$true; result=$result}
      } catch {
        Send-Json $Response @{ok=$false; error="Appel de l'outil en lecture seule echoue."} 502
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
