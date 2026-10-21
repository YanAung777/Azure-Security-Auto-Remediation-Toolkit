# Phase 3 — Progressive Autonomy + Human Interface

Sibling folder to `Phase1-SafeAutoRemediation` and `Phase2-IntelligenceLayer`. All default paths are relative to
each script's own location, so you can run any of them from any directory.

## How the pieces fit

```
Phase 2 run ──► matched finding, decision = Propose/Escalate
                    │  New-Phase3Proposal (live preview from Phase 1 -PreviewOnly, in the right subscription)
                    ▼
              Proposal (Pending) ──► Teams: "Approval needed ..."
                    │  Submit-Phase3Decision.ps1  (signed-in Azure identity; 2 different people for Escalate / ProdHighRisk)
                    ▼
              Approved ──► Invoke-Phase3ApprovedProposals.ps1 ──► Phase 1 -ApprovalId (re-checks scope, runs, tags, evidence)
                    │                                              └─ new resource appeared since approval? → Stale, nothing runs
                    └─ Rejected → reason code → state\Feedback.jsonl (learning store)
```

| Work item (design doc) | Delivered |
|---|---|
| 2 Approval gates | `Submit-Phase3Decision.ps1`, `Invoke-Phase3ApprovedProposals.ps1`, proposal store |
| 3 Natural-language interface | `Invoke-Phase3NaturalLanguage.ps1` + `Test-Phase3Intent` (validator) |
| 4 Attack-path boost | Already in Phase 2 (priority score; Propose → Escalate). Not rebuilt. |
| 5 Override / feedback capture | Rejections require a reason code; written to `Feedback.jsonl` |
| 6 Rollback | `New-Phase3UndoScript.ps1` — reverse script from recorded before-state |
| 7 SOC dashboard | `New-Phase3Dashboard.ps1` → self-contained `SOC-Dashboard.html` |
| 1 Expand Autonomy Matrix | **Not expanded.** `Test-Phase3PromotionCriteria.ps1` reports whether a category has earned a review. See below. |

## Design decisions worth knowing

- **Approval is per (script, subscription), not per resource.** The Fix scripts act on every non-compliant resource in the
  subscription and can't be narrowed. So there is no "approve with modifications". At execution Phase 1 checks that
  everything it would change is in the set approvers saw; if not, the proposal goes **Stale** and nothing runs.
- **Approvals lapse** after 24 h and proposals after 72 h (`phase3-config.json`).
- **Natural language can narrow or lower autonomy, never raise it.** The model's JSON is untrusted; the validator refuses
  `forceAuto`, `autonomy: Auto`, unknown categories, severity filters in Run mode, bad modes. "Run" only executes what the
  matrix already marks Auto and raises proposals for the rest. Nothing happens without `-Execute`.
- **Rollback is partial on purpose.** Generated for Storage and Function/Web App settings. Key Vault soft delete / purge
  protection are irreversible; Key Vault RBAC and Defender are emitted as MANUAL lines. Reverting a security fix is a
  regression — the generated script is preview-only unless `-Execute`.
- **Matrix expansion is a human change-control decision.** I did not flip any category. There is no evidence yet to
  justify it. `Test-Phase3PromotionCriteria.ps1` applies: ≥20 actions, ≥98 % success, 0 rejections, 0 recurrences in 30 days,
  per environment tier (NonProd success says nothing about ProdHighRisk).

## Fixes to earlier phases (found while testing this one)

| Where | Problem | Fix |
|---|---|---|
| Phase 2 | Called Phase 1 with an environment override but never switched subscription context — a NonProd decision could have applied to whichever subscription was active | Switches context to the finding's subscription, no override, restores afterwards, one trigger per (subscription, category) |
| Phase 2 | "Recurring" meant "seen in the last 7 days", so every still-open finding scored as recurring from day 2 | Recurring = resolved, then reappeared. Store now holds first-seen / resolved / reappeared (also feeds time-to-remediate) |
| Phase 1 | WhatIf previews were empty (toolkit scripts use `Write-Host`; `2>&1` doesn't capture it) | `*>&1` |
| All | Default paths were relative to the caller's working directory | Relative to the script |
| Phase 2 | `Build-Phase2FindingTypeMap.ps1` had a syntax error (would not load) | Fixed |
| Phase 1 | New: `-ApprovalId/-ApprovedScript/-ApprovedResourceIds`, `-PreviewOnly`, `-PassThru` | — |

## Verification — and its limits

PowerShell 7.4 was available in the build environment, so unlike Phases 0–2 this was actually executed:
every `.ps1/.psm1` parses; **36 checks** exercise the approval flow end-to-end (preview writes nothing, four-eyes, same-person
refusal, kill switch, stale detection leaves everything untouched, execute + tag + evidence, reject-needs-reason,
undo script, 9 intent-validator cases, promotion report, dashboard) and **12 checks** exercise Phase 2 (context switching,
recurrence semantics, proposal creation). **All against mocked Azure cmdlets.** Not verified: any real Azure call, Defender/
Resource Graph output shapes, Teams webhooks, Azure OpenAI (no key — verify `azureOpenAIApiVersion`), the Bicep, or a Hybrid Worker.

## Not done / needs your decision

- **One-click approve link.** The design doc's Logic App / Power Automate link isn't built; approval is a CLI command.
  Needs a Logic App with an authenticated approver identity.
- **Approvals are local files** — editable by anyone with folder write access. Fine for a pilot. For audit, authenticate
  approvers server-side or ship `state\` to the immutable evidence store.
- **Dashboard limits:** time-to-remediate is cluster-level and only observed at Phase 2 run cadence; it includes human fixes.
  "Open by decision" means eligible, not already fixed.
- **Hybrid Worker required** for scheduled use (see Phase 0 README correction).
