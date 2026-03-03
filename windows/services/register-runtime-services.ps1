param(
    [Parameter(Mandatory = $true)]
    [string]$RuntimeDir,
    [Parameter(Mandatory = $true)]
    [string]$AppRoot,
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

function Write-Status {
    param(
        [string]$Level,
        [string]$Message
    )

    Write-Host "[$Level] $Message"
}

function Invoke-OrPreview {
    param(
        [string]$Command
    )

    if (-not $Apply) {
        Write-Status "INFO" "Would run: $Command"
        return
    }

    & cmd /c $Command | Out-Null
    Write-Status "INFO" "Ran: $Command"
}

$queueScript = Join-Path $RuntimeDir "services\queue-worker-wrapper.ps1"
$schedulerScript = Join-Path $RuntimeDir "services\scheduler-wrapper.ps1"

$queueBin = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$queueScript`" -AppRoot `"$AppRoot`""
$schedulerBin = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$schedulerScript`" -AppRoot `"$AppRoot`""

Invoke-OrPreview -Command "sc.exe stop tenant-queue-worker"
Invoke-OrPreview -Command "sc.exe delete tenant-queue-worker"
Invoke-OrPreview -Command "sc.exe create tenant-queue-worker binPath= `"$queueBin`" start= auto"

Invoke-OrPreview -Command "sc.exe stop tenant-scheduler"
Invoke-OrPreview -Command "sc.exe delete tenant-scheduler"
Invoke-OrPreview -Command "sc.exe create tenant-scheduler binPath= `"$schedulerBin`" start= auto"

Invoke-OrPreview -Command "sc.exe start tenant-queue-worker"
Invoke-OrPreview -Command "sc.exe start tenant-scheduler"
