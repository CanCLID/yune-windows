param()

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$InstallerPath = Join-Path $RepoRoot "tools\install-yune-windows-ime.ps1"
$UninstallerPath = Join-Path $RepoRoot "tools\uninstall-yune-windows-ime.ps1"
foreach ($ScriptPath in @($InstallerPath, $UninstallerPath)) {
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "missing script: $ScriptPath"
    }
}

function Get-ScriptFunctionDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptSource,
        [Parameter(Mandatory = $true)]
        [string]$FunctionName
    )

    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $ScriptSource,
        [ref]$Tokens,
        [ref]$ParseErrors)
    if (@($ParseErrors).Count -gt 0) {
        throw "script parse errors prevented function import: $($ParseErrors -join '; ')"
    }

    $FunctionAst = $Ast.Find({
            param($Node)
            $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $Node.Name -eq $FunctionName
        }, $true)
    if ($null -eq $FunctionAst) {
        throw "script is missing function: $FunctionName"
    }

    return $FunctionAst.Extent.Text
}

function Assert-InstallDirResolverContract {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    $Source = Get-Content -Raw -LiteralPath $ScriptPath
    foreach ($Required in @(
            'function\s+Resolve-SafeInstallDir',
            '\$env:LOCALAPPDATA',
            'LocalAppData\\Yune',
            'Refusing unsafe install directory'
        )) {
        if ($Source -notmatch $Required) {
            throw "$ScriptPath install-dir resolver is missing required safety pattern: $Required"
        }
    }

    Invoke-Expression (Get-ScriptFunctionDefinition `
            -ScriptSource $Source `
            -FunctionName "Resolve-SafeInstallDir")

    $AllowedRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Yune"))
    $AllowedInstallDir = Join-Path $AllowedRoot "WindowsIme"
    $ResolvedAllowed = Resolve-SafeInstallDir -Path $AllowedInstallDir
    if (-not [string]::Equals(
            $ResolvedAllowed,
            [System.IO.Path]::GetFullPath($AllowedInstallDir),
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$ScriptPath did not preserve the allowed LocalAppData Yune install directory"
    }

    $BroadYuneWindowsDir = "C:\Yune\WindowsIme"
    $BroadDirThrew = $false
    try {
        Resolve-SafeInstallDir -Path $BroadYuneWindowsDir | Out-Null
    }
    catch {
        $BroadDirThrew = $true
        if ($_.Exception.Message -notmatch "LocalAppData\\Yune") {
            throw "$ScriptPath unsafe-path rejection did not name the LocalAppData Yune boundary: $($_.Exception.Message)"
        }
    }
    if (-not $BroadDirThrew) {
        throw "$ScriptPath accepted an install directory outside LocalAppData Yune: $BroadYuneWindowsDir"
    }
}

Assert-InstallDirResolverContract -ScriptPath $InstallerPath
Assert-InstallDirResolverContract -ScriptPath $UninstallerPath

$Plan = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\plans\active\p2-win01-plan-windows-product.md")
foreach ($RequiredPlanText in @(
        'tools\test-install-dir-safety-contract.ps1',
        'LocalAppData\Yune'
    )) {
    if ($Plan -notmatch [regex]::Escape($RequiredPlanText)) {
        throw "active plan is missing install-dir safety reference: $RequiredPlanText"
    }
}

Write-Host "Install and uninstall scripts constrain approved file operations to LocalAppData Yune install roots."
