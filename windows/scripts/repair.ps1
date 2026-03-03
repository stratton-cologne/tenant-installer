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

function Copy-DirectoryContents {
    param(
        [string]$SourceDir,
        [string]$TargetDir
    )

    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    Copy-Item -Path (Join-Path $SourceDir "*") -Destination $TargetDir -Recurse -Force
}

function Repair-Backend {
    param(
        [pscustomobject]$State
    )

    $currentDir = $State.deployed.current_release_dir
    $releaseDir = $State.deployed.backend_release_dir

    if ([string]::IsNullOrWhiteSpace($currentDir) -or [string]::IsNullOrWhiteSpace($releaseDir)) {
        Write-Status "WARN" "Backend-Pfade fehlen im State"
        return
    }

    if (Test-Path -LiteralPath $currentDir -PathType Container) {
        Write-Status "INFO" "Backend current release vorhanden: $currentDir"
        return
    }

    if (-not (Test-Path -LiteralPath $releaseDir -PathType Container)) {
        Write-Status "WARN" "Backend-Release-Quelle fehlt: $releaseDir"
        return
    }

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: would restore backend $releaseDir -> $currentDir"
        return
    }

    Copy-DirectoryContents -SourceDir $releaseDir -TargetDir $currentDir
    Write-Status "INFO" "Backend wiederhergestellt: $currentDir"
}

function Repair-Frontend {
    param(
        [pscustomobject]$State
    )

    $publicDir = $State.deployed.frontend_public_dir
    $releaseDir = $State.deployed.frontend_release_dir

    if ([string]::IsNullOrWhiteSpace($publicDir) -or [string]::IsNullOrWhiteSpace($releaseDir)) {
        Write-Status "WARN" "Frontend-Pfade fehlen im State"
        return
    }

    $hasFiles = $false
    if (Test-Path -LiteralPath $publicDir -PathType Container) {
        $hasFiles = $null -ne (Get-ChildItem -LiteralPath $publicDir -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
    }

    if ($hasFiles) {
        Write-Status "INFO" "Frontend public vorhanden: $publicDir"
        return
    }

    if (-not (Test-Path -LiteralPath $releaseDir -PathType Container)) {
        Write-Status "WARN" "Frontend-Release-Quelle fehlt: $releaseDir"
        return
    }

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: would restore frontend $releaseDir -> $publicDir"
        return
    }

    Copy-DirectoryContents -SourceDir $releaseDir -TargetDir $publicDir
    Write-Status "INFO" "Frontend wiederhergestellt: $publicDir"
}

function Repair-Runtime {
    param(
        [pscustomobject]$State
    )

    $runtimeDir = $State.services.runtime_config_dir
    $currentDir = $State.deployed.current_release_dir

    if ([string]::IsNullOrWhiteSpace($runtimeDir)) {
        Write-Status "WARN" "runtime_config_dir fehlt im State"
        return
    }

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: would ensure runtime directories under $runtimeDir"
        return
    }

    New-Item -ItemType Directory -Force -Path (Join-Path $runtimeDir "nginx") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $runtimeDir "services") | Out-Null

    $envBackup = Join-Path $runtimeDir "tenant.env"
    $envTarget = Join-Path $currentDir ".env"
    if ((Test-Path -LiteralPath $envBackup -PathType Leaf) -and (-not (Test-Path -LiteralPath $envTarget -PathType Leaf))) {
        Copy-Item -LiteralPath $envBackup -Destination $envTarget -Force
        Write-Status "INFO" "Env wiederhergestellt: $envTarget"
    }

    Write-Status "INFO" "Runtime-Verzeichnisse sichergestellt"
}

$state = Load-InstallerState -Path $StateFile -Secret $Passphrase
$script:LogFile = Join-Path $state.app_root "installer\logs\repair.log"
$script:SuccessMarker = Join-Path $state.app_root "installer\state\repair.success"

if ($DryRun) {
    Write-Status "INFO" "Dry-run: wuerde Repair-Log nach $script:LogFile schreiben"
    Write-Status "INFO" "Dry-run: wuerde Repair-Success-Marker nach $script:SuccessMarker schreiben"
}
else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:LogFile) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:SuccessMarker) | Out-Null
    "" | Set-Content -LiteralPath $script:LogFile -Encoding UTF8
    Write-Status "INFO" "Repair-Log initialisiert"
}

Repair-Backend -State $state
Repair-Frontend -State $state
Repair-Runtime -State $state

if ($DryRun) {
    Write-Status "INFO" "Dry-run: wuerde Repair-Success-Marker nach $script:SuccessMarker schreiben"
}
else {
    @(
        "repaired_at_utc=$([DateTime]::UtcNow.ToString('o'))"
    ) | Set-Content -LiteralPath $script:SuccessMarker -Encoding UTF8
    Write-Status "INFO" "Repair-Success-Marker geschrieben"
}

Write-Status "INFO" "Repair flow completed"
