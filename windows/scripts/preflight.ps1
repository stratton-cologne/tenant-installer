param()

$ErrorActionPreference = "Stop"

$script:Failed = $false

function Write-Status {
    param(
        [string]$Level,
        [string]$Message
    )

    Write-Host "[$Level] $Message"
}

function Add-Failure {
    param(
        [string]$Message
    )

    $script:Failed = $true
    Write-Status "FAIL" $Message
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        Write-Status "PASS" "Ausfuehrung mit Administratorrechten"
        return
    }

    Add-Failure "Administratorrechte sind erforderlich"
}

function Test-OsVersion {
    $version = [System.Environment]::OSVersion.Version

    if ($version.Major -ge 10) {
        Write-Status "PASS" "Unterstuetzte Windows-Version erkannt: $($version.ToString())"
        return
    }

    Add-Failure "Nicht unterstuetzte Windows-Version: $($version.ToString())"
}

function Test-CommandOptional {
    param(
        [string]$Name
    )

    if ($null -ne (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Status "PASS" "Befehl verfuegbar: $Name"
        return $true
    }

    Write-Status "WARN" "Befehl nicht gefunden: $Name"
    return $false
}

function Test-GitAvailability {
    if (Test-CommandOptional -Name "git") {
        Write-Status "INFO" "Git ist verfuegbar. Release-Bezug ueber GitHub kann vorbereitet werden."
        return
    }

    Add-Failure "Git fehlt. Der geplante Release-Bezug kann so nicht ausgefuehrt werden."
}

function Test-Php82 {
    $php = Get-Command php -ErrorAction SilentlyContinue

    if ($null -eq $php) {
        Write-Status "WARN" "PHP ist nicht vorhanden und muss spaeter installiert werden."
        return
    }

    $version = (& php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

    if ($version -eq "8.2") {
        Write-Status "PASS" "PHP 8.2 erkannt"
        return
    }

    Write-Status "WARN" "PHP erkannt, aber falsche Version: $version. Upgrade oder Neuinstallation von PHP 8.2 erforderlich."
}

function Test-NginxAvailability {
    if (Test-CommandOptional -Name "nginx") {
        Write-Status "PASS" "Nginx ist bereits verfuegbar"
        return
    }

    Write-Status "WARN" "Nginx ist nicht vorhanden und muss spaeter eingerichtet werden."
}

function Test-InstallerTooling {
    $hasWinget = Test-CommandOptional -Name "winget"
    $hasChoco = Test-CommandOptional -Name "choco"

    if ($hasWinget -or $hasChoco) {
        Write-Status "PASS" "Mindestens ein Paketmanager fuer spaetere Installationen verfuegbar"
        return
    }

    Write-Status "WARN" "Kein Paketmanager erkannt (weder winget noch choco). Tool-Installation muss ggf. manuell oder per direktem Download erfolgen."
}

Write-Status "INFO" "Starte Windows-Preflight"
Test-Administrator
Test-OsVersion
Test-GitAvailability
Test-Php82
Test-NginxAvailability
Test-InstallerTooling

if ($script:Failed) {
    Write-Status "INFO" "Preflight mit Fehlern abgeschlossen"
    exit 1
}

Write-Status "INFO" "Preflight erfolgreich abgeschlossen"
exit 0
