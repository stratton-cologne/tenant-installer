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

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallScript = Join-Path $ScriptRoot "install-module.ps1"

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

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing state file: $Path"
    }

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

if (-not (Test-Path -LiteralPath $InstallScript -PathType Leaf)) {
    throw "Missing install script: $InstallScript"
}

$state = Load-InstallerState -Path $StateFile -Secret $Passphrase
$appRoot = $state.app_root
if ([string]::IsNullOrWhiteSpace($appRoot)) {
    throw "app_root fehlt im State."
}

$logFile = Join-Path $appRoot "installer\modules\logs\update-module.log"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logFile) | Out-Null
"[INFO] Module-Update-Log initialisiert" | Set-Content -LiteralPath $logFile -Encoding UTF8

Write-Host "[INFO] Delegating module update to install flow"
Add-Content -LiteralPath $logFile -Value "[INFO] Delegating module update to install flow"

& powershell -ExecutionPolicy Bypass -File $InstallScript -StateFile $StateFile -Passphrase $Passphrase -ModuleZip $ModuleZip @(
    if ($DryRun) { "-DryRun" }
)

Write-Host "[INFO] Module update flow completed"
Add-Content -LiteralPath $logFile -Value "[INFO] Module update flow completed"
