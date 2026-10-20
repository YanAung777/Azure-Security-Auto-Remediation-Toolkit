# Phase 0 — Script Hardening Checklist

I hand-retrofitted 2 of the toolkit's 45 `Fix-*.ps1` scripts as worked examples
(`Fix-RemoveGuestOwnerAccounts.ps1`, `Fix-EnableSQLServerAuditing.ps1`). I did not
attempt all 45 — some reasons why, and what's involved in doing the rest.

## Why not all 45 in one pass

- I can't test any of them against a real Azure subscription in this environment, and
  mechanically rewriting 43 more scripts I can't run is exactly how you'd introduce a
  bug into a script you currently trust. Two hand-reviewed examples demonstrate the
  pattern; the rest should go through the same review a person actually does, one at a
  time, ideally with a non-prod test pass per script before it replaces the original.
- The scripts aren't uniform. I already found three different shapes in a 3-script
  sample: one script that already has try/catch (`Fix-NSGRestrictAllPorts.ps1`), two
  that have none. Applying one mechanical find-and-replace across all 45 risks being
  wrong for the ones that already handle errors differently.

## What "hardened" means here (from the two examples)

1. Import `Phase0-Common.psm1`, add a `-LogFile` parameter with a timestamped default.
2. Replace `-ErrorAction SilentlyContinue` on the actual remediation call with
   `-ErrorAction Stop` inside `Invoke-Phase0SafeAction` — silently-continue was hiding
   real failures as if they were successes.
3. Wrap the per-resource write action (not the whole script, just the mutating call)
   in `Invoke-Phase0SafeAction -ResourceName <name> -Action { ... }`.
4. Collect results into an array and print a summary count at the end
   (Success/Failed/WhatIf/AlreadyCompliant as applicable).
5. Leave the actual remediation logic — which properties get set, in what order —
   completely untouched. Hardening changes error handling and logging, never behavior.

## Suggested order for the remaining ~43

Prioritize by what's already scheduled to run unattended, not alphabetically:

1. **Any script feeding Phase 1's Auto categories first** — Storage (3), KeyVault (3),
   AppServices (2), Defender (1) — 9 scripts. These already run without a human in the
   loop for non-prod per the Phase 1 build, so they should be hardened before anything
   else. Quick audit: none of the 4 categories' scripts had try/catch when I checked
   them while building Phase 1 — they work, but a single resource erroring mid-loop
   currently stops the whole category's run for every resource after it.
2. **Identity scripts** (`Fix-RemoveGuestOwnerAccounts.ps1` and its siblings —
   `Fix-RemoveGuestReadAccounts.ps1`, `Fix-RemoveGuestWriteAccounts.ps1`,
   `Fix-RemoveDisabledOwnerAccounts.ps1`, `Fix-RemoveDisabledReadWriteAccounts.ps1`,
   `Fix-RemoveInactiveIdentitiesPermissions.ps1`) — these mutate access, a failed
   attempt silently swallowed is the worst category to get this wrong in.
3. Everything else, as it comes up for review or gets promoted beyond Propose in the
   Autonomy Matrix — a script that stays at Propose forever is lower urgency to harden
   than one being considered for Auto.

## Mechanical steps per script (once you're ready to do one)

1. Copy the original, don't edit in place until reviewed.
2. Add the `-LogFile` param and `Import-Module ...\Phase0-Common.psm1`.
3. Find the mutating cmdlet call(s) inside the `foreach` loop (usually one `Set-Az*`
   or `Remove-Az*` per script).
4. Wrap that call in `Invoke-Phase0SafeAction`, remove any
   `-ErrorAction SilentlyContinue` on it.
5. Replace `Write-Host` calls with `Write-Phase0Log ... $LogFile`.
6. Add the summary block at the end.
7. Diff against the original — the only lines that should change are error handling
   and logging, never the parameters passed to the Azure cmdlet.
