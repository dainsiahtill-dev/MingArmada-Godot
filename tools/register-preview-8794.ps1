$ErrorActionPreference = 'Stop'
$previewRoot = Split-Path -Parent $PSScriptRoot
$previewRunner = Join-Path $PSScriptRoot 'run-preview-8794.py'
$pythonWindowless = (Get-Command pythonw.exe -ErrorAction Stop).Source
$previewUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$previewTaskName = 'MingArmada Preview 8794'

if (Get-ScheduledTask -TaskName $previewTaskName -ErrorAction SilentlyContinue) {
    throw 'Task already exists; inspect it before changing its configuration.'
}
if (Get-NetTCPConnection -State Listen -LocalPort 8794 -ErrorAction SilentlyContinue) {
    throw 'Port 8794 is already in use; inspect its owner before starting a second server.'
}

$previewAction = New-ScheduledTaskAction -Execute $pythonWindowless -Argument ('"' + $previewRunner + '"') -WorkingDirectory $previewRoot
$previewLogon = New-ScheduledTaskTrigger -AtLogOn -User $previewUser
$previewRetry = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
$previewPrincipal = New-ScheduledTaskPrincipal -UserId $previewUser -LogonType Interactive -RunLevel Limited
$previewSettings = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $previewTaskName -Action $previewAction -Trigger @($previewLogon, $previewRetry) -Principal $previewPrincipal -Settings $previewSettings -Description 'Keep the MingArmada story reader on port 8794 available locally, on the LAN and through frp. Publish only the reader and its assets.' | Out-Null
Start-ScheduledTask -TaskName $previewTaskName
Get-ScheduledTask -TaskName $previewTaskName | Select-Object TaskName, State | ConvertTo-Json -Compress
