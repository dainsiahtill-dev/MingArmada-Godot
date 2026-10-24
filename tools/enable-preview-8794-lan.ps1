param([string]$ReceiptPath)

$ErrorActionPreference = 'Stop'
$ruleName = 'MingArmada-Preview-8794-LAN'
$previewTask = Get-ScheduledTask -TaskName 'MingArmada Preview 8794'
if ($previewTask.Actions.Arguments -notlike '*ming-armada\tools\run-preview-8794.py*') {
    throw 'Unexpected preview task; refusing to change firewall.'
}
$pythonWindowless = $previewTask.Actions.Execute
if (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name $ruleName -DisplayName 'MingArmada Preview 8794 LAN' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8794 -LocalAddress 192.168.10.4 -RemoteAddress 192.168.10.0/24 -Profile Any -Program $pythonWindowless | Out-Null
}
$rule = Get-NetFirewallRule -Name $ruleName
$port = $rule | Get-NetFirewallPortFilter
$address = $rule | Get-NetFirewallAddressFilter
$application = $rule | Get-NetFirewallApplicationFilter
if ($rule.Enabled -ne 'True' -or $rule.Action -ne 'Allow' -or $rule.Direction -ne 'Inbound' -or $rule.Profile -ne 'Any' -or $port.LocalPort -ne '8794' -or $port.Protocol -ne 'TCP' -or $address.LocalAddress -ne '192.168.10.4' -or $address.RemoteAddress -notin @('192.168.10.0/255.255.255.0', '192.168.10.0/24') -or $application.Program -ne $pythonWindowless) {
    throw 'The existing firewall rule differs from the intended LAN scope.'
}
$receipt = [pscustomobject]@{ Name = $rule.Name; Enabled = [string]$rule.Enabled; Profile = [string]$rule.Profile; Direction = [string]$rule.Direction; Action = [string]$rule.Action; LocalPort = $port.LocalPort; LocalAddress = $address.LocalAddress; RemoteAddress = $address.RemoteAddress; Program = $application.Program; VerifiedAt = (Get-Date).ToString('o') }
if ($ReceiptPath) { $receipt | ConvertTo-Json -Compress | Set-Content -LiteralPath $ReceiptPath -Encoding UTF8 }
$receipt | ConvertTo-Json -Compress
