param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $RepoRoot "tools\live-smoke-support.ps1")

$SyntheticLines = @(
    "time=2026-06-27T00:00:00Z event=key_down key=ngohaig",
    "time=2026-06-27T00:00:01Z event=candidate_update candidate_count=3 text=ngohaig",
    "time=2026-06-27T00:00:02Z event=commit_text text=我係個",
    "time=2026-06-27T00:00:03Z event=candidate_update candidate_count=2",
    "time=2026-06-27T00:00:04Z message=ignored"
)

$Summary = Get-StructuralEventSummary -Lines $SyntheticLines
if ($Summary -ne "candidate_update=2, commit_text=1, key_down=1") {
    throw "unexpected structural event summary: $Summary"
}

foreach ($Forbidden in @("ngohaig", "我係個", "candidate_count")) {
    if ($Summary -match [regex]::Escape($Forbidden)) {
        throw "structural event summary must not include raw log content: $Forbidden"
    }
}
if ($Summary -match '(^|[,\s])text=') {
    throw "structural event summary must not include raw text fields."
}

$EmptySummary = Get-StructuralEventSummary -Lines @()
if ($EmptySummary -ne "none") {
    throw "empty structural event summary should be none, got: $EmptySummary"
}

foreach ($ScriptName in @("run-notepad-smoke.ps1", "run-chromium-smoke.ps1")) {
    $Source = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\$ScriptName")
    if ($Source -notmatch [regex]::Escape("Structural event summary:")) {
        throw "$ScriptName must write the structural event summary to smoke results."
    }
    if ($Source -notmatch [regex]::Escape("Get-StructuralEventSummary")) {
        throw "$ScriptName must derive the structural event summary from new log lines."
    }
}

Write-Host "Live smoke structural event summaries report event counts without raw log content."
