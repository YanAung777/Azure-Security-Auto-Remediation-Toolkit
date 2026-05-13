<#
.SYNOPSIS
    Auto-fix: "There should be more than one owner assigned to subscriptions"
    Reports subscriptions with fewer than 2 Owners and provides guidance.
#>

param([switch]$WhatIf)

Write-Host "=== Ensuring Multiple Owners on Each Subscription ===" -ForegroundColor Cyan

$subs = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }

foreach ($sub in $subs) {
    $owners = Get-AzRoleAssignment -Scope "/subscriptions/$($sub.Id)" | 
              Where-Object { $_.RoleDefinitionName -eq "Owner" } | 
              Select-Object -ExpandProperty DisplayName

    if ($owners.Count -lt 2) {
        Write-Host "⚠ Subscription '$($sub.Name)' has only $($owners.Count) Owner(s): $($owners -join ', ')" -ForegroundColor Yellow
        Write-Host "   → Recommendation: Add at least one more Owner (break-glass or security account)" -ForegroundColor Cyan
    } else {
        Write-Host "✓ Subscription '$($sub.Name)' has $($owners.Count) Owners - Compliant" -ForegroundColor Green
    }
}

Write-Host "`nMultiple Owners check completed." -ForegroundColor Green