param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
if (-not (Test-Path -LiteralPath $SupportScript)) {
    throw "missing live smoke support script: $SupportScript"
}

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
$FunctionMatch = [regex]::Match(
    $SupportSource,
    '(?s)function Invoke-YuneWindowsBoundedProcess \{(?<body>.*?)\r?\n\}\r?\n\r?\nfunction Invoke-YuneWindowsProfileTool')
if (-not $FunctionMatch.Success) {
    throw "could not locate Invoke-YuneWindowsBoundedProcess body"
}

$Body = $FunctionMatch.Groups["body"].Value
foreach ($Required in @(
        'StandardOutput.ReadToEndAsync()',
        'StandardError.ReadToEndAsync()',
        '$StdoutTask',
        '$StderrTask'
    )) {
    if ($Body -notmatch [regex]::Escape($Required)) {
        throw "Invoke-YuneWindowsBoundedProcess must drain redirected output asynchronously before waiting for exit: $Required."
    }
}

$StdoutAsyncIndex = $Body.IndexOf('StandardOutput.ReadToEndAsync()', [System.StringComparison]::Ordinal)
$StderrAsyncIndex = $Body.IndexOf('StandardError.ReadToEndAsync()', [System.StringComparison]::Ordinal)
$WaitIndex = $Body.IndexOf('WaitForExit($TimeoutSeconds * 1000)', [System.StringComparison]::Ordinal)
if ($WaitIndex -lt 0) {
    throw "Invoke-YuneWindowsBoundedProcess must still enforce its timeout with WaitForExit."
}
if ($StdoutAsyncIndex -gt $WaitIndex -or $StderrAsyncIndex -gt $WaitIndex) {
    throw "Invoke-YuneWindowsBoundedProcess must start stdout/stderr async reads before waiting for exit."
}

if ($Body -match 'StandardOutput\.ReadToEnd\(\)' -or
    $Body -match 'StandardError\.ReadToEnd\(\)') {
    throw "Invoke-YuneWindowsBoundedProcess must not wait for exit and then synchronously drain redirected streams."
}

. $SupportScript

$PowerShellExe = Join-Path $PSHOME "powershell.exe"
$LargeOutputCommand = @'
[Console]::Out.Write(("o" * 262144))
[Console]::Error.Write(("e" * 262144))
exit 0
'@

$Result = Invoke-YuneWindowsBoundedProcess `
    -FilePath $PowerShellExe `
    -ArgumentList @("-NoProfile", "-Command", $LargeOutputCommand) `
    -TimeoutSeconds 10 `
    -Operation "bounded helper large redirected output smoke"

if ($Result.exit_code -ne 0) {
    throw "large redirected output smoke returned exit code $($Result.exit_code)"
}
if ($Result.stdout.Length -lt 262144) {
    throw "large redirected output smoke lost stdout bytes: $($Result.stdout.Length)"
}
if ($Result.stderr.Length -lt 262144) {
    throw "large redirected output smoke lost stderr bytes: $($Result.stderr.Length)"
}

Write-Host "Bounded process helper drains redirected output asynchronously without false timeouts."
