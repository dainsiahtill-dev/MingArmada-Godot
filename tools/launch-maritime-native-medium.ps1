param(
    [string]$Pythonw = 'C:\Python314\pythonw.exe',
    [string]$GodotExe = 'C:\Users\dains\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$helper = Join-Path $PSScriptRoot 'launch-maritime-native-medium.pyw'
foreach ($file in @($Pythonw,$GodotExe,$helper)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing launcher dependency: $file" }
}
function Get-SlotHashes([string]$Directory) {
    $result = [ordered]@{}
    foreach ($name in @('settings.json','saves/mingqi-v2.json','saves/legacy-v1.json')) {
        foreach ($suffix in @('','.backup','.rollback','.staged')) {
            $relative = $name+$suffix
            $file = Join-Path $Directory $relative
            $result[$relative] = if (Test-Path -LiteralPath $file -PathType Leaf) { (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
        }
    }
    return $result
}
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { throw 'No existing Explorer shell; launch not attempted.' }
$runId = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH-mm-ss-fffZ')+'-medium-'+$PID
$output = Join-Path $root ('docs/design/2026-10-26-ming-maritime/evidence/native/'+$runId)
$profile = Join-Path $root ('Temp/ming-maritime-profiles/native/'+$runId)
if ((Test-Path -LiteralPath $output) -or (Test-Path -LiteralPath $profile)) { throw 'Fresh native run directories required.' }
New-Item -ItemType Directory -Path $output,$profile | Out-Null
$original = Join-Path $env:APPDATA 'Godot/app_userdata/MingArmada'
$request = [ordered]@{runId=$runId; root=$root; output=$output; profile=$profile; exe=$GodotExe; pythonw=$Pythonw; shellContext='existing Explorer desktop Document.Application'; originalDirectory=$original; originalSlotsBefore=(Get-SlotHashes $original)}
$requestPath = Join-Path $output 'launch-request.json'
$request | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $requestPath -Encoding UTF8
# The existing desktop shell owns this ordinary open verb. The helper checks its
# actual token is Medium before starting any game; no elevation or policy edit.
$shell = New-Object -ComObject Shell.Application
$windows = $shell.Windows()
$location=$null; $locationRoot=$null; $windowHandle=0
$desktop = $windows.FindWindowSW([ref]$location,[ref]$locationRoot,8,[ref]$windowHandle,1)
if (-not $desktop) { throw 'Existing Explorer desktop dispatch unavailable; launch not attempted.' }
$application = $desktop.Document.Application
if (-not $application) { throw 'Existing Explorer desktop application unavailable; launch not attempted.' }
$application.ShellExecute($Pythonw, ('"'+$helper+'" "'+$requestPath+'"'), $root, 'open', 0)
foreach ($object in @($application,$desktop,$windows,$shell)) { [Runtime.InteropServices.Marshal]::ReleaseComObject($object) | Out-Null }
for ($attempt=0; $attempt -lt 100; $attempt++) {
    $receipt = Join-Path $output 'launch.json'
    $failure = Join-Path $output 'launch-error.json'
    if (Test-Path -LiteralPath $failure) { Get-Content -LiteralPath $failure -Raw; exit 1 }
    if (Test-Path -LiteralPath $receipt) { Get-Content -LiteralPath $receipt -Raw; exit 0 }
    Start-Sleep -Milliseconds 100
}
throw "Explorer launch did not produce a receipt within 10 seconds. Retained request: $requestPath"
