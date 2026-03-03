param(
    [Parameter(Mandatory = $true)]
    [string]$StateFile,
    [Parameter(Mandatory = $true)]
    [string]$Passphrase,
    [Parameter(Mandatory = $true)]
    [string]$ModuleSlug,
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

function Remove-OrPreview {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: would remove $Path"
        return
    }

    Remove-Item -LiteralPath $Path -Recurse -Force
    Write-Status "INFO" "Removed $Path"
}

$state = Load-InstallerState -Path $StateFile -Secret $Passphrase
$appRoot = $state.app_root

if ([string]::IsNullOrWhiteSpace($appRoot)) {
    throw "app_root fehlt im State."
}

$script:LogFile = Join-Path $appRoot "installer\modules\logs\uninstall-module.log"
$script:SuccessMarker = Join-Path $appRoot "installer\modules\last-success\uninstall-module.success"

if ($DryRun) {
    Write-Status "INFO" "Dry-run: wuerde Modul-Uninstall-Log nach $script:LogFile schreiben"
    Write-Status "INFO" "Dry-run: wuerde Modul-Uninstall-Success-Marker nach $script:SuccessMarker schreiben"
}
else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:LogFile) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:SuccessMarker) | Out-Null
    "" | Set-Content -LiteralPath $script:LogFile -Encoding UTF8
    Write-Status "INFO" "Modul-Uninstall-Log initialisiert"
}

$backendTarget = Join-Path $appRoot ("current\modules\" + $ModuleSlug)
$frontendTarget = Join-Path $appRoot ("public\modules\" + $ModuleSlug)
$moduleStateDir = Join-Path $appRoot ("installer\modules\installed\" + $ModuleSlug)
$moduleStateFile = Join-Path $moduleStateDir "module-state.json"

if ((-not $DryRun) -and (-not (Test-Path -LiteralPath $moduleStateFile -PathType Leaf))) {
    throw "Missing module state: $moduleStateFile"
}

Remove-OrPreview -Path $backendTarget
Remove-OrPreview -Path $frontendTarget
Remove-OrPreview -Path $moduleStateDir

$artisanPath = Join-Path $appRoot "current\artisan"
if ((-not $DryRun) -and (Test-Path -LiteralPath $artisanPath -PathType Leaf)) {
    Push-Location (Join-Path $appRoot "current")
    try {
        & php artisan optimize:clear
    }
    catch {
        Write-Status "WARN" "artisan optimize:clear failed but uninstall continues"
    }
    finally {
        Pop-Location
    }
    Write-Status "INFO" "Triggered artisan optimize:clear after module uninstall"
}

if ($DryRun) {
    Write-Status "INFO" "Dry-run: wuerde Modul-Uninstall-Success-Marker nach $script:SuccessMarker schreiben"
}
else {
    @(
        "uninstalled_at_utc=$([DateTime]::UtcNow.ToString('o'))"
        "module=$ModuleSlug"
    ) | Set-Content -LiteralPath $script:SuccessMarker -Encoding UTF8
    Write-Status "INFO" "Modul-Uninstall-Success-Marker geschrieben"
}

Write-Status "INFO" "Module uninstall completed for $ModuleSlug"
