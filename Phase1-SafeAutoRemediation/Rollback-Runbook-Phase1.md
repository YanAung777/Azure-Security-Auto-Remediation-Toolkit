# Phase 1 Rollback Runbook

Applies to the four Phase 1 categories: Storage, KeyVault, AppServices, Defender.
Read this *before* promoting any category to "Auto" in the Autonomy Matrix.

---

## Storage (TLS / HTTPS-only / Public Blob Access) — reversible

| Fix | Rollback command | Notes |
|---|---|---|
| Minimum TLS 1.2 | `Set-AzStorageAccount -ResourceGroupName <rg> -Name <name> -MinimumTlsVersion TLS1_0` | Only do this to unblock a legitimate legacy client while you fix the client — reverting is itself a security regression, not a neutral rollback. |
| HTTPS-only (secure transfer) | `Set-AzStorageAccount -ResourceGroupName <rg> -Name <name> -EnableHttpsTrafficOnly $false` | Same caveat as above. |
| Public blob access | `Set-AzStorageAccount -ResourceGroupName <rg> -Name <name> -AllowBlobPublicAccess $true` | Only re-enable for a specific container that genuinely needs anonymous read; don't blanket-revert. |

**Blast radius if this goes wrong:** app or client that depended on plaintext HTTP, TLS 1.0, or anonymous blob reads breaks. No data loss.

---

## Key Vault (Soft Delete / Purge Protection / RBAC) — **soft delete and purge protection are NOT reversible**

This is a platform behavior, not a toolkit limitation: once enabled, Key Vault soft delete cannot be turned back off, and once purge protection is enabled it cannot be disabled by anyone, including Microsoft, until the retention period elapses. Soft delete is also now effectively mandatory — the opt-out was deprecated. Confirm this against current Microsoft Learn documentation before you rely on it, since platform behavior can change.

**Practical implication for the Autonomy Matrix:** marking these "Auto" is defensible because the change is additive/protective (it doesn't remove functionality or delete data), but do not describe it to stakeholders as "safe because it's rollback-able" — it isn't. If a team genuinely needs to delete-and-immediately-reuse a vault name (a real workflow for some CI/CD pipelines), soft delete changes that workflow permanently once turned on. Flag this to any team that manages vault lifecycles programmatically before Phase 1 goes live for their subscriptions.

| Fix | Rollback | Notes |
|---|---|---|
| Soft delete | **None.** | Irreversible. |
| Purge protection | **None.** | Irreversible once set; the vault/object must be recovered or the retention period must elapse. |
| RBAC authorization (vs. access policies) | `Update-AzKeyVault -ResourceGroupName <rg> -VaultName <name> -EnableRbacAuthorization $false` | Reversible, but re-enabling access-policy mode does not restore whatever access policies existed before — you'd need those captured separately if you ever plan to revert. |

**Recommendation:** before turning KeyVault to "Auto" for any subscription, run a short comms pass with the owning teams specifically about soft delete/purge protection being permanent — don't rely on the Autonomy Matrix's "safe" label to cover this.

---

## App Services (Function/Web App HTTPS-only, Minimum TLS) — reversible

| Fix | Rollback command | Notes |
|---|---|---|
| HTTPS-only | `Set-AzWebApp -ResourceGroupName <rg> -Name <name> -HttpsOnly $false` | |
| Minimum TLS 1.2 | `Set-AzWebApp -ResourceGroupName <rg> -Name <name> -MinTlsVersion 1.0` | |

**Blast radius if this goes wrong:** same class of risk as Storage — legacy clients or health checks that hit the app over plain HTTP or old TLS will start failing.

---

## Defender (Plan enablement) — reversible, but scoping is the real risk

| Fix | Rollback command | Notes |
|---|---|---|
| Any plan | `Set-AzSecurityPricing -Name <plan> -PricingTier "Free"` | Reversible at any time. |

The actual risk here isn't reversibility, it's scope: `Fix-EnableDefenderPlans.ps1` loops every subscription the identity can see and calls `Set-AzContext` on each one internally, ignoring whatever subscription the orchestrator thinks it's operating in. Until that script accepts a `-SubscriptionId` parameter, treat any "Auto" outcome for Defender as suspect — the orchestrator in this build hard-overrides Defender to Propose regardless of the matrix for exactly this reason. If you fix the script to accept explicit scope, remove the override in `Invoke-Phase1AutoRemediation.ps1` and re-test in non-prod before trusting it.

**Cost note:** Defender plans are billed per resource/hour. A rollback here is operationally trivial but a wrong "Auto" firing tenant-wide is a real, immediate cost event, not just a security one — this is why the design's own Autonomy Matrix keeps Defender mostly at Propose/Escalate rather than Auto.

---

## General rule for all categories

Every category's rollback assumes you know *which* resources were touched and *when*. That's exactly what the `remediated-by` / `remediated-at` / `remediation-script` tags and the JSON evidence file are for — before rolling anything back, pull the relevant `Phase1_Evidence_*.json` file and use its `entries[].resourceId` list rather than guessing from the portal.
