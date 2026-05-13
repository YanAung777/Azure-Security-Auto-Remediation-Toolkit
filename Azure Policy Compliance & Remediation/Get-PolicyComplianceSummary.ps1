<#
.SYNOPSIS
    Azure Policy Compliance Summary Report
    Generates a clear compliance report for auditors and security teams.
#>

param(
    [string[]]$SubscriptionIds = @(),
    [switch]$ExportToExcel
)

Write-Host "=== Azure Policy Compliance Summary ===" -ForegroundColor Cyan

if ($SubscriptionIds.Count -eq 0) {
    $subs = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
} else {
    $subs = $SubscriptionIds | ForEach-Object { Get-AzSubscription -SubscriptionId $_ }
}

$results = @()

foreach ($sub in $subs) {
    Write-Host "Scanning Subscription: $($sub.Name)" -ForegroundColor Yellow
    Set-AzContext -Subscription $sub.Id | Out-Null

    $states = Get-AzPolicyState -All

    $summary = $states | Group-Object ComplianceState | ForEach-Object {
        [PSCustomObject]@{
            SubscriptionName = $sub.Name
            SubscriptionId   = $sub.Id
            ComplianceState  = $_.Name
            PolicyCount      = $_.Count
            Percentage       = [math]::Round(($_.Count / $states.Count) * 100, 2)
        }
    }

    $results += $summary
}

# Overall Summary
$results | Format-Table -AutoSize SubscriptionName, ComplianceState, PolicyCount, Percentage

if ($ExportToExcel) {
    $results | Export-Excel -Path "Azure_Policy_Compliance_$(Get-Date -Format 'yyyyMMdd_HHmmss').xlsx" -WorksheetName "PolicyCompliance" -AutoSize -TableName "Compliance"
    Write-Host "Report exported to Excel." -ForegroundColor Green
}

# Non-compliant policies (Top 10)
Write-Host "`nTop 10 Non-Compliant Policies:" -ForegroundColor Red
$nonCompliant = Get-AzPolicyState | Where-Object { $_.ComplianceState -eq "NonCompliant" } | 
                Group-Object PolicyDefinitionName | Sort-Object Count -Descending | Select-Object -First 10

$nonCompliant | Format-Table @{Name='Policy'; Expression={$_.Name}}, @{Name='NonCompliantCount'; Expression={$_.Count}}