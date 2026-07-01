param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$EvidenceDir = Join-Path $RepoRoot "docs\evidence\m01\installer"
$Reports = @(
    @{ Name = "live"; Path = Join-Path $EvidenceDir "live-preflight.json" },
    @{ Name = "install"; Path = Join-Path $EvidenceDir "install-preflight.json" }
)

$MissingReports = @($Reports | Where-Object { -not (Test-Path -LiteralPath $_.Path) })
if ($MissingReports.Count -gt 0) {
    $SummaryPath = Join-Path $RepoRoot "docs\evidence\m01\summary.json"
    if (-not (Test-Path -LiteralPath $SummaryPath)) {
        throw "missing durable live preflight evidence and compact M01 summary"
    }
    $Summary = Get-Content -Raw -LiteralPath $SummaryPath | ConvertFrom-Json
    if (($Summary.status -ne "complete") -or
        ($Summary.evidence_policy -ne "compact-summary-only")) {
        throw "M01 summary must document complete compact-summary evidence when durable preflight artifacts are pruned"
    }
    if ("powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools\run-m01-live-smoke.ps1" -notin @($Summary.regeneration_commands)) {
        throw "M01 summary must document the live-smoke regeneration command"
    }
    Write-Host "Live/install preflight durable evidence is pruned; compact summary records the regeneration path."
    return
}

foreach ($Report in $Reports) {
    $Json = Get-Content -Raw -LiteralPath $Report.Path | ConvertFrom-Json
    if ($Json.machine_state_changed -ne $false) {
        throw "$($Report.Name) preflight must record machine_state_changed=false"
    }
    if ($Json.machine_state_checked -ne $true) {
        throw "$($Report.Name) preflight must record machine_state_checked=true"
    }
    if ($null -eq $Json.PSObject.Properties["machine_state_issues"]) {
        throw "$($Report.Name) preflight must include machine_state_issues"
    }
    if (@($Json.machine_state_issues).Count -ne @($Json.machine_state_issues | Select-Object -Unique).Count) {
        throw "$($Report.Name) preflight must not duplicate machine-state residue entries"
    }
    if ($null -eq $Json.PSObject.Properties["filesystem_leftovers"]) {
        throw "$($Report.Name) preflight must include filesystem_leftovers"
    }
    if (@($Json.filesystem_leftovers).Count -ne @($Json.filesystem_leftovers | Select-Object -Unique).Count) {
        throw "$($Report.Name) preflight must not duplicate filesystem leftover entries"
    }
    if ($Json.install_dir_exists -ne $false) {
        throw "$($Report.Name) preflight must record install_dir_exists=false for the durable fresh target"
    }
    if ((@($Json.machine_state_issues).Count -gt 0 -or @($Json.filesystem_leftovers).Count -gt 0) -and
        $Json.ready_for_live_smoke -ne $false) {
        throw "$($Report.Name) preflight must not report ready when residue is present"
    }
    if ($null -eq $Json.server_process_count) {
        throw "$($Report.Name) preflight must include server_process_count"
    }
    if ($Json.yune_runtime_exists -ne $true) {
        throw "$($Report.Name) preflight must find packaged Yune runtime"
    }
    if ($Json.yune_schema_exists -ne $true) {
        throw "$($Report.Name) preflight must find Yune schema data"
    }
    if ($null -eq $Json.is_administrator) {
        throw "$($Report.Name) preflight must include administrator state"
    }
    if ($null -eq $Json.ready_for_live_smoke) {
        throw "$($Report.Name) preflight must include ready_for_live_smoke"
    }
}

Write-Host "Durable live/install preflight evidence is present and non-mutating."
