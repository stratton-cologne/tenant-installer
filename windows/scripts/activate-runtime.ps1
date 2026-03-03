param(
    [Parameter(Mandatory = $true)]
    [string]$StateFile,
    [Parameter(Mandatory = $true)]
    [string]$Passphrase,
    [switch]$Apply
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

function Copy-OrPreview {
    param(
        [string]$Source,
        [string]$Target
    )

    if (-not $Apply) {
        Write-Status "INFO" "Would copy $Source -> $Target"
        return
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Target -Force
    Write-Status "INFO" "Copied $Source -> $Target"
}

function Invoke-OrPreview {
    param(
        [string]$Command
    )

    if (-not $Apply) {
        Write-Status "INFO" "Would run: $Command"
        return
    }

    & powershell -NoProfile -Command $Command
    Write-Status "INFO" "Ran: $Command"
}

$state = Load-InstallerState -Path $StateFile -Secret $Passphrase
$runtimeDir = $state.services.runtime_config_dir
$currentDir = $state.deployed.current_release_dir

if ([string]::IsNullOrWhiteSpace($runtimeDir)) { throw "runtime_config_dir fehlt im State." }
if ([string]::IsNullOrWhiteSpace($currentDir)) { throw "current_release_dir fehlt im State." }

$script:LogFile = Join-Path $state.app_root "installer\logs\activate-runtime.log"
$script:SuccessMarker = Join-Path $state.app_root "installer\state\activate-runtime.success"

$nginxMainSource = Join-Path $runtimeDir "nginx\nginx.conf"
$nginxSource = Join-Path $runtimeDir "nginx\tenant-site.conf"
$queueSource = Join-Path $runtimeDir "services\queue-worker-wrapper.ps1"
$schedulerSource = Join-Path $runtimeDir "services\scheduler-wrapper.ps1"
$registerScript = Join-Path $runtimeDir "services\register-runtime-services.ps1"

Require-File $nginxMainSource
Require-File $nginxSource
Require-File $queueSource
Require-File $schedulerSource
Require-File $registerScript

$nginxMainTarget = "C:\Stratton\Nginx\conf\nginx.conf"
$nginxTarget = "C:\Stratton\Nginx\conf\sites-enabled\tenant-site.conf"
$queueTarget = "C:\Stratton\Tenant\runtime\services\queue-worker-wrapper.ps1"
$schedulerTarget = "C:\Stratton\Tenant\runtime\services\scheduler-wrapper.ps1"
$registerTarget = "C:\Stratton\Tenant\runtime\services\register-runtime-services.ps1"

if (-not $Apply) {
    Write-Status "INFO" "Preview mode: would write runtime activation log to $script:LogFile"
    Write-Status "INFO" "Preview mode: would write success marker to $script:SuccessMarker"
}
else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:LogFile) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:SuccessMarker) | Out-Null
    "" | Set-Content -LiteralPath $script:LogFile -Encoding UTF8
    Write-Status "INFO" "Runtime activation log initialisiert"
}

Write-Status "INFO" "Current release: $currentDir"
Copy-OrPreview -Source $nginxMainSource -Target $nginxMainTarget
Copy-OrPreview -Source $nginxSource -Target $nginxTarget
Copy-OrPreview -Source $queueSource -Target $queueTarget
Copy-OrPreview -Source $schedulerSource -Target $schedulerTarget
Copy-OrPreview -Source $registerScript -Target $registerTarget

$applyFlag = if ($Apply) { "-Apply" } else { "" }
Invoke-OrPreview -Command "& `"$registerTarget`" -RuntimeDir `"C:\Stratton\Tenant\runtime`" -AppRoot `"$($state.app_root)`" $applyFlag"
Invoke-OrPreview -Command 'Write-Host "Placeholder: reload nginx"'

if (-not $Apply) {
    Write-Status "INFO" "Preview completed. Re-run with -Apply to activate runtime assets."
}
else {
    @(
        "activated_at_utc=$([DateTime]::UtcNow.ToString('o'))"
        "runtime_dir=$runtimeDir"
    ) | Set-Content -LiteralPath $script:SuccessMarker -Encoding UTF8
    Write-Status "INFO" "Runtime activation success marker geschrieben"
    Write-Status "INFO" "Runtime activation completed"
}
