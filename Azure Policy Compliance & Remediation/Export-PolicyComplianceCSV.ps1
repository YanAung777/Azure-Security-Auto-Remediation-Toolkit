<#
.SYNOPSIS
    Export detailed Azure Policy compliance to CSV for auditors
#>

$states = Get-AzPolicyState -All

$report = $states | Select-Object @{
    Name='SubscriptionName'; Expression={ (Get-AzSubscription -SubscriptionId $_.SubscriptionId).Name }
}, PolicyDefinitionName, PolicyAssignmentName, ComplianceState, ResourceId, ResourceType, Timestamp

$report | Export-Csv -Path "Azure_Policy_Compliance_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv" -NoTypeInformation
Write-Host "Compliance report exported to CSV." -ForegroundColor Green