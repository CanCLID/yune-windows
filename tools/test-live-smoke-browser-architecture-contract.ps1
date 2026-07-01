param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $RepoRoot "tools\live-smoke-support.ps1")

$TempDir = Join-Path $env:TEMP "yune-windows\m01-browser-architecture-test"
if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Force $TempDir | Out-Null

function New-SyntheticPe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [UInt16]$Machine
    )

    $Bytes = [byte[]]::new(160)
    $Bytes[0] = [byte][char]'M'
    $Bytes[1] = [byte][char]'Z'
    $PeOffset = 0x80
    [BitConverter]::GetBytes([int]$PeOffset).CopyTo($Bytes, 0x3c)
    $Bytes[$PeOffset] = [byte][char]'P'
    $Bytes[$PeOffset + 1] = [byte][char]'E'
    $Bytes[$PeOffset + 2] = 0
    $Bytes[$PeOffset + 3] = 0
    [BitConverter]::GetBytes($Machine).CopyTo($Bytes, $PeOffset + 4)
    [System.IO.File]::WriteAllBytes($Path, $Bytes)
}

$X64Browser = Join-Path $TempDir "chrome-x64.exe"
$X86Browser = Join-Path $TempDir "chrome-x86.exe"
New-SyntheticPe -Path $X64Browser -Machine 0x8664
New-SyntheticPe -Path $X86Browser -Machine 0x014c

$X64Machine = Get-YuneWindowsPortableExecutableMachine -Path $X64Browser
if ($X64Machine -ne "x64") {
    throw "expected x64 PE machine, got $X64Machine"
}

$X86Machine = Get-YuneWindowsPortableExecutableMachine -Path $X86Browser
if ($X86Machine -ne "x86") {
    throw "expected x86 PE machine, got $X86Machine"
}

Assert-YuneWindowsChromiumBrowserArchitecture `
    -Path $X64Browser `
    -Source "synthetic x64 Chromium browser"

$X86Failure = ""
try {
    Assert-YuneWindowsChromiumBrowserArchitecture `
        -Path $X86Browser `
        -Source "synthetic x86 Chromium browser"
}
catch {
    $X86Failure = $_.Exception.Message
}
if ($X86Failure -eq "" -or $X86Failure -notmatch "x64") {
    throw "x86 Chromium browser path must be rejected for the current x64 TSF shell: $X86Failure"
}

if (-not (Test-YuneWindowsChromiumBrowserArchitecture -Path $X64Browser)) {
    throw "x64 Chromium browser path should be compatible."
}
if (Test-YuneWindowsChromiumBrowserArchitecture -Path $X86Browser) {
    throw "x86 Chromium browser path should not be compatible."
}

Write-Host "Live Chromium smoke rejects x86 browser paths for the current x64 TSF shell."
