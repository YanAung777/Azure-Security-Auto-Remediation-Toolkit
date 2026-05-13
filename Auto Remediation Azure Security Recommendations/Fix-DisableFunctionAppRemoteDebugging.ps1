<#
.SYNOPSIS
    Auto-fix: "Remote debugging should be turned off for Function App"
    Disables remote debugging on all Azure Function Apps.

    # Dry run first
.\Fix-DisableFunctionAppRemoteDebugging.ps1 -WhatIf

# Actual remediation
.\Fix-DisableFunctionAppRemoteDebugging.ps1
#>

param(
    [switch]$WhatIf
)

Write-Host "=== Disabling Remote Debugging on Azure Function Apps ===" -ForegroundColor Cyan

$functionApps = Get-AzFunctionApp

$fixedCount = 0

foreach ($app in $functionApps) {
    $rg = $app.ResourceGroupName
    $name = $app.Name

    try {
        # Check current remote debugging setting
        $config = Get-AzWebApp -ResourceGroupName $rg -Name $name -ErrorAction SilentlyContinue

        if ($config -and $config.SiteConfig.RemoteDebuggingEnabled -eq $true) {
            Write-Host "Function App '$name' has remote debugging enabled. Disabling..." -ForegroundColor Yellow

            if (-not $WhatIf) {
                Set-AzWebApp -ResourceGroupName $rg `
                             -Name $name `
                             -RemoteDebuggingEnabled $false `
                             -ErrorAction Stop

                Write-Host "  ✓ Remote debugging disabled for '$name'" -ForegroundColor Green
                $fixedCount++
            } else {
                Write-Host "  [WhatIf] Would disable remote debugging for '$name'" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "  ✗ Failed to update Function App '$name': $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nRemote Debugging remediation completed. Updated $fixedCount Function Apps." -ForegroundColor Green