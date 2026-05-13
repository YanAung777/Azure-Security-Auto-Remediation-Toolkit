<#
.SYNOPSIS
    Auto-fix: "Permissions of inactive identities in your Azure subscription should be revoked"
    Removes role assignments from users who have been inactive (no sign-in) for a specified number of days.

    # Dry run first (recommended)
.\Fix-RemoveInactiveIdentitiesPermissions.ps1 -WhatIf

# Actual remediation (90 days inactivity)
.\Fix-RemoveInactiveIdentitiesPermissions.ps1

# Change threshold to 180 days
.\Fix-RemoveInactiveIdentitiesPermissions.ps1 -InactiveDays 180
#>

param(
    [switch]$WhatIf,
    [int]$InactiveDays = 90,                    # Default: 90 days of inactivity
    [string[]]$RolesToCheck = @("Owner", "Contributor", "User Access Administrator", "Reader")
)

Write-Host "=== Removing Permissions from Inactive Identities ===" -ForegroundColor Cyan
Write-Host "Inactive threshold: $InactiveDays days`n" -ForegroundColor Yellow

# Ensure Microsoft Graph module is available
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) {
    Write-Host "Installing Microsoft.Graph.Users module..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph.Users -Scope CurrentUser -Force
}

Import-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue

# Connect to Microsoft Graph if not already connected
try {
    $null = Get-MgContext
} catch {
    Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All" -UseDeviceAuthentication
}

# Calculate cutoff date
$cutoffDate = (Get-Date).AddDays(-$InactiveDays)

# Get all users who haven't signed in recently
$inactiveUsers = Get-MgUser -All -Property Id, DisplayName, UserPrincipalName, SignInActivity |
    Where-Object { 
        $_.SignInActivity.LastSignInDateTime -lt $cutoffDate -and 
        $_.AccountEnabled -eq $true 
    }

if ($inactiveUsers.Count -eq 0) {
    Write-Host "No inactive users found (inactive for more than $InactiveDays days)." -ForegroundColor Green
    return
}

Write-Host "Found $($inactiveUsers.Count) inactive users.`n" -ForegroundColor Yellow

$removedCount = 0

foreach ($user in $inactiveUsers) {
    $upn = $user.UserPrincipalName
    $displayName = $user.DisplayName
    $lastSignIn = $user.SignInActivity.LastSignInDateTime

    # Get role assignments for this user
    $roleAssignments = Get-AzRoleAssignment -ObjectId $user.Id | 
        Where-Object { $_.RoleDefinitionName -in $RolesToCheck }

    foreach ($ra in $roleAssignments) {
        $role = $ra.RoleDefinitionName
        $scope = $ra.Scope

        Write-Host "Inactive user '$displayName' ($upn) has '$role' at $scope" -ForegroundColor Yellow

        if (-not $WhatIf) {
            try {
                Remove-AzRoleAssignment -ObjectId $user.Id `
                                        -RoleDefinitionName $role `
                                        -Scope $scope -ErrorAction Stop
                
                Write-Host "  ✓ Removed '$role' assignment from inactive user" -ForegroundColor Green
                $removedCount++
            }
            catch {
                Write-Host "  ✗ Failed to remove assignment: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "  [WhatIf] Would remove '$role' from '$displayName'" -ForegroundColor Gray
        }
    }
}

Write-Host "`nInactive identities remediation completed. Removed $removedCount role assignments." -ForegroundColor Green
Write-Host "Note: Adjust -InactiveDays parameter as needed (default is 90 days)." -ForegroundColor Cyan