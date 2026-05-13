<#
.SYNOPSIS
    Auto-fix: "Function App should only be accessible over HTTPS"
#>

param([switch]$WhatIf)

Write-Host "=== Enforcing HTTPS Only on Function Apps ===" -ForegroundColor Cyan

$functionApps = Get-AzFunctionApp

foreach ($app in $functionApps) {
    $rg = $app.ResourceGroupName
    $name = $app.Name
    $config = Get-AzWebApp -ResourceGroupName $rg -Name $name -ErrorAction SilentlyContinue
    
    if ($config -and $config.HttpsOnly -ne $true) {
        Write-Host "Function App '$name' - Enforcing HTTPS Only" -ForegroundColor Yellow
        if (-not $WhatIf) {
            Set-AzWebApp -ResourceGroupName $rg -Name $name -HttpsOnly $true -ErrorAction SilentlyContinue
            Write-Host "  ✓ HTTPS Only enabled" -ForegroundColor Green
        } else {
            Write-Host "  [WhatIf] Would enable HTTPS Only" -ForegroundColor Gray
        }
    }
}
Write-Host "Function App HTTPS Only remediation completed." -ForegroundColor Green