<#
.SYNOPSIS
    Auto-fix: Enable Microsoft Defender for SQL across all subscriptions
#>

param([switch]$WhatIf)

Write-Host "=== Enabling Microsoft Defender for SQL (All Subscriptions) ===" -ForegroundColor Cyan

try {
    $subscriptions = Get-AzSubscription -ErrorAction Stop
    Write-Host "Found $($subscriptions.Count) subscription(s)" -ForegroundColor Yellow
} catch {
    Write-Host "  ✗ Failed to retrieve subscriptions" -ForegroundColor Red
    exit 1
}

foreach ($subscription in $subscriptions) {
    Write-Host ""
    Write-Host "Processing subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Cyan
    
    try {
        Set-AzContext -SubscriptionId $subscription.Id -ErrorAction Stop | Out-Null
        
        if (-not $WhatIf) {
            try {
                Set-AzSecurityPricing -Name "SqlServers" -PricingTier "Standard" -ErrorAction Stop
                Set-AzSecurityPricing -Name "OpenSourceRelationalDatabases" -PricingTier "Standard" -ErrorAction SilentlyContinue
                Write-Host "  ✓ Microsoft Defender for SQL enabled" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Failed to enable Defender: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "  [WhatIf] Would enable Defender for SQL" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  ✗ Failed to set context for subscription: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Completed ===" -ForegroundColor Cyan