param(
    [Parameter(Mandatory = $true)]
    [string]$StateFile,
    [Parameter(Mandatory = $true)]
    [string]$Passphrase,
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
$script:LogFile = Join-Path $state.app_root "installer\logs\uninstall.log"
$script:SuccessMarker = Join-Path $state.app_root "installer\state\uninstall.success"

if ($DryRun) {
    Write-Status "INFO" "Dry-run: wuerde Uninstall-Log nach $script:LogFile schreiben"
    Write-Status "INFO" "Dry-run: wuerde Uninstall-Success-Marker nach $script:SuccessMarker schreiben"
}
else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:LogFile) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:SuccessMarker) | Out-Null
    "" | Set-Content -LiteralPath $script:LogFile -Encoding UTF8
    Write-Status "INFO" "Uninstall-Log initialisiert"
}

$keepData = Read-Host "Keep database and release files for manual recovery? [yes]"

if ([string]::IsNullOrWhiteSpace($keepData)) {
    $keepData = "yes"
}

$keepReleaseData = $keepData.ToLowerInvariant() -in @("y", "yes")

Remove-OrPreview -Path $state.deployed.current_release_dir
Remove-OrPreview -Path $state.deployed.frontend_public_dir
Remove-OrPreview -Path $state.services.runtime_config_dir
Remove-OrPreview -Path (Join-Path $state.app_root "installer\cache")

if (-not $keepReleaseData) {
    Remove-OrPreview -Path $state.deployed.backend_release_dir
    Remove-OrPreview -Path $state.deployed.frontend_release_dir
    Remove-OrPreview -Path (Join-Path $state.app_root "releases")
}
else {
    Write-Status "INFO" "Release-Verzeichnisse bleiben erhalten"
}

if ($DryRun) {
    Write-Status "INFO" "Dry-run: would remove state file $StateFile"
}
else {
    Remove-OrPreview -Path $StateFile

    @(
        "uninstalled_at_utc=$([DateTime]::UtcNow.ToString('o'))"
        "kept_release_data=$keepReleaseData"
    ) | Set-Content -LiteralPath $script:SuccessMarker -Encoding UTF8
    Write-Status "INFO" "Uninstall-Success-Marker geschrieben"
}

Write-Status "INFO" "Uninstall flow completed"
