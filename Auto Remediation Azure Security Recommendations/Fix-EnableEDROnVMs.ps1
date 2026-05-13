<#
.SYNOPSIS
    Auto-fix: "EDR solution should be installed on Virtual Machines"
#>

param([switch]$WhatIf)

Write-Host "=== Installing Microsoft Defender for Endpoint (EDR) on VMs ===" -ForegroundColor Cyan

$vms = Get-AzVM
$fixedCount = 0

foreach ($vm in $vms) {
    $rg = $vm.ResourceGroupName
    $name = $vm.Name

    $existing = Get-AzVMExtension -ResourceGroupName $rg -VMName $name -Name "MicrosoftDefenderForEndpoint" -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "VM '$name' - Installing EDR" -ForegroundColor Yellow
        if (-not $WhatIf) {
            try {
                Set-AzVMExtension -ResourceGroupName $rg `
                                  -VMName $name `
                                  -Name "MicrosoftDefenderForEndpoint" `
                                  -Publisher "Microsoft.Azure.Security.Monitoring" `
                                  -ExtensionType "MicrosoftDefenderForEndpoint" `
                                  -TypeHandlerVersion "1.0" `
                                  -Settings @{} -ErrorAction Stop | Out-Null
                Write-Host "  ✓ EDR installed" -ForegroundColor Green
                $fixedCount++
            } catch {
                Write-Host "  ✗ Failed" -ForegroundColor Red
            }
        } else {
            Write-Host "  [WhatIf] Would install EDR" -ForegroundColor Gray
        }
    }
}
Write-Host "EDR installation completed on $fixedCount VMs." -ForegroundColor Green