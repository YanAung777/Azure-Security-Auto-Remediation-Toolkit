# Phase 0 — Foundation & Baseline

Folder layout assumes this sits as a sibling to `Phase1-SafeAutoRemediation` and
`Phase2-IntelligenceLayer`, same as those two assume of each other:

```
Azure-Security-Auto-Remediation-Toolkit-main/
Phase0-Foundation/            <- this build
  Phase0-Common.psm1
  Baseline-Report.ps1
  Hardening-Checklist.md
  autonomy-matrix-v0.1-baseline.json
  Hardened-Examples/
  infra/
    main.bicep
    custom-role.bicep
  Deploy-Phase0Automation.ps1
Phase1-SafeAutoRemediation/
Phase2-IntelligenceLayer/
```

## Important: build order got reshuffled

You asked for Phase 1 and Phase 2 before Phase 0, so some Phase 0 groundwork already
exists inside those folders rather than here:

- The Autonomy Matrix (Phase 1's `autonomy-matrix.json`) already has real Auto
  decisions, not the "everything Propose" starting point the design doc describes for
  Phase 0. `autonomy-matrix-v0.1-baseline.json` in this folder is the retroactive
  governance artifact documenting what the *actual* starting point should have been,
  for audit-trail purposes — fill in the placeholder dates/approvers if you want a
  clean paper trail of "Propose everywhere, then Phase 1 approval granted Auto for
  four categories."
- Structured JSON evidence export already exists (built in Phase 1).
- Finding ingestion/normalization already exists (built in Phase 2); `Baseline-Report.ps1`
  in this folder reuses that code rather than duplicating it.

What's actually new here: script hardening, the Automation infrastructure, the
schedules, and the baseline report itself.

## Deployment order

1. **`infra/main.bicep`** at resource group scope — creates the Automation Account
   (system-assigned identity), Log Analytics workspace, and evidence Storage Account.
   ```
   az deployment group create -g <rg-name> --template-file infra/main.bicep
   ```
2. **`infra/custom-role.bicep`** at subscription scope — creates the least-privilege
   role and assigns it to the identity from step 1's output.
   ```
   az deployment sub create --location <region> --template-file infra/custom-role.bicep \
     --parameters automationAccountPrincipalId=<output from step 1>
   ```
3. **`Deploy-Phase0Automation.ps1`** — imports the Phase 1 runbook and creates the
   Daily/Weekly schedules.
4. **`Baseline-Report.ps1`** — run this manually first, before anything is scheduled,
   so the baseline reflects the environment before automation touches it.

**None of the infra files have been validated against a live subscription or run
through a Bicep compiler** — there's no Azure CLI available in the environment this
was built in. Run `az deployment group what-if` before applying either template for
real, and double-check current API versions against Microsoft Learn, especially for
the blob immutability policy resource, which is the piece I'm least confident about.

## What still needs a human decision before step 1

- **Resource group and region** for the shared Automation Account / Storage Account.
- **Evidence retention period** — `main.bicep` defaults to ~7 years (2555 days), a
  guess at a plausible SOC 2 retention window, not a number you told me. Confirm
  against your actual audit/retention requirement before deploying.
- **Which subscriptions** get the custom role assignment from `custom-role.bicep` —
  the default `assignableScope` is just the current subscription; change it to a
  management group if you're centralizing across more than one.

## Exit criteria (from the design doc) — check off as you go

- [ ] Toolkit runs reliably on schedule via Azure Automation.
- [ ] Structured evidence is generated on every run. *(Already true via Phase 1's
      evidence export — confirm it also lands in the new evidence Storage Account,
      not just the local `evidence/` folder Phase 1 defaults to.)*
- [ ] Baseline report exists (`Baseline-Report.ps1` output) and is reviewed by SOC +
      Platform Security — use the sign-off checklist at the bottom of the generated
      `Baseline_Summary_*.md`.
- [ ] At least the two example scripts' hardening pattern reviewed; a plan exists for
      the rest per `Hardening-Checklist.md` (particularly the 9 scripts feeding
      Phase 1's Auto categories — those are the ones already running unattended).

## What's deliberately NOT done automatically

- **No "real run" weekly schedule.** `Deploy-Phase0Automation.ps1` only registers the
  WhatIf weekly job. Adding a real weekly run for categories beyond what Phase 1
  already does daily is a decision to make after watching WhatIf output for a few
  cycles, not something to wire up blind.
- **Only 2 of 45 scripts hardened.** See `Hardening-Checklist.md` for why, and the
  priority order for the rest.
- **Immutability/WORM policy is a draft.** Verify the actual behavior (can it be
  extended later? what happens if you need to delete something during the retention
  window for a legitimate reason?) against current docs before you depend on it for
  an actual audit.
