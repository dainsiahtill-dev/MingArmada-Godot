param([switch]$VerifyOnly, [switch]$PassThru, [string]$CapturePath)

$ErrorActionPreference = 'Stop'
$releaseDirectory = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'MingArmada.exe')) {
    $PSScriptRoot
} else {
    [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../build/windows'))
}
$portableReceiptPath = Join-Path $releaseDirectory 'windows-export.json'
$exportReceiptPath = if (Test-Path -LiteralPath $portableReceiptPath -PathType Leaf) { $portableReceiptPath } else { Join-Path (Split-Path $releaseDirectory -Parent) 'windows-export.json' }
$executablePath = Join-Path $releaseDirectory 'MingArmada.exe'
$packPath = Join-Path $releaseDirectory 'MingArmada.pck'

foreach ($requiredPath in @($executablePath, $packPath, $exportReceiptPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Missing current release file: $requiredPath. Run rtk proxy node tools/export-windows.mjs first."
    }
}
$exportReceipt = Get-Content -LiteralPath $exportReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
$verifiedFiles = @()
foreach ($requiredPath in @($executablePath, $packPath)) {
    $fileName = Split-Path $requiredPath -Leaf
    $expected = @($exportReceipt.files | Where-Object { $_.name -eq $fileName })
    if ($expected.Count -ne 1) { throw "Current export receipt does not cover $fileName; re-export the release." }
    $hashStream = [System.IO.File]::OpenRead($requiredPath)
    $hashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
    try { $actualHash = [System.BitConverter]::ToString($hashAlgorithm.ComputeHash($hashStream)).Replace('-', '').ToLowerInvariant() }
    finally { $hashStream.Dispose(); $hashAlgorithm.Dispose() }
    if ($actualHash -ne $expected[0].sha256) { throw "Release file differs from its export receipt: $fileName" }
    $verifiedFiles += [pscustomobject]@{ name = $fileName; sha256 = $actualHash }
}
if ($VerifyOnly) {
    [pscustomobject]@{
        status = 'VERIFIED'
        exportedAt = $exportReceipt.exportedAt
        executable = $executablePath
        scene = 'res://game/scenes/reference_island_water/reference_island_water.tscn'
        route = 'actual main-menu water-study entry'
        files = $verifiedFiles
    } | ConvertTo-Json -Depth 5
    exit 0
}

# The game is the interactive window requested by the user; no editor/browser is opened.
$launchArguments = @('--', '--water-study')
$launchOptions = @{ FilePath = $executablePath; ArgumentList = $launchArguments; WorkingDirectory = $releaseDirectory; WindowStyle = 'Normal'; PassThru = $true }
if ($CapturePath) {
    $absoluteCapturePath = [System.IO.Path]::GetFullPath($CapturePath)
    [System.IO.Directory]::CreateDirectory((Split-Path $absoluteCapturePath -Parent)) | Out-Null
    $launchOptions.ArgumentList += ('"--water-study-capture=' + $absoluteCapturePath + '"')
    $launchOptions.RedirectStandardOutput = $absoluteCapturePath + '.stdout.log'
    $launchOptions.RedirectStandardError = $absoluteCapturePath + '.stderr.log'
}
$previewProcess = Start-Process @launchOptions
if ($PassThru) {
    [pscustomobject]@{ processId = $previewProcess.Id; executable = $executablePath; arguments = $launchOptions.ArgumentList; route = 'water-study'; exportedAt = $exportReceipt.exportedAt } | ConvertTo-Json -Depth 5
}
