param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($OutputDir -eq "") {
    $OutputDir = Join-Path $env:TEMP "yune-windows\m01-audit-engine-boundary-test"
}
if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$EvidenceRoot = Join-Path $OutputDir "evidence"
$SourceRoot = Join-Path $OutputDir "source"
New-Item -ItemType Directory -Force $EvidenceRoot | Out-Null
New-Item -ItemType Directory -Force (Join-Path $SourceRoot "src") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $SourceRoot "tools") | Out-Null

function Invoke-TestAudit([string]$Name) {
    $JsonPath = Join-Path $OutputDir "$Name.json"
    $MarkdownPath = Join-Path $OutputDir "$Name.md"
    & (Join-Path $RepoRoot "tools\audit-m01-closeout.ps1") `
        -EvidenceRoot $EvidenceRoot `
        -SourceRoot $SourceRoot `
        -JsonPath $JsonPath `
        -MarkdownPath $MarkdownPath | Out-Null
    return Get-Content -Raw -LiteralPath $JsonPath | ConvertFrom-Json
}

function Get-EngineBoundaryGate([object]$Audit) {
    $Gate = $Audit.gates | Where-Object { $_.id -eq "engine-boundary" } | Select-Object -First 1
    if (-not $Gate) {
        throw "audit did not emit engine-boundary gate"
    }
    return $Gate
}

"void StartFallback() { LoadLibraryW(L`"librime.dll`"); }" |
    Out-File -LiteralPath (Join-Path $SourceRoot "src\bad_librime_fallback.cpp") -Encoding utf8

$FallbackGate = Get-EngineBoundaryGate (Invoke-TestAudit "librime-fallback")
if ($FallbackGate.status -ne "missing") {
    throw "audit should reject implementation sources with librime fallback markers, got $($FallbackGate.status)"
}

Remove-Item -LiteralPath (Join-Path $SourceRoot "src\bad_librime_fallback.cpp") -Force
"auto api = rime_get_api(); auto field = YuneWindowsDefaultAbiField;" |
    Out-File -LiteralPath (Join-Path $SourceRoot "src\bad_default_abi_widening.cpp") -Encoding utf8

$AbiGate = Get-EngineBoundaryGate (Invoke-TestAudit "default-abi-widening")
if ($AbiGate.status -ne "missing") {
    throw "audit should reject implementation sources that suggest YuneWindows fields on the default ABI, got $($AbiGate.status)"
}

Remove-Item -LiteralPath (Join-Path $SourceRoot "src\bad_default_abi_widening.cpp") -Force
@'
auto profile_api = GetProcAddress(library, "rime_get_yune_windows_profile_api");
if (!profile_api) {
    return 1;
}
'@ | Out-File -LiteralPath (Join-Path $SourceRoot "src\good_profile_api.cpp") -Encoding utf8

$CleanGate = Get-EngineBoundaryGate (Invoke-TestAudit "clean-boundary")
if ($CleanGate.status -ne "complete") {
    throw "audit should accept clean Yune profile API usage with no librime fallback/default ABI widening, got $($CleanGate.status)"
}

Write-Host "Closeout audit enforces the Yune engine boundary on implementation sources."
