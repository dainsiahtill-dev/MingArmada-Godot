param(
    [ValidateSet('menu','mingqi','career','sail','duel','fleet')][string]$Mode = 'mingqi',
    [switch]$VerifyOnly,
    [switch]$PassThru,
    [string]$CapturePath,
    [string]$ProfileDirectory,
    [string]$WorkingDirectory
)
$ErrorActionPreference = 'Stop'
$releaseDirectory = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'MingArmada.exe')) { $PSScriptRoot } else { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../build/windows')) }
$portableReceipt = Join-Path $releaseDirectory 'windows-export.json'
$receiptPath = if (Test-Path -LiteralPath $portableReceipt -PathType Leaf) { $portableReceipt } else { Join-Path (Split-Path $releaseDirectory -Parent) 'windows-export.json' }
$executablePath = Join-Path $releaseDirectory 'MingArmada.exe'
$packPath = Join-Path $releaseDirectory 'MingArmada.pck'
foreach ($requiredPath in @($executablePath,$packPath,$receiptPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Missing current release file: $requiredPath" }
}
$receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($receipt.schemaVersion -ne 2 -or -not $receipt.gameEntrypoints) { throw 'This release has no verified ordinary gameplay entry support. Export the frozen current sources first.' }
$verifiedFiles = @()
foreach ($requiredPath in @($executablePath,$packPath)) {
    $fileName = Split-Path $requiredPath -Leaf
    $expected = @($receipt.files | Where-Object { $_.name -eq $fileName })
    if ($expected.Count -ne 1) { throw "Export receipt does not cover $fileName" }
    $hashStream = [IO.File]::OpenRead($requiredPath)
    $hashAlgorithm = [Security.Cryptography.SHA256]::Create()
    try { $actualHash = [BitConverter]::ToString($hashAlgorithm.ComputeHash($hashStream)).Replace('-','').ToLowerInvariant() }
    finally { $hashStream.Dispose(); $hashAlgorithm.Dispose() }
    if ($actualHash -ne $expected[0].sha256) { throw "Release hash differs from its current export receipt: $fileName" }
    $verifiedFiles += [pscustomobject]@{ name=$fileName; sha256=$actualHash }
}
if ($Mode -eq 'menu' -and $CapturePath) { throw 'PNG capture needs an explicit gameplay mode.' }
if ($VerifyOnly) {
    [pscustomobject]@{ status='VERIFIED'; mode=$Mode; exportedAt=$receipt.exportedAt; executable=$executablePath; files=$verifiedFiles; route='actual main-menu button and current router'; sourceFiles=$receipt.sourceSha256.Count } | ConvertTo-Json -Depth 5
    exit 0
}
if ($ProfileDirectory) { $profilePath=[IO.Path]::GetFullPath($ProfileDirectory) }
elseif ($CapturePath) { $profilePath=Join-Path (Split-Path $releaseDirectory -Parent) ('release-game-capture-profile/' + [Guid]::NewGuid().ToString('N')) }
else { $profilePath=Join-Path (Split-Path $releaseDirectory -Parent) 'release-player-profile' }
$roamingPath=Join-Path $profilePath 'roaming'
$localPath=Join-Path $profilePath 'local'
[IO.Directory]::CreateDirectory($roamingPath) | Out-Null
[IO.Directory]::CreateDirectory($localPath) | Out-Null
$launchDirectory=if ($WorkingDirectory) { [IO.Path]::GetFullPath($WorkingDirectory) } else { $releaseDirectory }
if (-not (Test-Path -LiteralPath $launchDirectory -PathType Container)) { throw "Working directory does not exist: $launchDirectory" }
$launchArguments=@()
if ($Mode -ne 'menu') { $launchArguments=@('--',('--start-game='+$Mode)) }
$launchOptions=@{ FilePath=$executablePath; WorkingDirectory=$launchDirectory; WindowStyle='Normal'; PassThru=$true }
if ($launchArguments.Count -gt 0) { $launchOptions.ArgumentList=$launchArguments }
if ($CapturePath) {
    $absoluteCapturePath=[IO.Path]::GetFullPath($CapturePath)
    if ([IO.Path]::GetExtension($absoluteCapturePath).ToLowerInvariant() -ne '.png') { throw 'CapturePath must name a PNG file.' }
    [IO.Directory]::CreateDirectory((Split-Path $absoluteCapturePath -Parent)) | Out-Null
    $launchOptions.ArgumentList += ('"--game-capture='+$absoluteCapturePath+'"')
    $launchOptions.RedirectStandardOutput=$absoluteCapturePath+'.stdout.log'
    $launchOptions.RedirectStandardError=$absoluteCapturePath+'.stderr.log'
}
# Isolated child environment preserves the user's existing Godot saves. Normal
# play gets a persistent release-only profile; evidence gets a fresh profile.
$previousRoaming=$env:APPDATA
$previousLocal=$env:LOCALAPPDATA
try {
    $env:APPDATA=$roamingPath; $env:LOCALAPPDATA=$localPath
    $gameProcess=Start-Process @launchOptions
} finally { $env:APPDATA=$previousRoaming; $env:LOCALAPPDATA=$previousLocal }
if ($PassThru) {
    [pscustomobject]@{ processId=$gameProcess.Id; executable=$executablePath; mode=$Mode; arguments=$launchOptions.ArgumentList; profile=$profilePath; workingDirectory=$launchDirectory; exportedAt=$receipt.exportedAt; route='actual bundled main-menu entry'; files=$verifiedFiles } | ConvertTo-Json -Depth 5
}
