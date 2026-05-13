<#
.SYNOPSIS
    Auto-fix: "FTPS should be required in function apps"
#>

param(
    [switch]$WhatIf,
    [string]$FtpsState = "FtpsOnly"
)

Write-Host "=== Enforcing FTPS on Function Apps ===" -ForegroundColor Cyan

$functionApps = Get-AzFunctionApp

foreach ($app in $functionApps) {
    $rg = $app.ResourceGroupName
    $name = $app.Name
    $config = Get-AzWebApp -ResourceGroupName $rg -Name $name -ErrorAction SilentlyContinue
    
    if ($config -and $config.FtpsState -ne $FtpsState) {
        Write-Host "Function App '$name' - Setting FTPS to $FtpsState" -ForegroundColor Yellow
        if (-not $WhatIf) {
            Set-AzWebApp -ResourceGroupName $rg -Name $name -FtpsState $FtpsState -ErrorAction SilentlyContinue
            Write-Host "  ✓ FTPS enforced" -ForegroundColor Green
        } else {
            Write-Host "  [WhatIf] Would set FTPS to $FtpsState" -ForegroundColor Gray
        }
    }
}
Write-Host "FTPS remediation for Function Apps completed." -ForegroundColor Green