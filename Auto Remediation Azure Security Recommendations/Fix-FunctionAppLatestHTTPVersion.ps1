<#
.SYNOPSIS
    Auto-fix: "Function apps should use latest 'HTTP Version'"
    Sets Function Apps to use HTTP Version 2.0 (latest recommended).  Add to Monthly Automation

    # Dry run first
.\Fix-FunctionAppLatestHTTPVersion.ps1 -WhatIf

# Actual remediation
.\Fix-FunctionAppLatestHTTPVersion.ps1
#>

param(
    [switch]$WhatIf
)

Write-Host "=== Setting Function Apps to Latest HTTP Version (2.0) ===" -ForegroundColor Cyan

$functionApps = Get-AzFunctionApp

$updatedCount = 0

foreach ($app in $functionApps) {
    $rg = $app.ResourceGroupName
    $name = $app.Name

    try {
        # Get current configuration
        $config = Get-AzWebApp -ResourceGroupName $rg -Name $name -ErrorAction SilentlyContinue

        if ($config -and $config.Http20Enabled -ne $true) {
            Write-Host "Function App '$name' - Setting HTTP Version to 2.0" -ForegroundColor Yellow

            if (-not $WhatIf) {
                Set-AzWebApp -ResourceGroupName $rg `
                             -Name $name `
                             -Http20Enabled $true `
                             -ErrorAction Stop

                Write-Host "  ✓ HTTP 2.0 enabled for '$name'" -ForegroundColor Green
                $updatedCount++
            } else {
                Write-Host "  [WhatIf] Would enable HTTP 2.0 for '$name'" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "  ✗ Failed to update Function App '$name': $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nFunction App HTTP Version remediation completed. Updated $updatedCount Function Apps." -ForegroundColor Green