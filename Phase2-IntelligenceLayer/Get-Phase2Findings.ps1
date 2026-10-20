<#
.SYNOPSIS
    Finding ingestion + normalization for Phase 2.

.DESCRIPTION
    Two sources, one common output shape:
      - Get-Phase2DefenderFindings  : Azure Resource Graph query against
        securityresources where type == 'microsoft.security/assessments',
        filtered to unhealthy (non-compliant) assessments.
      - Get-Phase2PolicyFindings    : Get-AzPolicyState, same filter the
        existing toolkit's Export-NonCompliantResourcesWithRemediation.ps1
        already uses (kept identical on purpose, for consistency with a
        script you already trust).

    Both are normalized by ConvertTo-Phase2NormalizedFinding into:
        ResourceId, ResourceGroup, SubscriptionId, RecommendationName,
        Severity, Source ("Defender" | "Policy"), DiscoveredAtUtc
#>

function Get-Phase2DefenderFindings {
    param([string[]]$SubscriptionIds)

    $query = @'
securityresources
| where type == 'microsoft.security/assessments'
| where properties.status.code == 'Unhealthy'
| extend recommendationName = tostring(properties.displayName)
| extend severity = tostring(properties.metadata.severity)
| project id, recommendationName, severity, subscriptionId
'@

    $params = @{ Query = $query; First = 1000 }
    if ($SubscriptionIds) { $params.Subscription = $SubscriptionIds }

    $rows = Search-AzGraph @params

    foreach ($row in $rows) {
        # An assessment's own ARM id is a sub-resource of the TARGET resource:
        #   /.../providers/Microsoft.Storage/storageAccounts/foo/providers/Microsoft.Security/assessments/<guid>
        # Strip the assessment suffix to recover the actual resource id.
        $targetResourceId = ($row.id -split '/providers/Microsoft\.Security/assessments/')[0]
        [PSCustomObject]@{
            ResourceId         = $targetResourceId
            SubscriptionId     = $row.subscriptionId
            RecommendationName = $row.recommendationName
            Severity           = if ($row.severity) { $row.severity } else { "Unknown" }
            Source             = "Defender"
        }
    }
}

function Get-Phase2PolicyFindings {
    # Deliberately mirrors Export-NonCompliantResourcesWithRemediation.ps1's own
    # query so this stays consistent with a script already in production use.
    $states = Get-AzPolicyState -Filter "ComplianceState eq 'NonCompliant'" -All

    foreach ($state in $states) {
        [PSCustomObject]@{
            ResourceId         = $state.ResourceId
            SubscriptionId     = $state.SubscriptionId
            RecommendationName = $state.PolicyDefinitionName
            Severity           = "Unknown"   # Policy states don't carry a severity; scoring falls back to the Unknown weight.
            Source             = "Policy"
        }
    }
}

function ConvertTo-Phase2NormalizedFinding {
    param([Parameter(ValueFromPipeline)]$Finding)
    process {
        $rgMatch = [regex]::Match($Finding.ResourceId, '(?i)/resourceGroups/([^/]+)/')
        [PSCustomObject]@{
            ResourceId         = $Finding.ResourceId
            ResourceGroup      = if ($rgMatch.Success) { $rgMatch.Groups[1].Value } else { $null }
            SubscriptionId     = $Finding.SubscriptionId
            RecommendationName = $Finding.RecommendationName
            Severity           = $Finding.Severity
            Source             = $Finding.Source
            DiscoveredAtUtc    = (Get-Date).ToUniversalTime().ToString("o")
        }
    }
}
