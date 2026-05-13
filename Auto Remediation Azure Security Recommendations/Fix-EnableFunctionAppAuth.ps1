<#
.SYNOPSIS
    Auto-fix: "Authentication should be enabled on Azure Functions"
#>

param([switch]$WhatIf)

Write-Host "=== Enabling Authentication on Azure Function Apps ===" -ForegroundColor Cyan

$functionApps = Get-AzFunctionApp

foreach ($app in $functionApps) {
    $rg = $app.ResourceGroupName
    $name = $app.Name

    try {
        $auth = Get-AzWebAppAuthSettings -ResourceGroupName $rg -Name $name -ErrorAction SilentlyContinue
        if (-not $auth -or -not $auth.Enabled) {
            Write-Host "Function App '$name' - Enabling Authentication" -ForegroundColor Yellow
            if (-not $WhatIf) {
                Set-AzWebAppAuthSettings -ResourceGroupName $rg -Name $name -Enabled $true -DefaultProvider "AzureActiveDirectory" -ErrorAction Stop
                Write-Host "  ✓ Authentication enabled" -ForegroundColor Green
            } else {
                Write-Host "  [WhatIf] Would enable authentication" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "  ✗ Failed on '$name'" -ForegroundColor Red
    }
}
Write-Host "Function App Authentication remediation completed." -ForegroundColor Green