param(
    [Parameter(Mandatory = $true)]
    [string]$SourceSchemaDir,
    [Parameter(Mandatory = $true)]
    [string]$DestinationSchemaDir,
    [string]$UserDataDir = ""
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path)
}

function Require-File([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing ${Description}: $Path"
    }
}

function Copy-RequiredFile([string]$Source, [string]$Destination, [string]$Description) {
    Require-File $Source $Description
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Copy-MobileSchemaAsJyut6ping3([string]$Source, [string]$Destination) {
    Require-File $Source "jyut6ping3_mobile schema"
    $Schema = Get-Content -Raw -LiteralPath $Source
    $Schema = $Schema -replace 'schema_id:\s*jyut6ping3_mobile', 'schema_id: jyut6ping3'
    Set-Content -LiteralPath $Destination -Encoding UTF8 -Value $Schema
}

$SourceSchemaDir = Resolve-FullPath $SourceSchemaDir
$DestinationSchemaDir = Resolve-FullPath $DestinationSchemaDir
$SourceBuildDir = Join-Path $SourceSchemaDir "build"
$DestinationBuildDir = Join-Path $DestinationSchemaDir "build"

if (-not (Test-Path -LiteralPath $SourceSchemaDir -PathType Container)) {
    throw "missing source schema directory: $SourceSchemaDir"
}

if ($SourceSchemaDir -ne $DestinationSchemaDir) {
    if (Test-Path -LiteralPath $DestinationSchemaDir) {
        Remove-Item -LiteralPath $DestinationSchemaDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force $DestinationSchemaDir | Out-Null
    Copy-Item -Path (Join-Path $SourceSchemaDir "*") -Destination $DestinationSchemaDir -Recurse -Force
}
else {
    New-Item -ItemType Directory -Force $DestinationSchemaDir | Out-Null
}
New-Item -ItemType Directory -Force $DestinationBuildDir | Out-Null

Copy-MobileSchemaAsJyut6ping3 `
    -Source (Join-Path $DestinationSchemaDir "jyut6ping3_mobile.schema.yaml") `
    -Destination (Join-Path $DestinationSchemaDir "jyut6ping3.schema.yaml")
Copy-MobileSchemaAsJyut6ping3 `
    -Source (Join-Path $DestinationBuildDir "jyut6ping3_mobile.schema.yaml") `
    -Destination (Join-Path $DestinationBuildDir "jyut6ping3.schema.yaml")

$Manifest = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    source_schema_dir = $SourceSchemaDir
    destination_schema_dir = $DestinationSchemaDir
    profile_schema_id = "jyut6ping3"
    runtime_schema_template = "jyut6ping3_mobile"
    prism_stem = "jyut6ping3_mobile"
    smoke_input = "ngohaig"
}
$Manifest | ConvertTo-Json | Out-File -LiteralPath (Join-Path $DestinationSchemaDir "yune-windows-product-data.json") -Encoding utf8

if (-not [string]::IsNullOrWhiteSpace($UserDataDir)) {
    $UserDataDir = Resolve-FullPath $UserDataDir
    $UserBuildDir = Join-Path $UserDataDir "build"
    New-Item -ItemType Directory -Force $UserBuildDir | Out-Null

    Copy-RequiredFile (Join-Path $DestinationBuildDir "default.yaml") `
        (Join-Path $UserBuildDir "default.yaml") `
        "prebuilt default config"
    Copy-RequiredFile (Join-Path $DestinationBuildDir "jyut6ping3.schema.yaml") `
        (Join-Path $UserBuildDir "jyut6ping3.schema.yaml") `
        "prebuilt jyut6ping3 schema"

    foreach ($FileName in @(
            "jyut6ping3.table.bin",
            "jyut6ping3.reverse.bin",
            "jyut6ping3_scolar.table.bin",
            "jyut6ping3_scolar.reverse.bin",
            "jyut6ping3_scolar.prism.bin",
            "luna_pinyin.table.bin",
            "luna_pinyin.reverse.bin",
            "luna_pinyin.prism.bin"
        )) {
        Copy-RequiredFile (Join-Path $DestinationSchemaDir $FileName) `
            (Join-Path $UserBuildDir $FileName) `
            "prebuilt $FileName"
    }

    Copy-RequiredFile (Join-Path $DestinationSchemaDir "jyut6ping3_mobile.prism.bin") `
        (Join-Path $UserBuildDir "jyut6ping3_mobile.prism.bin") `
        "prebuilt jyut6ping3_mobile.prism.bin"
    Copy-RequiredFile (Join-Path $DestinationSchemaDir "jyut6ping3_mobile.prism.bin") `
        (Join-Path $UserBuildDir "jyut6ping3.prism.bin") `
        "selected-schema prism fallback alias"
}

Write-Host "Prepared Yune Windows Yune product data: $DestinationSchemaDir"
