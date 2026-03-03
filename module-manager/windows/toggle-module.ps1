param(
    [Parameter(Mandatory = $true)]
    [string]$AppRoot,
    [Parameter(Mandatory = $true)]
    [string]$ModuleSlug,
    [Parameter(Mandatory = $true)]
    [ValidateSet("enable", "disable")]
    [string]$Action
)

$ErrorActionPreference = "Stop"

$script:LogFile = $null

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

$stateFile = Join-Path $AppRoot ("installer\modules\installed\" + $ModuleSlug + "\module-state.json")
$script:LogFile = Join-Path $AppRoot "installer\modules\logs\toggle-module.log"

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:LogFile) | Out-Null
"" | Set-Content -LiteralPath $script:LogFile -Encoding UTF8
Write-Status "INFO" "Module-Toggle-Log initialisiert"

if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) {
    throw "Missing module state: $stateFile"
}

$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
$state.enabled = ($Action -eq "enable")

if ($state.PSObject.Properties.Name -contains "updated_at_utc") {
    $state.updated_at_utc = [DateTime]::UtcNow.ToString("o")
}
else {
    $state | Add-Member -NotePropertyName updated_at_utc -NotePropertyValue ([DateTime]::UtcNow.ToString("o"))
}

$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $stateFile -Encoding UTF8
Write-Status "INFO" "Module $ModuleSlug set to $Action"
