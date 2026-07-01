param(
    [string]$YuneRoot = "C:\Users\laubonghaudoi\Documents\GitHub\yune"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$DevRepl = Join-Path $RepoRoot "tools\dev\dev-repl.ps1"
if (-not (Test-Path -LiteralPath $DevRepl -PathType Leaf)) {
    throw "missing dev REPL: $DevRepl"
}

$ScratchRoot = Join-Path $env:TEMP (
    "yune-windows\comment-hygiene-contract-{0}-{1}" -f
    $PID,
    [Guid]::NewGuid().ToString("N").Substring(0, 8))
$OutputPath = Join-Path $ScratchRoot "stdout.txt"
$ErrorPath = Join-Path $ScratchRoot "stderr.txt"
New-Item -Path $ScratchRoot -ItemType Directory -Force | Out-Null

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
        "ngohaig",
        "-Once"
    ) `
    -RedirectStandardOutput $OutputPath `
    -RedirectStandardError $ErrorPath `
    -WindowStyle Hidden `
    -PassThru

$Deadline = [DateTime]::UtcNow.AddMinutes(5)
while (-not $Process.HasExited -and [DateTime]::UtcNow -lt $Deadline) {
    Start-Sleep -Milliseconds 200
    $Process.Refresh()
}
if (-not $Process.HasExited) {
    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
    throw "dev-repl timed out while checking comment hygiene"
}

$Output = if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
    Get-Content -Raw -LiteralPath $OutputPath
} else {
    ""
}
$ErrorOutput = if (Test-Path -LiteralPath $ErrorPath -PathType Leaf) {
    Get-Content -Raw -LiteralPath $ErrorPath
} else {
    ""
}
$Text = $Output
if ($Process.ExitCode -ne 0 -and
    ($Text -notmatch '(?m)^candidate_count:\s+\d+$' -or
     $Text -notmatch '(?m)^\[1\]\s+.+\tngo5hai6go3\s*$')) {
    throw "dev-repl failed while checking comment hygiene: $Output`n$ErrorOutput"
}

if ($Text -match '(?m)\t\s*(\\f|\\r|[\x00-\x1f])*1,[^,\r\n]+,[a-z]+[1-6][a-z0-9'']*') {
    throw "server candidate comments leaked raw jyut6ping3 CSV data: $Text"
}
if ($Text -notmatch '(?m)^\[1\]\s+.+\tngo5hai6go3\s*$') {
    throw "server candidate comments should expose clean jyutping for ngohaig first candidate. Output: $Text"
}

Write-Host "Server candidate comments expose clean jyutping without raw CSV leakage."
