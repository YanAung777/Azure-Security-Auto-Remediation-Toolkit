<#
.SYNOPSIS
    Phase 0 shared hardening primitives.

.DESCRIPTION
    Two problems observed across the existing toolkit's Fix-*.ps1 scripts:
      1. Inconsistent logging -- some use Write-Host with color, some don't log at all.
      2. Inconsistent error handling -- most loop over resources with no try/catch, so
         one resource throwing (a transient API error, a locked resource, a permissions
         gap on one specific item) can abort the whole script before later resources
         are even attempted. A couple of scripts (e.g. Fix-NSGRestrictAllPorts.ps1) do
         wrap their loop; most don't.

    This module doesn't change what any script DOES -- it standardizes HOW failures
    inside a per-resource loop are handled and reported, without touching the
    remediation logic itself. Import it and wrap the existing foreach body's action
    in Invoke-Phase0SafeAction; nothing else in the script needs to change.
#>

function Write-Phase0Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","WARNING","ERROR","SUCCESS")][string]$Level = "INFO",
        [string]$LogFile
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts [$Level] $Message"
    if ($LogFile) { Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue }
    $color = switch ($Level) { "ERROR" {"Red"} "WARNING" {"Yellow"} "SUCCESS" {"Green"} default {"Gray"} }
    Write-Host $Message -ForegroundColor $color
}

function Invoke-Phase0SafeAction {
    <#
    .SYNOPSIS
        Runs $Action for a single resource; catches any error so the caller's loop
        can continue to the next resource instead of aborting the whole script.

    .EXAMPLE
        foreach ($sa in $storageAccounts) {
            Invoke-Phase0SafeAction -ResourceName $sa.StorageAccountName -LogFile $logFile -Action {
                Set-AzStorageAccount -ResourceGroupName $sa.ResourceGroupName -Name $sa.StorageAccountName -MinimumTlsVersion "TLS1_2" | Out-Null
            }
        }
    #>
    param(
        [Parameter(Mandatory)][string]$ResourceName,
        [Parameter(Mandatory)][scriptblock]$Action,
        [string]$LogFile
    )
    try {
        & $Action
        Write-Phase0Log "  OK: $ResourceName" "SUCCESS" $LogFile
        return [PSCustomObject]@{ ResourceName = $ResourceName; Status = "Success"; Error = $null }
    } catch {
        Write-Phase0Log "  FAILED: $ResourceName -- $($_.Exception.Message)" "ERROR" $LogFile
        return [PSCustomObject]@{ ResourceName = $ResourceName; Status = "Failed"; Error = $_.Exception.Message }
    }
}

function Test-Phase0RequiredParam {
    <#
    .SYNOPSIS
        Basic parameter validation: fail fast with a clear message instead of an
        obscure error three lines into the script when a required value is blank.
    #>
    param(
        [Parameter(Mandatory)][string]$ParamName,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [string]$LogFile
    )
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-Phase0Log "Required parameter '$ParamName' is empty. Aborting." "ERROR" $LogFile
        throw "Missing required parameter: $ParamName"
    }
}

Export-ModuleMember -Function Write-Phase0Log, Invoke-Phase0SafeAction, Test-Phase0RequiredParam
