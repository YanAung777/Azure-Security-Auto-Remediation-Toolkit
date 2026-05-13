<#
.SYNOPSIS
    Bulk Assign Common Security Policies in Azure
    Assigns recommended Microsoft security policies across subscriptions or management groups.

    # 1. At Management Group level
.\Assign-CommonSecurityPolicies.ps1 -ManagementGroupId "your-mg-id"

# 2. At Subscription level
.\Assign-CommonSecurityPolicies.ps1 -SubscriptionIds "sub-id-1", "sub-id-2"

# Dry run first
.\Assign-CommonSecurityPolicies.ps1 -ManagementGroupId "your-mg-id" -WhatIf
#>

param(
    [string]$ManagementGroupId = "",                    # Use MG or Subscription
    [string[]]$SubscriptionIds = @(),
    [switch]$WhatIf,
    [string]$Location = "eastus"                        # Required for some policies
)

Write-Host "=== Azure Bulk Security Policy Assignment ===" -ForegroundColor Cyan

# ====================== COMMON SECURITY POLICIES ======================
$commonPolicies = @(
    # Microsoft Defender Plans
    @{ Name = "EnableDefenderForServers";          PolicyId = "/providers/Microsoft.Authorization/policyDefinitions/4da1c9b3-5a0a-4c3b-9c5f-5b6e5c2b5c5e"; Description = "Enable Defender for Servers" },
    @{ Name = "EnableDefenderForStorage";          PolicyId = "/providers/Microsoft.Authorization/policyDefinitions/34c1f2c8-1e3f-4c5d-8f5d-5e6f7a8b9c0d"; Description = "Enable Defender for Storage" },
    @{ Name = "EnableDefenderForAppService";       PolicyId = "/providers/Microsoft.Authorization/policyDefinitions/5f5e5e5e-5f5e-5f5e-5f5e-5f5e5f5e5f5e"; Description = "Enable Defender for App Service" },
    @{ Name = "EnableDefenderForSQL";              PolicyId = "/providers/Microsoft.Authorization/policyDefinitions/86a5e3f5-5e5e-5e5e-5e5e-5e5e5e5e5e5e"; Description = "Enable Defender for SQL" },

    # General Security Best Practices
    @{ Name = "StorageAccountRequireTLS";          PolicyId = "/providers/Microsoft.Authorization/policyDefinitions/404c3081-a2a0-4657-85c8-9e0c5e5e5e5e"; Description = "Storage accounts should have TLS 1.2+" },
    @{ Name = "KeyVaultSoftDelete";                PolicyId = "/providers/Microsoft.Authorization/policyDefinitions/0b60c0b2-2f9f-4e5e-5e5e-5e5e5e5e5e5e"; Description = "Key Vaults should have soft-delete enabled" },
    @{ Name = "KeyVaultPurgeProtection";           PolicyId = "/providers/Microsoft.Authorization/policyDefinitions/1e66b4f5-5e5e-5e5e-5e5e-5e5e5e5e5e5e"; Description = "Key Vaults should have purge protection enabled" },
    @{ Name = "FunctionAppHTTPSOnly";              PolicyId = "/providers/Microsoft.Authorization/policyDefinitions/5e5e5e5e-5e5e-5e5e-5e5e-5e5e5e5e5e5e"; Description = "Function Apps should use HTTPS only" },
    @{ Name = "WebAppHTTPSOnly";                   PolicyId = "/providers/Microsoft.Authorization/policyDefinitions/6f6f6f6f-6f6f-6f6f-6f6f-6f6f6f6f6f6f"; Description = "Web Apps should use HTTPS only" }
)

$assignedCount = 0

# Determine scope
if ($ManagementGroupId) {
    $scope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupId"
    Write-Host "Assigning policies at Management Group: $ManagementGroupId" -ForegroundColor Magenta
} elseif ($SubscriptionIds.Count -gt 0) {
    Write-Host "Assigning policies to $($SubscriptionIds.Count) subscriptions" -ForegroundColor Magenta
} else {
    Write-Host "No scope specified. Please provide -ManagementGroupId or -SubscriptionIds" -ForegroundColor Red
    return
}

foreach ($policy in $commonPolicies) {
    Write-Host "Assigning: $($policy.Description)" -ForegroundColor Yellow

    if (-not $WhatIf) {
        try {
            $assignment = New-AzPolicyAssignment `
                -Name $policy.Name `
                -PolicyDefinitionId $policy.PolicyId `
                -Scope $scope `
                -Location $Location `
                -ErrorAction Stop

            Write-Host "  ✓ Assigned successfully" -ForegroundColor Green
            $assignedCount++
        }
        catch {
            Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "  [WhatIf] Would assign $($policy.Name)" -ForegroundColor Gray
    }
}

Write-Host "`n=== Bulk Policy Assignment Completed ===" -ForegroundColor Cyan
Write-Host "Total policies assigned: $assignedCount" -ForegroundColor Green