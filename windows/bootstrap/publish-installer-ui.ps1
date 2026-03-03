param(
    [string]$Configuration = "Release",
    [string]$RuntimeIdentifier = "win-x64",
    [string]$OutputRoot = "",
    [switch]$SelfContained,
    [switch]$SingleFile,
    [switch]$Sign,
    [string]$SignToolPath = "",
    [string]$CertificatePath = "",
    [string]$CertificatePassword = "",
    [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

function Write-Status {
    param(
        [string]$Level,
        [string]$Message
    )

    Write-Host "[$Level] $Message"
}

function Require-Command {
    param(
        [string]$Name
    )

    if ($null -eq (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Befehl nicht gefunden: $Name"
    }
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptRoot)
$UiProject = Join-Path $ProjectRoot "windows\installer-ui\TenantInstaller.Ui.csproj"

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $ProjectRoot "build\windows-installer-ui"
}

$publishDir = Join-Path $OutputRoot "$Configuration\$RuntimeIdentifier"
$selfContainedText = if ($SelfContained) { "true" } else { "false" }
$singleFileText = if ($SingleFile) { "true" } else { "false" }

Require-Command -Name "dotnet"

if (-not (Test-Path -LiteralPath $UiProject -PathType Leaf)) {
    throw "UI-Projekt nicht gefunden: $UiProject"
}

Write-Status "INFO" "Starte dotnet publish fuer $UiProject"
Write-Status "INFO" "Ziel: $publishDir"

$publishArgs = @(
    "publish",
    $UiProject,
    "-c",
    $Configuration,
    "-r",
    $RuntimeIdentifier,
    "--self-contained",
    $selfContainedText,
    "-p:EnableWindowsTargeting=true",
    "-p:PublishSingleFile=$singleFileText",
    "-p:PublishTrimmed=false",
    "-o",
    $publishDir
)

& dotnet @publishArgs

$publishedExe = Join-Path $publishDir "TenantInstaller.Ui.exe"

if (-not (Test-Path -LiteralPath $publishedExe -PathType Leaf)) {
    throw "Veroeffentlichtes EXE nicht gefunden: $publishedExe"
}

Write-Status "INFO" "Publish abgeschlossen: $publishedExe"

if (-not $Sign) {
    Write-Status "INFO" "Signierung uebersprungen"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($SignToolPath)) {
    throw "Signierung angefordert, aber SignToolPath fehlt."
}

if ([string]::IsNullOrWhiteSpace($CertificatePath)) {
    throw "Signierung angefordert, aber CertificatePath fehlt."
}

if (-not (Test-Path -LiteralPath $SignToolPath -PathType Leaf)) {
    throw "signtool nicht gefunden: $SignToolPath"
}

if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
    throw "Zertifikat nicht gefunden: $CertificatePath"
}

Write-Status "INFO" "Signiere $publishedExe"

$signArgs = @(
    "sign",
    "/f",
    $CertificatePath
)

if (-not [string]::IsNullOrWhiteSpace($CertificatePassword)) {
    $signArgs += @("/p", $CertificatePassword)
}

$signArgs += @(
    "/fd",
    "SHA256",
    "/tr",
    $TimestampUrl,
    "/td",
    "SHA256",
    $publishedExe
)

& $SignToolPath @signArgs

Write-Status "INFO" "Signierung abgeschlossen"
