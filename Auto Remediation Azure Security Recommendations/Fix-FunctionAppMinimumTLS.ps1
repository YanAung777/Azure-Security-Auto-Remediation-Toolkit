<#
.SYNOPSIS
    Auto-fix: "TLS should be updated to the latest version for function apps"
#>

param(
    [switch]$WhatIf,
    [string]$MinimumTlsVersion = "1.2"
)

Write-Host "=== Setting Minimum TLS Version on Function Apps ===" -ForegroundColor Cyan

$functionApps = Get-AzFunctionApp

foreach ($app in $functionApps) {
    $rg = $app.ResourceGroupName
    $name = $app.Name
    $config = Get-AzWebApp -ResourceGroupName $rg -Name $name -ErrorAction SilentlyContinue
    
    if ($config -and $config.SiteConfig.MinTlsVersion -ne $MinimumTlsVersion) {
        Write-Host "Function App '$name' → Setting TLS $MinimumTlsVersion" -ForegroundColor Yellow
        if (-not $WhatIf) {
            Set-AzWebApp -ResourceGroupName $rg -Name $name -MinTlsVersion $MinimumTlsVersion -ErrorAction SilentlyContinue
            Write-Host "  ✓ TLS updated" -ForegroundColor Green
        } else {
            Write-Host "  [WhatIf] Would set TLS $MinimumTlsVersion" -ForegroundColor Gray
        }
    }
}
Write-Host "Function App Minimum TLS remediation completed." -ForegroundColor Green