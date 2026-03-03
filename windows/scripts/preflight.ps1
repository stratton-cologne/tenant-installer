param(
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

function Write-Status {
    param(
        [string]$Level,
        [string]$Message
    )

    Write-Host "[$Level] $Message"
}

function Test-CommandAvailable {
    param(
        [string]$Name,
        [bool]$Required = $true
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue

    if ($null -ne $command) {
        Write-Status "PASS" "Befehl verfuegbar: $Name"
        return $true
    }

    if ($Required) {
        Write-Status "FAIL" "Befehl fehlt: $Name"
        return $false
    }

    Write-Status "WARN" "Optionaler Befehl fehlt: $Name"
    return $true
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        Write-Status "PASS" "Ausfuehrung mit Administratorrechten"
        return $true
    }

    Write-Status "FAIL" "Administratorrechte sind erforderlich"
    return $false
}

function Test-OsVersion {
    $version = [System.Environment]::OSVersion.Version

    if ($version.Major -ge 10) {
        Write-Status "PASS" "Unterstuetzte Windows-Version erkannt: $($version.ToString())"
        return $true
    }

    Write-Status "FAIL" "Nicht unterstuetzte Windows-Version: $($version.ToString())"
    return $false
}

function Test-PhpVersion {
    $php = Get-Command php -ErrorAction SilentlyContinue

    if ($null -eq $php) {
        Write-Status "FAIL" "PHP fehlt"
        return $false
    }

    $phpVersion = & php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;'

    if ($phpVersion -eq "8.2") {
        Write-Status "PASS" "PHP 8.2 erkannt"
        return $true
    }

    Write-Status "FAIL" "Falsche PHP-Version erkannt: $phpVersion (erwartet 8.2)"
    return $false
}

function Test-PhpExtension {
    param(
        [string]$Name
    )

    $modules = & php -m

    if ($modules -contains $Name) {
        Write-Status "PASS" "PHP-Extension verfuegbar: $Name"
        return $true
    }

    Write-Status "FAIL" "PHP-Extension fehlt: $Name"
    return $false
}

function Test-PortAvailability {
    param(
        [int]$Port
    )

    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue

    if ($null -eq $listener) {
        Write-Status "PASS" "Port $Port ist aktuell frei"
        return $true
    }

    Write-Status "WARN" "Port $Port ist bereits belegt"
    return $true
}

$allChecksPassed = $true

Write-Status "INFO" "Starte Windows-Preflight"

if (-not (Test-Administrator)) { $allChecksPassed = $false }
if (-not (Test-OsVersion)) { $allChecksPassed = $false }
if (-not (Test-CommandAvailable -Name "php" -Required $true)) { $allChecksPassed = $false }
if (-not (Test-PhpVersion)) { $allChecksPassed = $false }
if (-not (Test-CommandAvailable -Name "composer" -Required $true)) { $allChecksPassed = $false }
if (-not (Test-CommandAvailable -Name "jq" -Required $true)) { $allChecksPassed = $false }
if (-not (Test-CommandAvailable -Name "Expand-Archive" -Required $true)) { $allChecksPassed = $false }
if (-not (Test-CommandAvailable -Name "mysql" -Required $false)) { }
if (-not (Test-CommandAvailable -Name "mariadb" -Required $false)) { }
if (-not (Test-PhpExtension -Name "pdo_mysql")) { $allChecksPassed = $false }
if (-not (Test-PhpExtension -Name "mbstring")) { $allChecksPassed = $false }
if (-not (Test-PhpExtension -Name "openssl")) { $allChecksPassed = $false }
if (-not (Test-PhpExtension -Name "xml")) { $allChecksPassed = $false }
if (-not (Test-PhpExtension -Name "curl")) { $allChecksPassed = $false }
if (-not (Test-PhpExtension -Name "zip")) { $allChecksPassed = $false }
if (-not (Test-PortAvailability -Port 80)) { }
if (-not (Test-PortAvailability -Port 443)) { }

if ($allChecksPassed) {
    Write-Status "INFO" "Preflight erfolgreich abgeschlossen"
    exit 0
}

Write-Status "INFO" "Preflight mit Fehlern abgeschlossen"
exit 1
