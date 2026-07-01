param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportScript = Join-Path $RepoRoot "tools\dev\dev-support.ps1"
$ReplScript = Join-Path $RepoRoot "tools\dev\dev-repl.ps1"

foreach ($Path in @($SupportScript, $ReplScript)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing dev REPL state contract input: $Path"
    }
}

$SupportSource = Get-Content -Raw -LiteralPath $SupportScript
$ReplSource = Get-Content -Raw -LiteralPath $ReplScript

foreach ($Required in @(
        'Invoke-YuneWindowsDevServerRawRequest',
        '\[Parameter\(Mandatory = \$true\)\]\[string\]\$Payload'
    )) {
    if ($SupportSource -notmatch $Required) {
        throw "dev-support.ps1 is missing raw op request support: $Required"
    }
}

foreach ($Required in @(
        ':state',
        ':schemas',
        ':ascii',
        ':full-shape',
        ':standard',
        ':schema',
        'op=get-state',
        'op=list-schemas',
        'op=set-option',
        'op=select-schema',
        'output_standard'
    )) {
    if ($ReplSource -notmatch [regex]::Escape($Required)) {
        throw "dev-repl.ps1 is missing IME state command support: $Required"
    }
}

Write-Host "Dev REPL supports server-owned IME state op commands."
