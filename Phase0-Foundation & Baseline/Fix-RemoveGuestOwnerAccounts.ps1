<#
.SYNOPSIS
    Auto-fix: "Guest accounts with owner permissions on Azure resources should be removed"

.NOTES
    PHASE 0 HARDENED VERSION of the original Fix-RemoveGuestOwnerAccounts.ps1.
    Remediation logic is byte-for-byte the same (still Remove-AzRoleAssignment on the
    same filter). What changed:
      - -ErrorAction SilentlyContinue removed: the original swallowed failures with no
        way to tell a removal failed vs. succeeded. Now every attempt is individually
        caught and reported.
      - One guest's removal failing (locked scope, insufficient permission at that
        specific scope, transient throttling) no longer risks looking like success --
        it's now visible in the summary and the log file.
      - Consistent timestamped logging via Phase0-Common.psm1, matching every other
        Phase 0/1/2 script in this build instead of ad hoc Write-Host color choices.
      - A run summary (removed / failed / whatif counts) is written at the end instead
        of only per-line console output.

    This is a proposed replacement, not applied automatically -- review it, then decide
    whether to replace the original in the toolkit repo or keep both side by side.
#>

param(
    [switch]$WhatIf,
    [string]$LogFile = ".\logs\Fix-RemoveGuestOwnerAccounts_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

Import-Module (Join-Path $PSScriptRoot "..\Phase0-Common.psm1") -Force

$logDir = Split-Path $LogFile -Parent
if ($logDir -and -not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

Write-Phase0Log "=== Removing Guest Accounts with Owner Permissions ===" "INFO" $LogFile

$assignments = Get-AzRoleAssignment | Where-Object { $_.RoleDefinitionName -eq "Owner" -and $_.SignInName -like "*#EXT#*" }
Write-Phase0Log "Found $($assignments.Count) guest account(s) with Owner role." "INFO" $LogFile

$results = @()
foreach ($ra in $assignments) {
    Write-Phase0Log "Guest '$($ra.SignInName)' has Owner at $($ra.Scope)" "WARNING" $LogFile

    if ($WhatIf) {
        Write-Phase0Log "  [WhatIf] Would remove" "INFO" $LogFile
        $results += [PSCustomObject]@{ ResourceName = $ra.SignInName; Status = "WhatIf"; Error = $null }
        continue
    }

    $results += Invoke-Phase0SafeAction -ResourceName $ra.SignInName -LogFile $LogFile -Action {
        Remove-AzRoleAssignment -ObjectId $ra.ObjectId -RoleDefinitionName "Owner" -Scope $ra.Scope -ErrorAction Stop
    }
}

$summary = [PSCustomObject]@{
    Total   = $results.Count
    Removed = ($results | Where-Object Status -eq "Success").Count
    Failed  = ($results | Where-Object Status -eq "Failed").Count
    WhatIf  = ($results | Where-Object Status -eq "WhatIf").Count
}
Write-Phase0Log "Summary: $($summary.Removed) removed, $($summary.Failed) failed, $($summary.WhatIf) whatif (of $($summary.Total))." "SUCCESS" $LogFile

$results
