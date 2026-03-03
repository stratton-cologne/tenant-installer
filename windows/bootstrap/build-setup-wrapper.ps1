param(
    [string]$AppVersion = "0.1.0",
    [string]$PublishDir = "",
    [string]$OutputDir = "",
    [string]$TemplatePath = "",
    [string]$RenderedScriptPath = "",
    [string]$InnoCompilerPath = "",
    [switch]$Compile
)

$ErrorActionPreference = "Stop"

function Write-Status {
    param(
        [string]$Level,
        [string]$Message
    )

    Write-Host "[$Level] $Message"
}

function Require-Path {
    param(
        [string]$Path,
        [string]$Description,
        [bool]$Directory = $false
    )

    $pathType = if ($Directory) { "Container" } else { "Leaf" }

    if (-not (Test-Path -LiteralPath $Path -PathType $pathType)) {
        throw "$Description nicht gefunden: $Path"
    }
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptRoot)

if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
    $TemplatePath = Join-Path $ScriptRoot "TenantInstaller.Setup.iss.tpl"
}

if ([string]::IsNullOrWhiteSpace($PublishDir)) {
    $PublishDir = Join-Path $ProjectRoot "build\windows-installer-ui\Release\win-x64"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot "build\windows-setup"
}

if ([string]::IsNullOrWhiteSpace($RenderedScriptPath)) {
    $RenderedScriptPath = Join-Path $OutputDir "TenantInstaller.Setup.iss"
}

Require-Path -Path $TemplatePath -Description "Inno-Template"
Require-Path -Path $PublishDir -Description "Publish-Verzeichnis" -Directory $true

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$template = Get-Content -LiteralPath $TemplatePath -Raw
$rendered = $template.Replace("__APP_VERSION__", $AppVersion)
$rendered = $rendered.Replace("__PUBLISH_DIR__", $PublishDir)
$rendered = $rendered.Replace("__OUTPUT_DIR__", $OutputDir)

Set-Content -LiteralPath $RenderedScriptPath -Value $rendered -Encoding UTF8
Write-Status "INFO" "Inno-Setup-Skript erzeugt: $RenderedScriptPath"

if (-not $Compile) {
    Write-Status "INFO" "Kompilierung uebersprungen"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($InnoCompilerPath)) {
    throw "Compile angefordert, aber InnoCompilerPath fehlt."
}

Require-Path -Path $InnoCompilerPath -Description "Inno Setup Compiler"

Write-Status "INFO" "Starte Inno Setup Compiler"
& $InnoCompilerPath $RenderedScriptPath
Write-Status "INFO" "Setup-Kompilierung abgeschlossen"
