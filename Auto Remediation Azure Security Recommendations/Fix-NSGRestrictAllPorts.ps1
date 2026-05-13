<#
.SYNOPSIS
    Auto-fix: "All network ports should be restricted on network security groups associated to your virtual machine"
#>

param([switch]$WhatIf)

Write-Host "=== Adding DenyAllInbound Rule on NSGs Attached to VMs ===" -ForegroundColor Cyan

$vms = Get-AzVM
$fixedCount = 0

foreach ($vm in $vms) {
    $nics = $vm.NetworkProfile.NetworkInterfaces
    foreach ($nicId in $nics.Id) {
        $nic = Get-AzNetworkInterface -ResourceId $nicId
        if (-not $nic.NetworkSecurityGroup) { continue }

        $nsg = Get-AzNetworkSecurityGroup -ResourceId $nic.NetworkSecurityGroup.Id
        $nsgName = $nsg.Name

        $denyRule = $nsg.SecurityRules | Where-Object { $_.Name -like "*DenyAllInbound*" -and $_.Access -eq "Deny" }

        if (-not $denyRule) {
            Write-Host "VM '$($vm.Name)' → Adding DenyAll rule to NSG '$nsgName'" -ForegroundColor Yellow
            if (-not $WhatIf) {
                try {
                    Add-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $nsg `
                        -Name "DenyAllInbound-AutoRemediation" `
                        -Description "Auto-remediation: Deny all inbound" `
                        -Priority 4095 `
                        -Protocol "*" `
                        -SourceAddressPrefix "*" `
                        -SourcePortRange "*" `
                        -DestinationAddressPrefix "*" `
                        -DestinationPortRange "*" `
                        -Access Deny `
                        -Direction Inbound | Out-Null

                    Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg | Out-Null
                    Write-Host "  ✓ DenyAll rule added" -ForegroundColor Green
                    $fixedCount++
                } catch {
                    Write-Host "  ✗ Failed" -ForegroundColor Red
                }
            } else {
                Write-Host "  [WhatIf] Would add DenyAll rule" -ForegroundColor Gray
            }
        }
    }
}
Write-Host "NSG DenyAll remediation completed. Updated $fixedCount NSGs." -ForegroundColor Green