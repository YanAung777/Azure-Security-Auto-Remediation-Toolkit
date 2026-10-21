<#
.SYNOPSIS
    Generates a reverse script from a Phase 1 evidence file, using the recorded before-state.

.DESCRIPTION
    - The generated script is PREVIEW-ONLY unless run with -Execute.
    - Reverting a security fix is itself a security regression. Use it to unblock a broken workload
      while the real problem is fixed, then re-apply the fix.
    - Key Vault soft delete / purge protection cannot be reversed (platform behaviour) and Key Vault
      RBAC is left as a manual step; those appear as MANUAL lines, never as commands.
    - Defender plans are not generated: Phase 1 never auto-executes them.
#>
param(
    [Parameter(Mandatory)][string]$EvidenceFile,
    [string]$ApprovalId,
    [string]$OutFile = ".\Undo_$(Get-Date -Format 'yyyyMMdd_HHmmss').ps1"
)
$pkg = Get-Content $EvidenceFile -Raw | ConvertFrom-Json
$entries = @($pkg.entries | Where-Object { $_.status -eq "Remediated" -and (-not $ApprovalId -or $_.approvalId -eq $ApprovalId) })
if ($entries.Count -eq 0) { throw "No remediated entries found in $EvidenceFile$(if ($ApprovalId) { " for approval $ApprovalId" })." }

function q($v) { "'" + ([string]$v).Replace("'", "''") + "'" }
function b($v) { if ($v -eq $true) { '$true' } else { '$false' } }

$out = @()
$out += "# Generated $(Get-Date -Format o) from $EvidenceFile (run $($pkg.runId))"
$out += "# PREVIEW by default. Add -Execute to apply. Reverting a security fix is a regression -- re-apply it once the underlying problem is fixed."
$out += 'param([switch]$Execute)'
$out += 'function Do-Undo([string]$Desc, [scriptblock]$Action) { if ($Execute) { Write-Host "Reverting: $Desc"; & $Action } else { Write-Host "[Preview] Would revert: $Desc" } }'
foreach ($e in $entries) {
    $bs = $e.beforeState
    $sub = ([regex]::Match($e.resourceId, '/subscriptions/([^/]+)/')).Groups[1].Value
    $ctx = "Set-AzContext -SubscriptionId $(q $sub) | Out-Null; "
    $rg = q $bs.ResourceGroup; $nm = q $bs.Name
    switch ($e.script) {
        "Fix-StorageAccountTLS.ps1"        { $out += "Do-Undo $(q "$($bs.Name): MinimumTlsVersion -> $($bs.MinimumTlsVersion)") { $ctx`Set-AzStorageAccount -ResourceGroupName $rg -Name $nm -MinimumTlsVersion $(q $bs.MinimumTlsVersion) | Out-Null }" }
        "Fix-StorageSecureTransfer.ps1"    { $out += "Do-Undo $(q "$($bs.Name): EnableHttpsTrafficOnly -> $($bs.EnableHttpsTrafficOnly)") { $ctx`Set-AzStorageAccount -ResourceGroupName $rg -Name $nm -EnableHttpsTrafficOnly $(b $bs.EnableHttpsTrafficOnly) | Out-Null }" }
        "Fix-StoragePublicBlobAccess.ps1"  { $out += "Do-Undo $(q "$($bs.Name): AllowBlobPublicAccess -> $($bs.AllowBlobPublicAccess)") { $ctx`Set-AzStorageAccount -ResourceGroupName $rg -Name $nm -AllowBlobPublicAccess $(b $bs.AllowBlobPublicAccess) | Out-Null }" }
        "Fix-FunctionAppHTTPSOnly.ps1"     { $out += "Do-Undo $(q "$($bs.Name): HttpsOnly -> $($bs.HttpsOnly)") { $ctx`Set-AzWebApp -ResourceGroupName $rg -Name $nm -HttpsOnly $(b $bs.HttpsOnly) | Out-Null }" }
        "Fix-FunctionAppMinimumTLS.ps1"    { $out += "Do-Undo $(q "$($bs.Name): MinTlsVersion -> $($bs.MinTlsVersion)") { $ctx`Set-AzWebApp -ResourceGroupName $rg -Name $nm -MinTlsVersion $(q $bs.MinTlsVersion) | Out-Null }" }
        "Fix-EnableKeyVaultSoftDelete.ps1"       { $out += "# MANUAL / NOT REVERSIBLE: $($bs.Name) soft delete cannot be disabled once enabled." }
        "Fix-EnableKeyVaultPurgeProtection.ps1"  { $out += "# MANUAL / NOT REVERSIBLE: $($bs.Name) purge protection cannot be disabled once enabled." }
        "Fix-EnableKeyVaultRBAC.ps1"             { $out += "# MANUAL: $($bs.Name) was switched to RBAC authorization. Confirm the vault's access policies before reverting; not generated automatically." }
        default                                  { $out += "# MANUAL: no reverse generator for $($e.script) ($($e.resourceName))." }
    }
}
$out | Set-Content -Path $OutFile
Write-Host "Wrote $OutFile ($($entries.Count) entries). Review it, then run it (preview by default)." -ForegroundColor Green
