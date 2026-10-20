<#
.SYNOPSIS
    Auto-fix: "Auditing should be enabled at the server level for SQL Servers"

.NOTES
    PHASE 0 HARDENED VERSION of the original Fix-EnableSQLServerAuditing.ps1.
    Remediation logic is unchanged (same Set-AzSqlServerAuditing call, same optional
    -StorageAccountResourceId). What changed:
      - -ErrorAction SilentlyContinue removed from both the read (Get-AzSqlServerAuditing)
        and the write (Set-AzSqlServerAuditing) -- the original had no way to tell a
        server whose auditing check or enablement failed apart from one that was
        already compliant. Both paths are now distinguishable.
      - One SQL server failing no longer risks silently skipping the rest.
      - Warns (once, up front) if $StorageAccountResourceId is blank, since whether
        that's intentional (Log Analytics-only auditing) or a missed parameter isn't
        obvious from the original script -- this doesn't change behavior, just surfaces
        the ambiguity so whoever runs it notices.
      - Consistent timestamped logging + run summary via Phase0-Common.psm1.

    This is a proposed replacement, not applied automatically -- review it, then decide
    whether to replace the original in the toolkit repo or keep both side by side.
#>

param(
    [switch]$WhatIf,
    [string]$StorageAccountResourceId = "",
    [string]$LogFile = ".\logs\Fix-EnableSQLServerAuditing_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

Import-Module (Join-Path $PSScriptRoot "..\Phase0-Common.psm1") -Force

$logDir = Split-Path $LogFile -Parent
if ($logDir -and -not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

Write-Phase0Log "=== Enabling SQL Server Auditing ===" "INFO" $LogFile
if (-not $StorageAccountResourceId) {
    Write-Phase0Log "No -StorageAccountResourceId supplied. Confirm this is intentional (e.g. Log Analytics-only auditing) before relying on Auto for this category." "WARNING" $LogFile
}

$sqlServers = Get-AzSqlServer
Write-Phase0Log "Found $($sqlServers.Count) SQL server(s) to check." "INFO" $LogFile

$results = @()
foreach ($server in $sqlServers) {
    $rg = $server.ResourceGroupName
    $name = $server.ServerName

    try {
        $audit = Get-AzSqlServerAuditing -ResourceGroupName $rg -ServerName $name -ErrorAction Stop
    } catch {
        Write-Phase0Log "  Could not read auditing state for '$name': $($_.Exception.Message)" "ERROR" $LogFile
        $results += [PSCustomObject]@{ ResourceName = $name; Status = "Failed"; Error = $_.Exception.Message }
        continue
    }

    if (-not $audit -or $audit.State -ne "Enabled") {
        Write-Phase0Log "SQL Server '$name' - Enabling Auditing" "WARNING" $LogFile

        if ($WhatIf) {
            Write-Phase0Log "  [WhatIf] Would enable auditing" "INFO" $LogFile
            $results += [PSCustomObject]@{ ResourceName = $name; Status = "WhatIf"; Error = $null }
            continue
        }

        $results += Invoke-Phase0SafeAction -ResourceName $name -LogFile $LogFile -Action {
            $params = @{ ResourceGroupName = $rg; ServerName = $name; State = "Enabled" }
            if ($StorageAccountResourceId) { $params.StorageAccountResourceId = $StorageAccountResourceId }
            Set-AzSqlServerAuditing @params -ErrorAction Stop | Out-Null
        }
    } else {
        $results += [PSCustomObject]@{ ResourceName = $name; Status = "AlreadyCompliant"; Error = $null }
    }
}

$summary = [PSCustomObject]@{
    Total            = $results.Count
    Enabled          = ($results | Where-Object Status -eq "Success").Count
    AlreadyCompliant = ($results | Where-Object Status -eq "AlreadyCompliant").Count
    Failed           = ($results | Where-Object Status -eq "Failed").Count
    WhatIf           = ($results | Where-Object Status -eq "WhatIf").Count
}
Write-Phase0Log "Summary: $($summary.Enabled) enabled, $($summary.AlreadyCompliant) already compliant, $($summary.Failed) failed, $($summary.WhatIf) whatif (of $($summary.Total))." "SUCCESS" $LogFile

$results
