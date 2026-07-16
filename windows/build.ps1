param(
    [switch]$Installer,
    [string]$Version = "1.0.1"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$WindowsRoot = $PSScriptRoot
$Dist = Join-Path $Root "dist"

python -m pip install --disable-pip-version-check --quiet pyinstaller
Push-Location $WindowsRoot
try {
    python -m PyInstaller --noconfirm --clean CodexUsageCard.spec
} finally {
    Pop-Location
}

New-Item -ItemType Directory -Force -Path $Dist | Out-Null
Copy-Item (Join-Path $WindowsRoot "dist\CodexUsageCard.exe") (Join-Path $Dist "CodexUsageCard-windows-x64.exe") -Force

if ($Installer) {
    $Compiler = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    if (-not (Test-Path $Compiler)) {
        throw "Inno Setup 6 was not found. Install it first or omit -Installer."
    }
    $env:APP_VERSION = $Version.TrimStart("v")
    Push-Location $WindowsRoot
    try {
        & $Compiler "installer.iss"
    } finally {
        Pop-Location
    }
}

Write-Host "Built Windows application in $Dist"
