<#
.SYNOPSIS
    Attack-path awareness (design doc Concept 7) via the Defender CSPM Attack Path API,
    which is exposed through Azure Resource Graph rather than a separate REST endpoint.

.DESCRIPTION
    Requires Defender CSPM to be enabled on the subscription(s) in scope -- this returns
    an empty map (not an error) if it isn't, so it's safe to call unconditionally.

    Query pattern is Microsoft's own documented approach:
        securityresources | where type == "microsoft.security/attackpaths"
    Entities on the path live under properties.graphComponent.entities[], each with
    entityIdentifiers.azureResourceId -- we expand those to build a ResourceId -> risk map.
#>

function Get-Phase2AttackPathResourceMap {
    param([string[]]$SubscriptionIds)

    $query = @'
securityresources
| where type == "microsoft.security/attackpaths"
| extend displayName = tostring(properties.displayName)
| extend riskLevel = tostring(properties.riskLevel)
| mv-expand entity = properties.graphComponent.entities
| extend resourceId = tolower(tostring(entity.entityIdentifiers.azureResourceId))
| where isnotempty(resourceId)
| project resourceId, displayName, riskLevel
'@

    $params = @{ Query = $query; First = 1000 }
    if ($SubscriptionIds) { $params.Subscription = $SubscriptionIds }

    $map = @{}
    try {
        $rows = Search-AzGraph @params -ErrorAction Stop
        foreach ($row in $rows) {
            # A resource can sit on more than one attack path; keep the highest-risk one.
            if (-not $map.ContainsKey($row.resourceId) -or
                (Compare-Phase2RiskLevel $row.riskLevel) -gt (Compare-Phase2RiskLevel $map[$row.resourceId].RiskLevel)) {
                $map[$row.resourceId] = [PSCustomObject]@{
                    RiskLevel   = $row.riskLevel
                    DisplayName = $row.displayName
                }
            }
        }
    } catch {
        Write-Warning "Get-Phase2AttackPathResourceMap: query failed ($($_.Exception.Message)). Treating as 'no attack path data available' -- confirm Defender CSPM is actually enabled before assuming this means 'no attack paths exist'."
    }
    return $map
}

function Compare-Phase2RiskLevel {
    param([string]$RiskLevel)
    switch ($RiskLevel) {
        "Critical" { 3 }
        "High"     { 2 }
        "Medium"   { 1 }
        default    { 0 }
    }
}
