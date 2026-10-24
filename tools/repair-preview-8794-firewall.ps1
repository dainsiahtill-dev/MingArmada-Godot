param([Parameter(Mandatory=$true)][string]$ReceiptPath)

$ErrorActionPreference = 'Stop'
$receiptDirectory = Split-Path -Parent $ReceiptPath
try {
    & (Join-Path $PSScriptRoot 'enable-preview-8794-lan.ps1') | Out-Null
    $task = Get-ScheduledTask -TaskName 'MingArmada Preview 8794'
    $program = $task.Actions.Execute
    $blocks = @(Get-NetFirewallApplicationFilter -Program $program | Get-NetFirewallRule | Where-Object {
        $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Block' -and $_.Profile -eq 'Public' -and $_.Name -like 'TCP Query User*'
    })
    $changed = @()
    foreach ($rule in $blocks) {
        $filter = $rule | Get-NetFirewallPortFilter
        if ($filter.Protocol -ne 'TCP') { throw 'Unexpected protocol in the Python TCP block rule.' }
        $beforePorts = @($filter.LocalPort)
        if (($beforePorts -join ',') -eq 'Any') {
            $backupPath = Join-Path $receiptDirectory 'firewall-python-tcp-block-before.json'
            if (-not (Test-Path -LiteralPath $backupPath)) {
                [pscustomobject]@{ Name=$rule.Name; Program=$program; Profile=[string]$rule.Profile; LocalPort=$beforePorts; CapturedAt=(Get-Date).ToString('o') } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $backupPath -Encoding UTF8
            }
            # Preserve the explicit block for every other TCP port.
            $filter | Set-NetFirewallPortFilter -LocalPort @('1-8793', '8795-65535') | Out-Null
            $changed += $rule.Name
        }
        $after = (Get-NetFirewallRule -Name $rule.Name | Get-NetFirewallPortFilter).LocalPort
        if ((@($after) -join ',') -ne '1-8793,8795-65535') {
            throw 'Unexpected port scope; refusing to declare the block repaired.'
        }
    }
    $receipt = [pscustomobject]@{ Status='verified'; ChangedRules=$changed; Program=$program; AllowedPort=8794; PreservedBlockPorts=@('1-8793','8795-65535'); UdpRulesChanged=$false; VerifiedAt=(Get-Date).ToString('o') }
    $receipt | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $ReceiptPath -Encoding UTF8
} catch {
    [pscustomobject]@{ Status='error'; Message=$_.Exception.Message; At=(Get-Date).ToString('o') } | ConvertTo-Json -Compress | Set-Content -LiteralPath $ReceiptPath -Encoding UTF8
    throw
}
