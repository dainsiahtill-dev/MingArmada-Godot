$ErrorActionPreference = 'Stop'
$siteDirectory = Split-Path -Parent $PSScriptRoot
$serverScript = Join-Path $PSScriptRoot 'serve.mjs'
$runtimeDirectory = Join-Path $siteDirectory '.runtime'
$serverPort = 4173
$serverNode = (Get-Command node -ErrorAction Stop).Source

if (-not (Test-Path -LiteralPath (Join-Path $siteDirectory 'dist/index.html'))) {
    throw 'Build the gameplay website before starting the LAN server.'
}

$existingListener = Get-NetTCPConnection -LocalPort $serverPort -State Listen -ErrorAction SilentlyContinue
if ($existingListener) {
    $owner = Get-CimInstance Win32_Process -Filter "ProcessId = $($existingListener[0].OwningProcess)"
    if ($owner.CommandLine -and $owner.CommandLine.IndexOf($serverScript, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and $existingListener[0].LocalAddress -eq '0.0.0.0') {
        [pscustomobject]@{ status = 'already-running'; pid = $owner.ProcessId; host = '0.0.0.0'; port = $serverPort } | ConvertTo-Json -Compress
        exit 0
    }
    throw "Port $serverPort is occupied by another process. Existing process was left unchanged."
}

New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null
$serverArguments = '"{0}" --host 0.0.0.0 --port {1}' -f $serverScript, $serverPort
$serverProcess = Start-Process -FilePath $serverNode -ArgumentList $serverArguments -WorkingDirectory $siteDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtimeDirectory 'server.stdout.log') -RedirectStandardError (Join-Path $runtimeDirectory 'server.stderr.log')
$metadata = [ordered]@{ pid = $serverProcess.Id; host = '0.0.0.0'; port = $serverPort; script = $serverScript; startedAtUtc = [DateTime]::UtcNow.ToString('o') }
$metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runtimeDirectory 'server.json') -Encoding UTF8

for ($attempt = 0; $attempt -lt 20; $attempt++) {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$serverPort/" -UseBasicParsing -TimeoutSec 2
        if ($response.StatusCode -eq 200 -and $response.Content.Contains('id="hero-title"')) {
            [pscustomobject]@{ status = 'running'; pid = $serverProcess.Id; host = '0.0.0.0'; port = $serverPort; localUrl = "http://127.0.0.1:$serverPort/" } | ConvertTo-Json -Compress
            exit 0
        }
    } catch {
        if ($serverProcess.HasExited) { throw 'The web server exited. See .runtime/server.stderr.log.' }
    }
    Start-Sleep -Milliseconds 150
}
throw 'Web server readiness timed out; inspect .runtime/server.stderr.log and the listening process.'
