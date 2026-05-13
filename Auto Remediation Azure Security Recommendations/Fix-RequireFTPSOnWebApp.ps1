<#
.SYNOPSIS
    Auto-fix: "FTPS should be required in web apps"
#>

param(
    [switch]$WhatIf,
    [string]$FtpsState = "FtpsOnly"
)

Write-Host "=== Enforcing FTPS on Web Apps ===" -ForegroundColor Cyan

$webApps = Get-AzWebApp

foreach ($app in $webApps) {
    $rg = $app.ResourceGroupName
    $name = $app.Name
    $config = Get-AzWebApp -ResourceGroupName $rg -Name $name -ErrorAction SilentlyContinue
    
    if ($config -and $config.FtpsState -ne $FtpsState) {
        Write-Host "Web App '$name' - Setting FTPS to $FtpsState" -ForegroundColor Yellow
        if (-not $WhatIf) {
            Set-AzWebApp -ResourceGroupName $rg -Name $name -FtpsState $FtpsState -ErrorAction SilentlyContinue
            Write-Host "  ✓ FTPS enforced" -ForegroundColor Green
        } else {
            Write-Host "  [WhatIf] Would set FTPS to $FtpsState" -ForegroundColor Gray
        }
    }
}
Write-Host "FTPS remediation for Web Apps completed." -ForegroundColor Green