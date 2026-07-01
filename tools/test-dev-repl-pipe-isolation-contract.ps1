param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$DevRepl = Join-Path $RepoRoot "tools\dev\dev-repl.ps1"
if (-not (Test-Path -LiteralPath $DevRepl -PathType Leaf)) {
    throw "missing dev REPL: $DevRepl"
}

$Source = Get-Content -Raw -LiteralPath $DevRepl
if ($Source -match '\[string\]\$PipeName\s*=\s*"\\\\\.\\pipe\\yune-windows-ime-dev"') {
    throw "dev-repl default pipe must be unique per run; keep fixed pipe only as an explicit override"
}
if ($Source -notmatch 'New-YuneWindowsDevReplPipeName') {
    throw "dev-repl should generate a unique default pipe name"
}

$RunRoot = Join-Path $env:TEMP (
    "yune-windows\dev-repl-isolation-contract-{0}-{1}" -f
    $PID,
    [Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -Path $RunRoot -ItemType Directory -Force | Out-Null

function Start-DevReplIsolationRun {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$InputText
    )

    $ScratchRoot = Join-Path $RunRoot $Name
    $OutputPath = Join-Path $RunRoot "$Name.out.txt"
    $ErrorPath = Join-Path $RunRoot "$Name.err.txt"
    $Process = Start-Process `
        -FilePath "powershell" `
        -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $DevRepl,
            "-YuneRoot",
            $YuneRoot,
            "-ScratchRoot",
            $ScratchRoot,
            "-InputText",
            $InputText,
            "-Once"
        ) `
        -RedirectStandardOutput $OutputPath `
        -RedirectStandardError $ErrorPath `
        -WindowStyle Hidden `
        -PassThru
    return [pscustomobject]@{
        name = $Name
        process = $Process
        output_path = $OutputPath
        error_path = $ErrorPath
        scratch_root = $ScratchRoot
    }
}

$Runs = @(
    (Start-DevReplIsolationRun -Name "first" -InputText "ngohaig"),
    (Start-DevReplIsolationRun -Name "second" -InputText "ngohaig")
)

$Deadline = [DateTime]::UtcNow.AddMinutes(5)
foreach ($Run in $Runs) {
    while (-not $Run.process.HasExited -and [DateTime]::UtcNow -lt $Deadline) {
        Start-Sleep -Milliseconds 200
        $Run.process.Refresh()
    }
    if (-not $Run.process.HasExited) {
        Stop-Process -Id $Run.process.Id -Force -ErrorAction SilentlyContinue
        throw "dev-repl isolation run timed out: $($Run.name)"
    }
}

$SeenPipes = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase)
foreach ($Run in $Runs) {
    $Output = if (Test-Path -LiteralPath $Run.output_path -PathType Leaf) {
        Get-Content -Raw -LiteralPath $Run.output_path
    } else {
        ""
    }
    $ErrorOutput = if (Test-Path -LiteralPath $Run.error_path -PathType Leaf) {
        Get-Content -Raw -LiteralPath $Run.error_path
    } else {
        ""
    }
    $Combined = "$Output`n$ErrorOutput"
    if ($Run.process.ExitCode -ne 0 -and
        ($Combined -notmatch '(?m)^Started dev server PID \d+ on (?<pipe>.+)$' -or
         $Combined -notmatch '(?m)^candidate_count:\s+30$')) {
        throw "dev-repl isolation run failed: $($Run.name)`n$Combined"
    }
    if ($Combined -notmatch '(?m)^Started dev server PID \d+ on (?<pipe>.+)$') {
        throw "dev-repl isolation run did not report its pipe: $($Run.name)`n$Combined"
    }
    $Pipe = $Matches["pipe"].Trim()
    if (-not $SeenPipes.Add($Pipe)) {
        throw "dev-repl isolation runs reused pipe $Pipe"
    }
    if ($Combined -notmatch '(?m)^candidate_count:\s+30$') {
        throw "dev-repl isolation run did not return candidates: $($Run.name)`n$Combined"
    }
}

$Leftover = @(Get-Process -Name "YuneWindowsServer" -ErrorAction SilentlyContinue |
    Where-Object {
        $Path = ""
        try {
            $Path = [string]$_.Path
        }
        catch {
        }
        -not [string]::IsNullOrWhiteSpace($Path) -and
            $Path.StartsWith($RunRoot, [System.StringComparison]::OrdinalIgnoreCase)
    })
if ($Leftover.Count -gt 0) {
    throw "dev-repl isolation left scratch server process(es): $($Leftover.Id -join ', ')"
}

Write-Host "dev-repl default one-shot runs use isolated pipes and leave no scratch servers."
