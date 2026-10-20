# Phase 1 — Safe Auto-Remediation

Wraps the existing, unmodified `Fix-*.ps1` scripts with autonomy-matrix decisions,
evidence capture, and a kill switch. Nothing in the original toolkit folder is edited.

## Files in this build

| File | Purpose |
|---|---|
| `Invoke-Phase1AutoRemediation.ps1` | The orchestrator. Run this, not the individual Fix- scripts, from now on for Phase 1 categories. |
| `autonomy-matrix.json` | Category × environment → Auto/Propose/Escalate. Edit this to tune behavior; don't hardcode decisions in the script. |
| `RBAC-Phase1-CustomRole.json` | Custom role definition for the automation identity — deliberately *not* Contributor. |
| `Rollback-Runbook-Phase1.md` | Read before turning anything to "Auto", especially the Key Vault section. |

## Prerequisites

- PowerShell 7+ (uses `ConvertFrom-Json -AsHashtable`, not available in Windows PowerShell 5.1's built-in cmdlet).
- Az modules: `Az.Accounts`, `Az.Storage`, `Az.KeyVault`, `Az.Websites`, `Az.Functions`, `Az.Security`, `Az.Resources`.
- The identity running this needs the custom role in `RBAC-Phase1-CustomRole.json` assigned at your target management group or subscription scope — replace the placeholder `AssignableScopes` value first.
- Every subscription in scope should be tagged `Environment` = `NonProd`/`Prod`, and `Prod` subscriptions should additionally be tagged `Criticality` = `Low`/`High`. Untagged subscriptions fail closed to `ProdHighRisk` (mostly Propose/Escalate) — they will not silently get Auto treatment.

## Running it

```powershell
# Dry-run everything, see what would happen, touch nothing:
.\Invoke-Phase1AutoRemediation.ps1 -Category All -WhatIf

# First real pilot run, but force Propose everywhere even for Auto categories
# (recommended for at least the first week, regardless of what the matrix says):
.\Invoke-Phase1AutoRemediation.ps1 -Category Storage -ForcePropose

# Real run once you trust it:
.\Invoke-Phase1AutoRemediation.ps1 -Category Storage
```

Emergency stop at any time: create a file at `.\PAUSE_AUTOREMEDIATION` (or set
`killSwitch.enabled: true` in `autonomy-matrix.json`). Every category forces to
Propose on the next run until the file is removed / flag is cleared. This does
not require redeploying anything.

## What's deliberately NOT in this build (don't assume it exists)

- **No clustering or noise suppression.** If the same finding shows up on 40 storage accounts, you get 40 evidence entries and one Teams message with a count — nothing groups them into "one recurring pattern." That's Phase 2.
- **No priority scoring, ownership resolution, or attack-path awareness.** The evidence schema has `priorityScore`, `clusterId`, and `owner` fields present but set to `null` on purpose, so Phase 2 can start populating them without breaking anything reading Phase 1 evidence files.
- **No real ITSM integration.** `Propose`/`Escalate` decisions write a `TicketRequest_*.json` stub to the evidence folder. Nothing files a ServiceNow or Jira ticket yet — someone (or a Logic App you build next) has to read those stubs.
- **No Azure Table/Log Analytics-backed recurrence store.** Recurrence tracking uses a local JSON file (`state/RemediationHistory.json`). Fine for a pilot on one machine; not fine for a scheduled Azure Automation job running from ephemeral compute — swap `Get-RecurrenceStore`/`Save-RecurrenceStore` for a real backing store before this runs unattended on a schedule.
- **Defender is capped at Propose, permanently, in this build.** `Fix-EnableDefenderPlans.ps1` loops every visible subscription internally regardless of what scope you invoke it with, so "Auto" can't be trusted until that script is parameterized with `-SubscriptionId`. The orchestrator hard-overrides this — don't try to force it via the matrix, you'd have to change the script first.
- **No per-resource canary/percentage rollout.** Scoping is by subscription only (via the Environment/Criticality tags), not by a gradual percentage of resources within a subscription.

## Suggested rollout order

1. Run with `-WhatIf` against every non-prod subscription. Read the evidence output, confirm the resource counts look sane.
2. Run for real with `-ForcePropose` against non-prod for a week — this exercises the whole pipeline (snapshot, ticket stub, Teams notification) without touching anything, so you catch bugs in tagging/evidence logic before they matter.
3. Drop `-ForcePropose`, let Storage and KeyVault run Auto in non-prod for real.
4. Once Auto in non-prod has run clean for a few cycles, extend to `ProdLow` per the matrix.
5. Do not extend AppServices or Defender to Prod categories until Phase 2's ownership/attack-path context exists — the matrix already keeps those at Propose/Escalate in Prod for this reason.
