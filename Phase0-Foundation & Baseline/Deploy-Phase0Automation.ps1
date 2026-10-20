<#
.SYNOPSIS
    Imports the Phase 1 orchestrator as an Automation Runbook and wires up the
    Daily/Weekly schedules the design doc's Phase 0 work item 4 calls for.

.DESCRIPTION
    Run this AFTER main.bicep and custom-role.bicep have both deployed successfully.
    This script does not deploy infrastructure -- it only imports runbook content and
    creates schedules against an Automation Account that already exists.

    NOT TESTED against a live Automation Account (no Azure connectivity in the
    environment this was authored in). Review each cmdlet call against current
    Az.Automation documentation before running -- parameter names on
    Register-AzAutomationScheduledRunbook in particular are easy to get subtly wrong.

.NOTES
    Schedule design per the doc:
      - Daily: Storage, KeyVault, Defender (the "Critical/High categories" it names)
      - Weekly: everything (-Category All), -WhatIf first, real run second
    AppServices is deliberately left off the daily schedule -- it's Propose-only in
    Prod per the Autonomy Matrix, so a daily Auto pass buys nothing for AppServices in
    Prod, and non-prod doesn't need daily cadence for something this low-risk.
#>

param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$AutomationAccountName,
    [string]$Phase1ScriptPath = "..\Phase1-SafeAutoRemediation\Invoke-Phase1AutoRemediation.ps1",
    [string]$DailyScheduleTime = "02:00",
    [string]$WeeklyScheduleTime = "03:00",
    [string]$WeeklyScheduleDay = "Sunday"
)

$ErrorActionPreference = "Stop"

function Import-Phase0Runbook {
    param([string]$RunbookName, [string]$Path)
    Write-Host "Importing runbook '$RunbookName'..." -ForegroundColor Cyan
    Import-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName `
        -Name $RunbookName -Path $Path -Type PowerShell -Force | Out-Null
    Publish-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName `
        -Name $RunbookName | Out-Null
    Write-Host "  Published." -ForegroundColor Green
}

# ---- Import the Phase 1 orchestrator once; schedules pass different -Category values ----
Import-Phase0Runbook -RunbookName "Invoke-Phase1AutoRemediation" -Path $Phase1ScriptPath

# ---- Daily schedule: Storage, KeyVault, Defender ----
$dailyStart = (Get-Date $DailyScheduleTime).AddDays(1) # first run tomorrow at the given time
New-AzAutomationSchedule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName `
    -Name "Phase0-Daily-CriticalCategories" -StartTime $dailyStart -DayInterval 1 | Out-Null

foreach ($category in @("Storage", "KeyVault", "Defender")) {
    Register-AzAutomationScheduledRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName `
        -RunbookName "Invoke-Phase1AutoRemediation" -ScheduleName "Phase0-Daily-CriticalCategories" `
        -Parameters @{ Category = $category } | Out-Null
}
Write-Host "Daily schedule created for Storage / KeyVault / Defender at $DailyScheduleTime." -ForegroundColor Green

# ---- Weekly schedule: full run, WhatIf first then real ----
$weeklyStart = (Get-Date $WeeklyScheduleTime).AddDays(7)
New-AzAutomationSchedule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName `
    -Name "Phase0-Weekly-FullRun" -StartTime $weeklyStart -WeekInterval 1 -DaysOfWeek $WeeklyScheduleDay | Out-Null

# Two runbook links against the same schedule: WhatIf preview first, then the real run.
# If your Automation account's job ordering doesn't guarantee the WhatIf job completes
# before the real one starts, split these into two schedules a few minutes apart instead.
Register-AzAutomationScheduledRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName `
    -RunbookName "Invoke-Phase1AutoRemediation" -ScheduleName "Phase0-Weekly-FullRun" `
    -Parameters @{ Category = "All"; WhatIf = $true } | Out-Null

Write-Host "Weekly schedule created (full run, WhatIf) for $WeeklyScheduleDay at $WeeklyScheduleTime." -ForegroundColor Green
Write-Host ""
Write-Host "Review the WhatIf job output for a few cycles before adding a second, non-WhatIf weekly job for the categories you're ready to trust." -ForegroundColor Yellow
