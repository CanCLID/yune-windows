param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$SupportPath = Join-Path $RepoRoot "tools\live-smoke-support.ps1"
$Source = Get-Content -Raw -LiteralPath $SupportPath

if ($Source -match [regex]::Escape('Marshal]::SizeOf([YuneWindowsWindows.Input])')) {
    throw "SendInput helper must not pass a RuntimeType object to Marshal.SizeOf for YuneWindowsWindows.Input."
}
if ($Source -notmatch [regex]::Escape('$InputSize = [System.Runtime.InteropServices.Marshal]::SizeOf([YuneWindowsWindows.Input]::new())')) {
    throw "SendInput helper must compute YuneWindowsWindows.Input size from an instance before calling SendInput."
}
if ($Source -notmatch [regex]::Escape('SendInput([uint32]$Inputs.Length, $Inputs, $InputSize)')) {
    throw "SendInput helper must pass the instance-computed input size into SendInput."
}
foreach ($Required in @(
        'public struct MouseInput',
        'public struct HardwareInput',
        'public MouseInput mi',
        'public HardwareInput hi'
    )) {
    if ($Source -notmatch [regex]::Escape($Required)) {
        throw "SendInput interop must model the full INPUT union so cbSize matches Windows: $Required"
    }
}

. $SupportPath
Ensure-YuneWindowsForegroundWindowType
$InputSize = [System.Runtime.InteropServices.Marshal]::SizeOf([YuneWindowsWindows.Input]::new())
if ($InputSize -le 0) {
    throw "YuneWindowsWindows.Input marshaled size must be positive."
}
$ExpectedInputSize = if ([IntPtr]::Size -eq 8) { 40 } else { 28 }
if ($InputSize -ne $ExpectedInputSize) {
    throw "YuneWindowsWindows.Input marshaled size should be $ExpectedInputSize on this platform, got $InputSize."
}

Write-Host "SendInput helper computes YuneWindowsWindows.Input size from an instance."
