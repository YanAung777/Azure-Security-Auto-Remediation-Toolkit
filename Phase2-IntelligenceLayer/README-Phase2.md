# Phase 2 — Intelligence Layer

Sits in front of Phase 1, never replaces it. Phase 2 decides *whether and when* to
trigger Phase 1; Phase 1 remains the only thing that actually touches Azure resources.

## Expected folder layout

```
Azure-Security-Auto-Remediation-Toolkit-main/     <- your original, unmodified toolkit
Phase1-SafeAutoRemediation/                        <- from the Phase 1 build
  Invoke-Phase1AutoRemediation.ps1
  autonomy-matrix.json
  evidence/
Phase2-IntelligenceLayer/                          <- this build
  Invoke-Phase2Intelligence.ps1
  Get-Phase2Findings.ps1
  Get-Phase2AttackPaths.ps1
  Build-Phase2FindingTypeMap.ps1
  phase2-config.json
```

The default parameter values assume these three folders are siblings. Override the
`-AutonomyMatrixPath`, `-Phase1OrchestratorPath`, `-ToolkitScriptsPath` etc. parameters
if your layout differs.

## Prerequisites

- Everything Phase 1 needs, plus:
- `Az.ResourceGraph` module (for `Search-AzGraph`).
- `Az.PolicyInsights` module (for `Get-AzPolicyState`).
- **Defender CSPM enabled** on subscriptions where you want attack-path scoring — per your answer, this is on. If it's ever turned off for a subscription, `Get-Phase2AttackPathResourceMap` degrades to "no attack path data" rather than erroring, but that's silent — don't mistake an empty result for "no attack paths exist."
- The Phase 1 custom role needs `Microsoft.Security/assessments/read` and `Microsoft.Authorization/policyAssignments/read` (plus the resource graph query permission, which piggybacks on read access to the resource types being queried) added to its action list for the identity running Phase 2.

## Running it

```powershell
# See what Phase 2 would decide, without triggering any Phase 1 execution:
.\Invoke-Phase2Intelligence.ps1 -ForcePropose

# Real run once you trust it:
.\Invoke-Phase2Intelligence.ps1 -TeamsWebhookUrl "https://your-teams-webhook"
```

Same kill switch as Phase 1: the `PAUSE_AUTOREMEDIATION` file in the Phase 1 folder
pauses both layers, since Phase 2 checks for it before triggering anything.

## How a finding's decision actually gets made

1. **Matched vs. unmatched.** Phase 2 reads each Phase 1 `Fix-*.ps1` script's own `.SYNOPSIS` line to learn which Defender recommendation it addresses — no hand-maintained mapping table to go stale. Only the four Phase 1 categories can ever be matched; everything else (Identity, SQL, Networking, ...) is unmatched by design until a later phase extends the Autonomy Matrix.
2. **Unmatched findings never execute.** There's no script to call. They're always Propose or Escalate, by severity, for visibility only.
3. **Matched findings use the Autonomy Matrix**, same as Phase 1 — Phase 2 doesn't invent new autonomy rules, it just decides *when* to invoke Phase 1 based on clustering/scoring.
4. **Attack-path presence only ever adds caution, never autonomy.** A cluster on an active attack path can go from Propose to Escalate; it can never go from Propose to Auto. An Auto-eligible cluster on an attack path stays Auto but gets flagged urgent and an immediate Teams ping, instead of waiting to be folded into the end-of-run rollup message.

## What's deliberately NOT in this build

- **No CMDB/Service Catalog integration.** Ownership context is a single best-effort tag check (`Owner` tag on one resource per cluster, not every resource) — the design doc lists a real CMDB lookup as optional; wire it in if you have one.
- **No event-driven trigger.** This is a script you run on a schedule (or manually). Wiring "new Critical recommendation → immediate evaluation" via Event Grid/Logic App is a separate build.
- **No real ITSM ticket creation**, per your Teams-only answer. If that changes later, the integration point is the Escalate/Propose branch in the main loop — it currently only calls a Teams webhook.
- **Clustering granularity is Subscription + ResourceGroup, not exact resource type or naming pattern.** Good enough to collapse "the same finding on 40 storage accounts in one RG" into one cluster; won't catch a pattern that spans resource groups.
- **Ownership/ARG calls are not parallelized.** On a large estate this will be slow. Fine for a scheduled nightly run; not fine if you want sub-minute event-driven evaluation later.
