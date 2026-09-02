# Detailed Design & Phase Build Order  
## AI-Assisted Azure Security Auto-Remediation System

**Document Version:** 1.0  
**Date:** 2026-09-02  
**Based on:** Azure Security Auto-Remediation Toolkit + Design Thinking concepts  
**Audience:** Cloud Security Platform Engineering, SOC Leadership, GRC/Compliance  

---

## 1. Purpose & Scope

This document provides a **detailed technical design** and **phased build order** to evolve the existing Azure Security Auto-Remediation Toolkit into an intelligent, closed-loop system.  

**Primary goals:**
- Reduce SOC cognitive load from repeated configuration findings.
- Enable progressive autonomy with strong guardrails.
- Generate continuous, auditor-grade SOC 2 evidence automatically.
- Keep the existing battle-tested PowerShell scripts as the reliable execution core.

**Out of scope for this design:** Full custom agent platform rewrite, multi-cloud expansion beyond Azure, or replacing Microsoft Defender for Cloud / Azure Policy.

---

## 2. Target Architecture (End State)

```
┌────────────────────────────────────────────────────────────────────────────────────┐
│                           AI-ASSISTED REMEDIATION PLATFORM                         │
├────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                    │
│  ┌──────────────────┐   ┌──────────────────────┐   ┌────────────────────────────┐  │
│  │ Signal Sources   │──▶│ Intelligence Layer   │──▶│ Decision & Autonomy Engine │  │
│  │                  │   │                      │   │                            │  │
│  │ • Defender Recs  │   │ • Clustering         │   │ • Autonomy Matrix          │  │
│  │ • Policy NonComp │   │ • Risk Scoring       │   │ • Auto / Propose / Escalate│  │
│  │ • Activity Logs  │   │ • Ownership Enrich   │   │ • WhatIf + Approval Gates  │  │
│  │ • Toolkit History│   │ • Recurrence Detect  │   │                            │  │
│  └──────────────────┘   └──────────────────────┘   └─────────────┬──────────────┘  │
│                                                                   │                │
│                                                                   ▼                │
│  ┌──────────────────────────────────────────────────────────────────────────────┐  │
│  │                        Execution Layer (Existing Toolkit)                    │  │
│  │  Run-AllAutoFix.ps1  |  Policy Remediation Scripts  |  Individual Fix-*.ps1  │  │
│  │  Azure Automation Runbooks  |  Managed Identity  |  Key Vault                │  │
│  └──────────────────────────────────────────────────────────────────────────────┘  │
│                                                                   │                │
│                                                                   ▼                │
│  ┌──────────────────────────────────────────────────────────────────────────────┐  │
│  │                     Evidence & Learning Layer                                │  │
│  │  Structured Logs → Log Analytics / Immutable Blob                            │  │
│  │  SOC 2 Evidence Packages  |  Metrics Dashboard  |  Feedback to Intelligence  │  │
│  └──────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                    │
└────────────────────────────────────────────────────────────────────────────────────┘
```

**Core principle:** The existing toolkit remains the **trusted execution engine**. New components sit *around* it (intelligence in front, evidence behind).

---

## 3. Detailed Component Design

### 3.1 Signal Sources (Phase 0–1)

| Source | How Consumed | Frequency | Notes |
|--------|--------------|-----------|-------|
| Microsoft Defender for Cloud Recommendations | Azure Resource Graph + REST / PowerShell | Daily + on-demand | Primary trigger for auto-remediation candidates |
| Azure Policy Non-Compliance | Existing `Export-NonCompliantResources*` scripts + ARG | Daily | Feeds severity-based remediation |
| Azure Activity Log / Resource Changes | Diagnostic settings → Log Analytics | Near real-time | Detects drift after remediation |
| Toolkit Execution History | CSV/Log files + Log Analytics | Continuous | Enables recurrence detection |

### 3.2 Intelligence Layer (Phases 2–3)

**Key capabilities to build:**

1. **Finding Normalizer**  
   - Normalize Defender recommendation IDs, Policy definition IDs, and toolkit script names into a common “Finding Type” taxonomy.

2. **Clustering & Noise Suppression**  
   - Group identical findings across subscriptions/RGs.  
   - Track “first seen” vs “recurring”.  
   - Suppress or auto-queue only the first occurrence of a known pattern within a time window (e.g., 7 days).

3. **Context Enrichment**  
   - Resource tags → Owner, Environment, Criticality, Application.  
   - CMDB / Service Catalog lookup (optional integration).  
   - Recent change actors from Activity Log.

4. **Risk / Priority Scoring**  
   - Simple weighted score initially: Severity (Defender) + Environment (Prod > Non-Prod) + Attack Path presence + Recurrence count.  
   - Later: integrate Defender attack-path analysis.

5. **Recurrence Detector**  
   - After a successful Fix- script run, monitor the same resource for the same finding reappearing within X days.  
   - Flag as “drift” and raise priority or create ticket.

### 3.3 Decision & Autonomy Engine (Phases 1–3)

**Autonomy Matrix** (example – must be customized per organization):

| Category                  | Non-Prod | Prod (Low Risk) | Prod (High Risk / Critical) | Notes |
|---------------------------|----------|-----------------|-----------------------------|-------|
| Storage (TLS, HTTPS, Public Blob) | Auto    | Auto            | Propose + Notify            | Very safe |
| Key Vault Soft Delete / Purge | Auto    | Auto            | Auto                        | Safe |
| Defender Plan Enablement  | Auto     | Propose         | Escalate                    | Cost impact |
| Identity (remove disabled/guest) | Propose | Propose         | Escalate                    | Needs review |
| NSG / Network restrictions | Propose  | Escalate        | Escalate                    | High blast radius |
| SQL Firewall / Auditing   | Propose  | Propose         | Escalate                    | Business impact |

**Decision outcomes:**
- **Auto** → Run with `-WhatIf` first, then execute under managed identity, log evidence.
- **Propose** → Generate remediation plan + create ITSM ticket (ServiceNow/Jira) with pre-filled evidence + WhatIf output.
- **Escalate** → Create high-priority ticket + optional Teams/email notification to on-call or security owner.

### 3.4 Execution Layer (Existing + Light Extensions)

- Keep all current `Fix-*.ps1` and Policy scripts.
- Enhance `Run-AllAutoFix.ps1`:
  - New parameters: `-AutonomyLevel`, `-Categories`, `-EvidenceOutputPath`, `-DryRunOnly`.
  - Automatic structured JSON evidence export after every run.
  - Resource tagging (`remediated-by`, `remediated-at`, `script-version`).
- Prefer **Azure Automation** with System-assigned Managed Identity (least privilege) over long-lived service principals where possible.
- Support both scheduled runs and event-driven triggers (Logic App / Event Grid on new Critical recommendations).

### 3.5 Evidence & Learning Layer (Phases 0–4)

**Evidence Package structure (JSON example):**

```json
{
  "runId": "guid",
  "timestampUtc": "2026-09-02T02:00:00Z",
  "triggeredBy": "Scheduled | Manual | RecommendationId",
  "scope": { "managementGroup": "...", "subscriptions": [...] },
  "autonomyLevel": "Level1",
  "scriptsExecuted": [
    {
      "script": "Fix-StorageAccountTLS.ps1",
      "status": "Success",
      "durationSeconds": 12.4,
      "resourcesAffected": 7,
      "beforeState": {...},
      "afterState": {...},
      "whatIfPreview": "..."
    }
  ],
  "summary": {
    "success": 42,
    "failed": 1,
    "skipped": 3
  },
  "soc2Mapping": ["CC6.1", "CC6.6", "CC7.4"],
  "evidenceLocation": "https://..."
}
```

- Store in **immutable** Azure Blob (WORM) or Log Analytics with long retention.
- Monthly automated “Evidence Pack” generation for GRC tools / auditors.
- Metrics: Auto-remediation %, MTTR (posture), Recurrence rate, Human override rate.

---

## 4. Phase Build Order (Detailed)

### Phase 0 – Foundation & Baseline (1–2 weeks)

**Objective:** Make the existing toolkit production-ready for continuous use and establish measurement.

**Work items:**
1. Review and harden all existing scripts (parameter validation, error handling, logging consistency).
2. Implement Azure Automation Account + Managed Identity with least-privilege roles (Contributor + Security Admin at target MG/Sub scope, Key Vault Secrets User if needed).
3. Convert key scripts into Automation Runbooks (or use Hybrid Worker if preferred).
4. Create standard schedules:
   - Daily: Critical/High categories only (Storage, Key Vault, Defender).
   - Weekly: Full `Run-AllAutoFix.ps1` with `-WhatIf` first, then real run on approved categories.
5. Standardize output:
   - Always produce timestamped Log + Summary CSV.
   - New: Emit structured JSON evidence package to a central Storage Account / Log Analytics.
6. Baseline measurement:
   - Export current open Defender recommendations + Policy non-compliance.
   - Document current open findings by category and severity.
7. Create initial Autonomy Matrix document (even if everything is still “Propose”).

**Exit criteria:**
- Toolkit runs reliably on schedule via Azure Automation.
- Structured evidence is generated on every run.
- Baseline report exists and is reviewed by SOC + Platform Security.

**Deliverables:**
- Automation Account + Runbooks
- Evidence storage location + retention policy
- Baseline compliance report
- Initial Autonomy Matrix (v0.1)

---

### Phase 1 – Safe Auto-Remediation (2–4 weeks)

**Objective:** Turn on Level-1 autonomy for the safest, highest-volume findings so SOC stops seeing the same Storage/Key Vault noise.

**Work items:**
1. Finalize Autonomy Matrix for Phase 1 (Storage TLS/HTTPS/PublicBlob, Key Vault Soft-Delete/Purge/RBAC, Function App HTTPS/TLS, basic Defender plan enablement in non-prod).
2. Enhance `Run-AllAutoFix.ps1` (or create wrapper):
   - Respect Autonomy Matrix (Auto vs Propose).
   - Always execute `-WhatIf` and store preview.
   - On Auto success → tag resources + write evidence.
3. Implement simple notification:
   - On Auto success → optional Teams channel summary.
   - On failure or Propose → create ITSM ticket with evidence link.
4. Add basic recurrence tracking:
   - After successful fix, record resource + finding type + timestamp in Log Analytics or a small Azure Table.
5. Pilot in Non-Production first, then selected Production subscriptions.
6. Document rollback procedures for each Auto category.

**Exit criteria:**
- ≥ 70 % of Phase-1 category findings are auto-remediated without human intervention.
- Zero production incidents caused by auto-remediation.
- SOC ticket volume for those categories drops measurably.
- Full evidence trail exists for every auto action.

**Deliverables:**
- Updated master runner with autonomy support
- Phase-1 Autonomy Matrix (approved)
- Notification / ticket integration (basic)
- Recurrence tracking store
- Phase-1 success metrics dashboard (simple)

---

### Phase 2 – Intelligence Layer (Core) (4–6 weeks)

**Objective:** Stop treating every finding as equal. Introduce prioritization, clustering, ownership, and smarter triggering.

**Work items:**
1. **Finding Ingestion Service** (Azure Function or Automation Runbook + Logic App):
   - Query Defender for Cloud recommendations (Resource Graph preferred).
   - Query Policy non-compliance.
   - Normalize into common schema.
2. **Clustering Engine**:
   - Group by (FindingType + Subscription/RG pattern or exact resource type).
   - Detect “first occurrence” vs “recurring within window”.
3. **Context Enrichment**:
   - Pull tags (Owner, Environment, Criticality, App).
   - Optional: Activity Log last modifier.
4. **Priority Scoring** (simple rule-based first):
   - Score = f(Severity, Environment, IsRecurring, HasAttackPath, OwnerPresent).
5. **Decision Engine v1**:
   - Apply Autonomy Matrix + Priority Score → Auto / Propose / Escalate.
6. **Trigger model**:
   - Scheduled full scan remains.
   - Add event-driven path: new Critical recommendation → immediate evaluation.
7. Integrate with existing Execution Layer (call the right Fix- script or Policy remediation).
8. Expand evidence package to include priority score, cluster ID, ownership, and decision reason.

**Exit criteria:**
- Noise suppression is measurable (fewer identical tickets).
- Ownership is resolved for majority of findings.
- Decision engine correctly routes according to matrix.
- SOC sees primarily novel / high-priority items.

**Deliverables:**
- Finding Ingestion + Normalization
- Clustering + Recurrence service
- Context enrichment module
- Priority scoring + Decision Engine v1
- Updated evidence schema
- Operational runbook for the intelligence components

---

### Phase 3 – Progressive Autonomy + Human Interface (6–10 weeks)

**Objective:** Expand safe auto-remediation, add natural-language / guided interface, and tighten human oversight.

**Work items:**
1. Expand Autonomy Matrix (add more categories that have proven safe in Phase 1–2).
2. Implement approval gates for “Propose” items:
   - Ticket contains WhatIf output + one-click approve link (Logic App / Power Automate or custom).
   - Approved actions automatically execute the corresponding toolkit script.
3. Natural-language interface (optional but high value):
   - Azure OpenAI / Security Copilot style prompt: “Remediate all High Storage findings in Prod MG but leave Identity alone”.
   - Translates to category + scope + autonomy override for this run.
4. Attack-path awareness (if Defender attack paths available):
   - Boost priority of findings sitting on active attack paths.
5. Human override & feedback capture:
   - When a human rejects or modifies a proposed remediation, capture the reason → feed learning store.
6. Improve rollback / safety:
   - For selected scripts, capture before-state more completely and provide reverse script or Policy undo guidance.
7. SOC dashboard:
   - Open findings by decision type (Auto / Propose / Escalate)
   - Auto-remediation success rate
   - MTTR for posture issues
   - Recurrence rate trend

**Exit criteria:**
- Autonomy Level 2 operating in production for approved categories.
- Human approval path is smooth and audited.
- Natural-language interface (if built) is used by platform/SOC team.
- Clear metrics show reduced SOC time on configuration noise.

**Deliverables:**
- Expanded Autonomy Matrix + approval workflow
- Natural-language interface (MVP)
- Attack-path priority boost (if data available)
- Feedback capture mechanism
- Operational SOC dashboard

---

### Phase 4 – Full Closed-Loop + SOC 2 Evidence Factory (Ongoing / 8–12 weeks initial)

**Objective:** Make the system self-improving and turn evidence generation into a first-class, auditor-ready product.

**Work items:**
1. **Learning Loop**:
   - Analyze success/failure + human overrides.
   - Suggest Autonomy Matrix changes (e.g., “this script has 98 % success and zero overrides for 90 days → candidate for Auto”).
2. **SOC 2 Evidence Factory**:
   - Automated monthly (or on-demand) Evidence Pack generation.
   - Control mapping table maintained in code/config.
   - Immutable storage + retention aligned to audit period.
   - Export format suitable for common GRC tools (Vanta, Drata, Scytale, Hyperproof, etc.) or direct auditor portal.
3. **Advanced Observability**:
   - Full end-to-end tracing of a finding from detection → decision → execution → evidence.
   - Alerting on intelligence layer failures or high failure rates of specific scripts.
4. **Governance of the Remediation System itself**:
   - Change control process for Autonomy Matrix updates.
   - Regular review of managed identity permissions.
   - Periodic tabletop / audit simulation of the evidence pack.
5. **Optional advanced features**:
   - Integration with third-party CNAPP attack-path data.
   - Generation of new Fix- script drafts via LLM (human-reviewed before promotion).
   - Multi-subscription / multi-MG orchestration improvements.

**Exit criteria:**
- Evidence Pack can be generated and handed to auditor with minimal manual work.
- System demonstrates continuous improvement in auto rate and reduced recurrence.
- Formal governance process exists for the remediation platform.
- External or internal audit accepts the automated evidence approach.

**Deliverables:**
- Learning / recommendation engine for autonomy changes
- Fully automated SOC 2 Evidence Pack pipeline
- Governance documentation & runbooks
- Mature metrics & observability
- Optional advanced integrations

---

## 5. Cross-Cutting Concerns (Apply in Every Phase)

| Concern | Design Decision |
|---------|-----------------|
| **Identity & Privilege** | Prefer System-assigned Managed Identity on Automation Account / Functions. Least-privilege RBAC. No long-lived secrets in scripts. |
| **Safety** | Always run `-WhatIf` (or equivalent preview) before real change. Maintain rollback guidance. Start narrow (categories + environments). |
| **Auditability** | Every decision and action produces structured, timestamped, immutable evidence. |
| **Observability** | Central Log Analytics workspace. Alerts on failures, high recurrence, or intelligence component downtime. |
| **Change Management** | Autonomy Matrix changes require review/approval. Script updates follow normal code review. |
| **Cost** | Azure Automation free tier + consumption Functions are usually sufficient initially. Monitor Defender recommendation query volume. |
| **Testing** | Non-prod first. Synthetic findings for testing. Chaos-style tests for rollback. |

---

## 6. Team & Skills Recommendations

| Role | Phase Involvement | Key Responsibilities |
|------|-------------------|----------------------|
| Cloud Security / Platform Engineer | All phases | Script hardening, Automation, Identity, Execution layer |
| SOC Lead / Detection Engineer | Phase 0–3 | Autonomy Matrix definition, noise validation, dashboard needs |
| Automation / DevOps Engineer | Phase 0–2 | Azure Automation, Functions, Logic Apps, CI/CD for scripts |
| GRC / Compliance | Phase 0, 1, 4 | Evidence schema, control mapping, auditor communication |
| Optional: AI/ML Engineer | Phase 2–4 | Clustering quality, scoring models, natural-language interface |

**Recommended starting team size:** 1–2 platform engineers + SOC lead part-time + GRC reviewer.

---

## 7. Success Metrics by Phase

| Metric | Phase 0 | Phase 1 | Phase 2 | Phase 3 | Phase 4 |
|--------|---------|---------|---------|---------|---------|
| % of targeted findings auto-remediated | 0 % | ≥ 70 % (safe categories) | ≥ 60 % overall | ≥ 75 % overall | ≥ 80 % + improving |
| SOC tickets for configuration noise | Baseline | ↓ 40–60 % | Further ↓ | Minimal | Minimal |
| Mean Time to Remediate (posture) | Baseline | < 48–72 h | < 24–48 h | < 24 h | Continuous improvement |
| Evidence pack generation time | Manual | Semi-auto | Semi-auto | < 1 day | Minutes / on-demand |
| Human override / rejection rate | N/A | Track | < 15 % | < 10 % | Declining |
| Production incidents from auto-remediation | 0 | 0 | 0 | 0 | 0 |

---

## 8. Risk Register (Key Items)

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Auto-remediation causes outage | Medium | High | Strict Autonomy Matrix, WhatIf mandatory, Non-prod pilot, rollback plan |
| Over-automation hides real issues | Medium | Medium | Clear “novel vs recurring” distinction; SOC still sees Escalates |
| Privilege of Managed Identity too broad | Medium | High | Least privilege, regular access reviews, monitoring of identity activity |
| Evidence not accepted by auditor | Low–Medium | High | Early engagement with auditor, clear process documentation, immutable storage |
| Intelligence layer false prioritization | Medium | Medium | Start rule-based, human review of decisions, feedback loop |
| Script drift / unmaintained Fix- scripts | Medium | Medium | Version control, ownership, periodic review of script success rates |

---

## 9. Immediate Next Actions (Start This Week)

1. **Approve Phase 0 scope** and assign owners.
2. Stand up Azure Automation Account + Managed Identity in a dedicated management subscription/RG.
3. Run full baseline export of Defender recommendations + Policy non-compliance.
4. Draft Autonomy Matrix v0.1 with SOC + Platform Security.
5. Decide evidence storage location (immutable Blob recommended) and retention.
6. Schedule Phase 0 kick-off and success criteria review.

---

## 10. Document Control

- This design is intentionally **evolutionary**. Each phase delivers working value and creates the foundation for the next.
- The existing toolkit scripts remain the single source of truth for *how* to remediate. New code focuses on *when*, *whether*, and *how to prove* the remediation happened.
- Update this document at the end of each phase with actual outcomes, lessons learned, and any scope changes.

**End of Detailed Design & Phase Build Order**
