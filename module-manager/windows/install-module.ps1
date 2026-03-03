param(
    [Parameter(Mandatory = $true)]
    [string]$StateFile,
    [Parameter(Mandatory = $true)]
    [string]$Passphrase,
    [Parameter(Mandatory = $true)]
    [string]$ModuleZip,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$script:LogFile = $null
$script:SuccessMarker = $null

function Write-Status {
    param(
        [string]$Level,
        [string]$Message
    )

    $line = "[$Level] $Message"
    Write-Host $line

    if (-not [string]::IsNullOrWhiteSpace($script:LogFile)) {
        $directory = Split-Path -Parent $script:LogFile
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $directory | Out-Null
        }
        Add-Content -LiteralPath $script:LogFile -Value $line
    }
}

function Require-File {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Fehlende Datei: $Path"
    }
}

function Get-KeyFromPassphrase {
    param(
        [string]$Value
    )

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))
    }
    finally {
        $sha.Dispose()
    }
}

function Load-InstallerState {
    param(
        [string]$Path,
        [string]$Secret
    )

    Require-File $Path
    $envelope = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $key = Get-KeyFromPassphrase -Value $Secret
    $secure = ConvertTo-SecureString -String $envelope.payload -Key $key
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)

    try {
        $plaintext = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }

    return ($plaintext | ConvertFrom-Json)
}

function Copy-DirectoryContents {
    param(
        [string]$SourceDir,
        [string]$TargetDir
    )

    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    Copy-Item -Path (Join-Path $SourceDir "*") -Destination $TargetDir -Recurse -Force
}

$state = Load-InstallerState -Path $StateFile -Secret $Passphrase
$appRoot = $state.app_root

if ([string]::IsNullOrWhiteSpace($appRoot)) {
    throw "app_root fehlt im State."
}

$script:LogFile = Join-Path $appRoot "installer\modules\logs\install-module.log"
$script:SuccessMarker = Join-Path $appRoot "installer\modules\last-success\install-module.success"

if ($DryRun) {
    Write-Status "INFO" "Dry-run: wuerde Modul-Log nach $script:LogFile schreiben"
    Write-Status "INFO" "Dry-run: wuerde Modul-Success-Marker nach $script:SuccessMarker schreiben"
}
else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:LogFile) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:SuccessMarker) | Out-Null
    "" | Set-Content -LiteralPath $script:LogFile -Encoding UTF8
    Write-Status "INFO" "Module-Install-Log initialisiert"
}

Require-File $ModuleZip

$workDir = Join-Path $appRoot "installer\modules\tmp"
$extractDir = Join-Path $workDir "extract"

if ($DryRun) {
    Write-Status "INFO" "Dry-run: would extract $ModuleZip into $extractDir"
    $moduleSlug = "dry-run-module"
    $moduleVersion = "0.0.0"
}
else {
    if (Test-Path -LiteralPath $workDir) {
        Remove-Item -LiteralPath $workDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    Expand-Archive -LiteralPath $ModuleZip -DestinationPath $extractDir -Force

    $moduleManifest = Join-Path $extractDir "module.json"
    Require-File $moduleManifest
    $moduleJson = Get-Content -LiteralPath $moduleManifest -Raw | ConvertFrom-Json
    $moduleSlug = $moduleJson.slug
    $moduleVersion = $moduleJson.version
}

if ([string]::IsNullOrWhiteSpace($moduleSlug)) { throw "module slug fehlt." }
if ([string]::IsNullOrWhiteSpace($moduleVersion)) { throw "module version fehlt." }

$backendSource = Join-Path $extractDir "backend"
$frontendSource = Join-Path $extractDir "frontend"
$backendTarget = Join-Path $appRoot ("current\modules\" + $moduleSlug)
$frontendTarget = Join-Path $appRoot ("public\modules\" + $moduleSlug)
$moduleStateDir = Join-Path $appRoot ("installer\modules\installed\" + $moduleSlug)
$moduleStateFile = Join-Path $moduleStateDir "module-state.json"

if ($DryRun) {
    Write-Status "INFO" "Dry-run: would install backend to $backendTarget"
    Write-Status "INFO" "Dry-run: would install frontend to $frontendTarget"
    Write-Status "INFO" "Dry-run: would persist module state to $moduleStateFile"
    exit 0
}

if (Test-Path -LiteralPath $backendSource -PathType Container) {
    Copy-DirectoryContents -SourceDir $backendSource -TargetDir $backendTarget
    Write-Status "INFO" "Installed backend module files into $backendTarget"
}

if (Test-Path -LiteralPath $frontendSource -PathType Container) {
    Copy-DirectoryContents -SourceDir $frontendSource -TargetDir $frontendTarget
    Write-Status "INFO" "Installed frontend module files into $frontendTarget"
}

New-Item -ItemType Directory -Force -Path $moduleStateDir | Out-Null
$moduleJson | Add-Member -NotePropertyName enabled -NotePropertyValue $true -Force
$moduleJson | Add-Member -NotePropertyName installed_at_utc -NotePropertyValue ([DateTime]::UtcNow.ToString("o")) -Force
$moduleJson | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $moduleStateFile -Encoding UTF8
Write-Status "INFO" "Persisted module state to $moduleStateFile"

$artisanPath = Join-Path $appRoot "current\artisan"
if (Test-Path -LiteralPath $artisanPath -PathType Leaf) {
    Push-Location (Join-Path $appRoot "current")
    try {
        & php artisan migrate --force
    }
    catch {
        Write-Status "WARN" "artisan migrate failed but install continues"
    }
    finally {
        Pop-Location
    }
    Write-Status "INFO" "Triggered artisan migrate for module install"
}

Write-Status "INFO" "Module install completed for $moduleSlug@$moduleVersion"

if ($DryRun) {
    Write-Status "INFO" "Dry-run: wuerde Modul-Success-Marker nach $script:SuccessMarker schreiben"
}
else {
    @(
        "installed_at_utc=$([DateTime]::UtcNow.ToString('o'))"
        "module=$moduleSlug"
        "version=$moduleVersion"
    ) | Set-Content -LiteralPath $script:SuccessMarker -Encoding UTF8
    Write-Status "INFO" "Module-Success-Marker geschrieben"
}
