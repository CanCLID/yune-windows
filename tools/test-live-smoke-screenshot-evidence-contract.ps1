param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $RepoRoot "tools\live-smoke-support.ps1")

if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\p2-win01-screenshot-evidence-contract"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force $OutputDir | Out-Null

function New-TestPng {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [int]$Width = 640,
        [int]$Height = 360,
        [string]$Color = "White"
    )

    Add-Type -AssemblyName System.Drawing
    $Bitmap = [System.Drawing.Bitmap]::new($Width, $Height)
    $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
    try {
        $Graphics.Clear([System.Drawing.Color]::FromName($Color))
        $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $Graphics.Dispose()
        $Bitmap.Dispose()
    }
}

function Expect-Throw {
    param(
        [scriptblock]$Script,
        [string]$Reason
    )

    try {
        & $Script
    }
    catch {
        return
    }
    throw "expected failure: $Reason"
}

$CandidatePath = Join-Path $OutputDir "candidate.png"
$CommitPath = Join-Path $OutputDir "commit.png"
$TinyPath = Join-Path $OutputDir "tiny.png"
$PlaceholderPath = Join-Path $OutputDir "placeholder.png"

New-TestPng -Path $CandidatePath -Color "White"
New-TestPng -Path $CommitPath -Color "Black"
New-TestPng -Path $TinyPath -Width 1 -Height 1 -Color "Red"
[System.IO.File]::WriteAllBytes($PlaceholderPath, [byte[]](0x89, 0x50, 0x4e, 0x47))

Assert-DesktopScreenshotEvidence -Path $CandidatePath -Context "candidate screenshot"
Assert-DesktopScreenshotEvidence -Path $CommitPath -Context "commit screenshot"
Assert-DistinctDesktopScreenshots `
    -CandidatePath $CandidatePath `
    -CommitPath $CommitPath `
    -Context "app smoke"

Expect-Throw {
    Assert-DesktopScreenshotEvidence -Path $TinyPath -Context "tiny screenshot"
} "tiny screenshots must not count as live evidence"

Expect-Throw {
    Assert-DesktopScreenshotEvidence -Path $PlaceholderPath -Context "placeholder screenshot"
} "placeholder screenshot bytes must not count as live evidence"

Expect-Throw {
    Assert-DistinctDesktopScreenshots `
        -CandidatePath $CandidatePath `
        -CommitPath $CandidatePath `
        -Context "identical screenshot pair"
} "candidate and commit screenshots must differ"

foreach ($RelativePath in @("tools\run-notepad-smoke.ps1", "tools\run-chromium-smoke.ps1")) {
    $SourcePath = Join-Path $RepoRoot $RelativePath
    $Source = Get-Content -Raw -LiteralPath $SourcePath
    $Name = Split-Path -Leaf $SourcePath

    foreach ($Required in @(
            "Assert-DesktopScreenshotEvidence",
            "Assert-DistinctDesktopScreenshots",
            'Candidate/commit screenshots distinct:',
            '$CandidateCommitScreenshotsDistinct'
        )) {
        if ($Source -notmatch [regex]::Escape($Required)) {
            throw "$Name is missing screenshot evidence guard pattern: $Required"
        }
    }

    $PassPattern = '\$Pass\s*=\s*\$MatchesExpectedCommit\s+-and(?s:.*?)' +
        '\$CandidateScreenshotCaptured\s+-and\s*' +
        '\$CommitScreenshotCaptured\s+-and\s*' +
        '\$CandidateCommitScreenshotsDistinct\s+-and'
    if ($Source -notmatch $PassPattern) {
        throw "$Name must require distinct candidate/commit screenshots before reporting Pass: True."
    }
}

Write-Host "Live app-smoke screenshot evidence is validated before pass evidence is written."
