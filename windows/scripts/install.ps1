param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [string]$OutputRoot = "",
    [string]$GitHubToken = "",
    [ValidateSet("ScheduledTask", "Nssm")]
    [string]$PhpRuntimeMode = "",
    [switch]$IncludePrerelease,
    [switch]$SkipPreflight,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Write-Status {
    param(
        [string]$Level,
        [string]$Message
    )

    Write-Host "[$Level] $Message"
}

function Require-File {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Fehlende Datei: $Path"
    }
}

function Read-InstallConfig {
    param(
        [string]$Path
    )

    Require-File $Path
    $raw = Get-Content -LiteralPath $Path -Raw

    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Konfigurationsdatei ist leer: $Path"
    }

    return ($raw | ConvertFrom-Json)
}

function Get-ConfigString {
    param(
        [object]$Config,
        [string]$Name,
        [string]$Default = ""
    )

    $property = $Config.PSObject.Properties[$Name]

    if ($null -eq $property -or $null -eq $property.Value) {
        return $Default
    }

    return [string]$property.Value
}

function Get-ConfigBool {
    param(
        [object]$Config,
        [string]$Name,
        [bool]$Default = $false
    )

    $property = $Config.PSObject.Properties[$Name]

    if ($null -eq $property -or $null -eq $property.Value) {
        return $Default
    }

    if ($property.Value -is [bool]) {
        return [bool]$property.Value
    }

    $text = [string]$property.Value
    return $text.ToLowerInvariant() -in @("1", "true", "yes", "y")
}

function ConvertTo-InstallContext {
    param(
        [object]$Config
    )

    $installRoot = Get-ConfigString -Config $Config -Name "InstallRoot" -Default "C:\TenantPlatform"

    if ([string]::IsNullOrWhiteSpace($installRoot)) {
        throw "InstallRoot darf nicht leer sein."
    }

    $context = [ordered]@{
        InstallRoot = $installRoot
        PrimaryDomain = Get-ConfigString -Config $Config -Name "PrimaryDomain"
        UseSsl = Get-ConfigBool -Config $Config -Name "UseSsl" -Default $true
        AdminEmail = Get-ConfigString -Config $Config -Name "AdminEmail"
        AdminPassword = Get-ConfigString -Config $Config -Name "AdminPassword"
        UseLocalDatabase = Get-ConfigBool -Config $Config -Name "UseLocalDatabase" -Default $false
        DatabaseHost = Get-ConfigString -Config $Config -Name "DatabaseHost" -Default "127.0.0.1"
        DatabasePort = Get-ConfigString -Config $Config -Name "DatabasePort" -Default "3306"
        DatabaseName = Get-ConfigString -Config $Config -Name "DatabaseName" -Default "tenant_platform"
        DatabaseUser = Get-ConfigString -Config $Config -Name "DatabaseUser" -Default "tenant_user"
        DatabasePassword = Get-ConfigString -Config $Config -Name "DatabasePassword"
        EnableSmtp = Get-ConfigBool -Config $Config -Name "EnableSmtp" -Default $false
        SmtpHost = Get-ConfigString -Config $Config -Name "SmtpHost"
        SmtpPort = Get-ConfigString -Config $Config -Name "SmtpPort" -Default "587"
        SmtpUser = Get-ConfigString -Config $Config -Name "SmtpUser"
        SmtpPassword = Get-ConfigString -Config $Config -Name "SmtpPassword"
        SmtpEncryption = Get-ConfigString -Config $Config -Name "SmtpEncryption" -Default "tls"
        MailFromAddress = Get-ConfigString -Config $Config -Name "MailFromAddress"
        TenantId = Get-ConfigString -Config $Config -Name "TenantId"
        LicenseKeys = Get-ConfigString -Config $Config -Name "LicenseKeys"
        PhpRuntimeMode = Get-ConfigString -Config $Config -Name "PhpRuntimeMode" -Default "ScheduledTask"
    }

    return [pscustomobject]$context
}

function Validate-InstallContext {
    param(
        [pscustomobject]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Context.PrimaryDomain)) {
        throw "PrimaryDomain ist erforderlich."
    }

    if ([string]::IsNullOrWhiteSpace($Context.AdminEmail)) {
        throw "AdminEmail ist erforderlich."
    }

    if ([string]::IsNullOrWhiteSpace($Context.AdminPassword)) {
        throw "AdminPassword ist erforderlich."
    }

    if ([string]::IsNullOrWhiteSpace($Context.DatabasePassword)) {
        throw "DatabasePassword ist erforderlich."
    }

    if ($Context.EnableSmtp -and [string]::IsNullOrWhiteSpace($Context.MailFromAddress)) {
        throw "MailFromAddress ist erforderlich, wenn SMTP aktiviert ist."
    }

    if ($Context.PhpRuntimeMode -notin @("ScheduledTask", "Nssm")) {
        throw "PhpRuntimeMode muss 'ScheduledTask' oder 'Nssm' sein."
    }
}

function Invoke-Preflight {
    param(
        [string]$ScriptPath
    )

    Require-File $ScriptPath
    Write-Status "INFO" "Fuehre Preflight aus"
    & powershell -ExecutionPolicy Bypass -File $ScriptPath

    if ($LASTEXITCODE -ne 0) {
        throw "Preflight fehlgeschlagen mit Exit-Code $LASTEXITCODE"
    }
}

function Invoke-FetchReleases {
    param(
        [string]$ScriptPath,
        [string]$TargetOutputRoot,
        [string]$Token
    )

    Require-File $ScriptPath

    $arguments = @(
        "-ExecutionPolicy", "Bypass",
        "-File", $ScriptPath,
        "-OutputRoot", $TargetOutputRoot
    )

    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $arguments += @("-GitHubToken", $Token)
    }

    if ($IncludePrerelease) {
        $arguments += "-IncludePrerelease"
    }

    Write-Status "INFO" "Hole neueste Releases"
    & powershell @arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Release-Bezug fehlgeschlagen mit Exit-Code $LASTEXITCODE"
    }
}

function Get-LatestReleaseDirectory {
    param(
        [string]$ComponentRoot
    )

    if (-not (Test-Path -LiteralPath $ComponentRoot -PathType Container)) {
        throw "Release-Verzeichnis nicht gefunden: $ComponentRoot"
    }

    $latest = Get-ChildItem -LiteralPath $ComponentRoot -Directory |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if ($null -eq $latest) {
        throw "Kein Release-Unterordner gefunden: $ComponentRoot"
    }

    return $latest.FullName
}

function Get-PrimaryAssetFile {
    param(
        [string]$AssetsRoot
    )

    if (-not (Test-Path -LiteralPath $AssetsRoot -PathType Container)) {
        throw "Asset-Verzeichnis nicht gefunden: $AssetsRoot"
    }

    $zipAsset = Get-ChildItem -LiteralPath $AssetsRoot -File | Where-Object { $_.Extension -eq ".zip" } | Select-Object -First 1

    if ($null -ne $zipAsset) {
        return $zipAsset.FullName
    }

    $singleAsset = Get-ChildItem -LiteralPath $AssetsRoot -File | Select-Object -First 1

    if ($null -eq $singleAsset) {
        throw "Keine Assets gefunden: $AssetsRoot"
    }

    throw "Kein ZIP-Asset gefunden. Aktuell wird fuer die Installation ein ZIP-Release erwartet: $($singleAsset.FullName)"
}

function Reset-DirectoryContents {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
        return
    }

    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
}

function Copy-DirectoryContents {
    param(
        [string]$SourceDir,
        [string]$TargetDir
    )

    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        throw "Quellverzeichnis nicht gefunden: $SourceDir"
    }

    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    Copy-Item -Path (Join-Path $SourceDir "*") -Destination $TargetDir -Recurse -Force
}

function Write-FileUtf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )

    $directoryPath = Split-Path -Parent $Path

    if (-not [string]::IsNullOrWhiteSpace($directoryPath)) {
        New-Item -ItemType Directory -Force -Path $directoryPath | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Expand-ReleaseArchive {
    param(
        [string]$ArchivePath,
        [string]$TargetDir
    )

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde $ArchivePath nach $TargetDir entpacken"
        return
    }

    Reset-DirectoryContents -Path $TargetDir
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $TargetDir -Force
    Write-Status "INFO" "Entpackt: $TargetDir"
}

function Get-FrontendDeploySource {
    param(
        [string]$ExpandedFrontendDir
    )

    $distDir = Join-Path $ExpandedFrontendDir "dist"

    if (Test-Path -LiteralPath $distDir -PathType Container) {
        return $distDir
    }

    return $ExpandedFrontendDir
}

function Test-CommandAvailable {
    param(
        [string]$Name
    )

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-PhpMinorVersion {
    $phpExecutable = Find-PhpExecutable

    if ([string]::IsNullOrWhiteSpace($phpExecutable)) {
        return ""
    }

    $versionLine = & $phpExecutable --version | Select-Object -First 1

    if ($versionLine -match 'PHP\s+(?<major>\d+)\.(?<minor>\d+)') {
        return "$($Matches.major).$($Matches.minor)"
    }

    return ""
}

function Get-PhpIniPath {
    param(
        [string]$PhpExecutable
    )

    if ([string]::IsNullOrWhiteSpace($PhpExecutable)) {
        return ""
    }

    $iniOutput = & $PhpExecutable --ini 2>$null

    foreach ($line in $iniOutput) {
        if ($line -match 'Loaded Configuration File:\s+(?<path>.+)$') {
            $candidate = $Matches.path.Trim()

            if ($candidate -ne "(none)" -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                return $candidate
            }
        }
    }

    $phpDir = Split-Path -Parent $PhpExecutable
    $directPhpIni = Join-Path $phpDir "php.ini"

    if (Test-Path -LiteralPath $directPhpIni -PathType Leaf) {
        return $directPhpIni
    }

    foreach ($templateName in @("php.ini-production", "php.ini-development")) {
        $templatePath = Join-Path $phpDir $templateName

        if (Test-Path -LiteralPath $templatePath -PathType Leaf) {
            if (-not $DryRun) {
                Copy-Item -LiteralPath $templatePath -Destination $directPhpIni -Force
            }

            return $directPhpIni
        }
    }

    return $directPhpIni
}

function Convert-ToVersion {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    if ($Value -match '^(?<major>\d+)\.(?<minor>\d+)(?:\.(?<patch>\d+))?$') {
        $patch = if ([string]::IsNullOrWhiteSpace($Matches.patch)) { "0" } else { $Matches.patch }
        return [version]"$($Matches.major).$($Matches.minor).$patch"
    }

    return $null
}

function Test-MinimumPhpVersion {
    param(
        [string]$VersionText
    )

    $versionValue = Convert-ToVersion -Value $VersionText

    if ($null -eq $versionValue) {
        return $false
    }

    return $versionValue -ge [version]"8.2.0"
}

function Install-WithWinget {
    param(
        [string]$PackageId,
        [string]$DisplayName
    )

    if (-not (Test-CommandAvailable -Name "winget")) {
        throw "winget ist fuer die Installation von $DisplayName nicht verfuegbar."
    }

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde $DisplayName ueber winget installieren ($PackageId)"
        return
    }

    $arguments = @(
        "install",
        "--source", "winget",
        "--exact",
        "--id", $PackageId,
        "--accept-source-agreements",
        "--accept-package-agreements",
        "--silent"
    )

    Write-Status "INFO" "Installiere $DisplayName ueber winget"
    & winget @arguments | Out-Host

    if ($LASTEXITCODE -ne 0) {
        throw "$DisplayName konnte nicht ueber winget installiert werden (Exit-Code $LASTEXITCODE)."
    }
}

function Install-WithChocolatey {
    param(
        [string]$PackageName,
        [string]$DisplayName,
        [string]$PackageVersion = "",
        [switch]$IgnoreDependencies
    )

    if (-not (Test-CommandAvailable -Name "choco")) {
        throw "Chocolatey ist fuer die Installation von $DisplayName nicht verfuegbar."
    }

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde $DisplayName ueber choco installieren ($PackageName)"
        return
    }

    $arguments = @(
        "install",
        $PackageName,
        "-y",
        "--no-progress"
    )

    if (-not [string]::IsNullOrWhiteSpace($PackageVersion)) {
        $arguments += @("--version", $PackageVersion)
    }

    if ($IgnoreDependencies) {
        $arguments += "--ignore-dependencies"
    }

    Write-Status "INFO" "Installiere $DisplayName ueber Chocolatey"
    & choco @arguments | Out-Host

    if ($LASTEXITCODE -ne 0) {
        throw "$DisplayName konnte nicht ueber Chocolatey installiert werden (Exit-Code $LASTEXITCODE)."
    }
}

function Install-Package {
    param(
        [string]$WingetId,
        [string]$ChocolateyName,
        [string]$DisplayName,
        [string]$ChocolateyVersion = "",
        [switch]$RequireWinget
    )

    if (Test-CommandAvailable -Name "winget") {
        try {
            Install-WithWinget -PackageId $WingetId -DisplayName $DisplayName
            return
        }
        catch {
            if (Test-CommandAvailable -Name "choco") {
                Write-Status "WARN" "$DisplayName konnte nicht ueber winget installiert werden. Fallback auf Chocolatey wird versucht."
                Install-WithChocolatey -PackageName $ChocolateyName -DisplayName $DisplayName -PackageVersion $ChocolateyVersion
                return
            }

            throw
        }
    }

    if ($RequireWinget) {
        if (Test-CommandAvailable -Name "choco") {
            Install-WithChocolatey -PackageName $ChocolateyName -DisplayName $DisplayName -PackageVersion $ChocolateyVersion
            return
        }

        throw "$DisplayName erfordert aktuell einen automatischen Paketmanager. Weder winget noch Chocolatey sind geeignet verfuegbar."
    }

    if (Test-CommandAvailable -Name "choco") {
        Install-WithChocolatey -PackageName $ChocolateyName -DisplayName $DisplayName -PackageVersion $ChocolateyVersion
        return
    }

    throw "Weder winget noch Chocolatey sind verfuegbar. $DisplayName kann nicht automatisch installiert werden."
}

function Find-CommandPath {
    param(
        [string]$Name
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue

    if ($null -eq $command) {
        return ""
    }

    return [string]$command.Source
}

function Find-PhpExecutable {
    $commandPath = Find-CommandPath -Name "php"

    if (-not [string]::IsNullOrWhiteSpace($commandPath)) {
        return $commandPath
    }

    $knownPaths = @(
        "C:\Program Files\PHP\v8.2\php.exe",
        "C:\Program Files\PHP\php.exe",
        "C:\tools\php82\php.exe",
        "C:\php\php.exe"
    )

    foreach ($candidate in $knownPaths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return ""
}

function Find-PhpCgiExecutable {
    $phpExecutable = Find-PhpExecutable

    if (-not [string]::IsNullOrWhiteSpace($phpExecutable)) {
        $sibling = Join-Path (Split-Path -Parent $phpExecutable) "php-cgi.exe"

        if (Test-Path -LiteralPath $sibling -PathType Leaf) {
            return $sibling
        }
    }

    $knownPaths = @(
        "C:\Program Files\PHP\v8.2\php-cgi.exe",
        "C:\Program Files\PHP\php-cgi.exe",
        "C:\tools\php82\php-cgi.exe",
        "C:\php\php-cgi.exe"
    )

    foreach ($candidate in $knownPaths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return ""
}

function Find-MariaDbClientExecutable {
    $commands = @("mysql", "mariadb")

    foreach ($commandName in $commands) {
        $commandPath = Find-CommandPath -Name $commandName

        if (-not [string]::IsNullOrWhiteSpace($commandPath)) {
            return $commandPath
        }
    }

    $knownMatches = Get-ChildItem -Path "C:\Program Files\MariaDB*" -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName "bin\mysql.exe" } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1

    if ($null -ne $knownMatches) {
        return [string]$knownMatches
    }

    return ""
}

function Find-MariaDbBaseDirectory {
    $knownMatches = Get-ChildItem -Path "C:\Program Files\MariaDB*" -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if ($null -ne $knownMatches) {
        return [string]$knownMatches.FullName
    }

    return ""
}

function Find-MariaDbServerExecutable {
    $baseDirectory = Find-MariaDbBaseDirectory

    if ([string]::IsNullOrWhiteSpace($baseDirectory)) {
        return ""
    }

    $candidate = Join-Path $baseDirectory "bin\mysqld.exe"

    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return $candidate
    }

    return ""
}

function Get-MariaDbService {
    $service = Get-Service | Where-Object {
        $_.Name -like "*MariaDB*" -or
        $_.DisplayName -like "*MariaDB*" -or
        $_.Name -like "*MySQL*" -or
        $_.DisplayName -like "*MySQL*"
    } | Select-Object -First 1

    return $service
}

function Find-ComposerExecutable {
    $commandPath = Find-CommandPath -Name "composer"

    if (-not [string]::IsNullOrWhiteSpace($commandPath)) {
        return $commandPath
    }

    $knownPaths = @(
        "C:\ProgramData\ComposerSetup\bin\composer.bat",
        "C:\ProgramData\chocolatey\bin\composer.bat"
    )

    foreach ($candidate in $knownPaths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return ""
}

function Find-NssmExecutable {
    $commandPath = Find-CommandPath -Name "nssm"

    if (-not [string]::IsNullOrWhiteSpace($commandPath)) {
        return $commandPath
    }

    $knownPaths = @(
        "C:\ProgramData\chocolatey\bin\nssm.exe",
        "C:\tools\nssm\win64\nssm.exe",
        "C:\tools\nssm\win32\nssm.exe"
    )

    foreach ($candidate in $knownPaths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return ""
}

function Find-NginxExecutable {
    $commandPath = Find-CommandPath -Name "nginx"

    if (-not [string]::IsNullOrWhiteSpace($commandPath) -and (Test-Path -LiteralPath $commandPath -PathType Leaf)) {
        return $commandPath
    }

    $knownPaths = @(
        "C:\Program Files\nginx\nginx.exe",
        "C:\Program Files (x86)\nginx\nginx.exe",
        "C:\tools\nginx\nginx.exe"
    )

    foreach ($candidate in $knownPaths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $packageRoots = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps")
    )

    foreach ($packageRoot in $packageRoots) {
        if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
            continue
        }

        $packageCandidate = Get-ChildItem -LiteralPath $packageRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "nginxinc.nginx*" -or $_.Name -like "freenginx.nginx*" } |
            ForEach-Object {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -Filter "nginx.exe" -ErrorAction SilentlyContinue
            } |
            Select-Object -First 1

        if ($null -ne $packageCandidate) {
            return $packageCandidate.FullName
        }
    }

    return ""
}

function Get-NginxRoot {
    param(
        [string]$NginxExecutable
    )

    if ([string]::IsNullOrWhiteSpace($NginxExecutable)) {
        throw "Nginx-Executable ist leer."
    }

    return (Split-Path -Parent $NginxExecutable)
}

function Ensure-Php82Installed {
    param(
        [pscustomobject]$Context
    )

    $installedVersion = Get-PhpMinorVersion
    $constraint = Get-BackendPhpConstraint -Context $Context

    if (-not [string]::IsNullOrWhiteSpace($installedVersion) -and (Test-MinimumPhpVersion -VersionText $installedVersion)) {
        if (Test-PhpVersionAgainstConstraint -VersionText $installedVersion -Constraint $constraint) {
            if ([string]::IsNullOrWhiteSpace($constraint)) {
                Write-Status "PASS" "PHP $installedVersion ist vorhanden (>= 8.2)"
            }
            else {
                Write-Status "PASS" "PHP $installedVersion ist vorhanden und erfuellt die Backend-Anforderung '$constraint'"
            }

            return (Find-PhpExecutable)
        }

        throw "PHP $installedVersion ist zwar >= 8.2, erfuellt aber die Backend-Anforderung '$constraint' nicht. Bitte eine kompatible PHP-Version manuell installieren."
    }

    if (-not [string]::IsNullOrWhiteSpace($installedVersion)) {
        Write-Status "WARN" "Gefundene PHP-Version $installedVersion ist kleiner als 8.2 und wird aufgeruestet"
    }
    else {
        Write-Status "INFO" "Es ist noch keine geeignete PHP-Version (>= 8.2) vorhanden"
    }

    Install-Package -WingetId "PHP.PHP.8.2" -ChocolateyName "php" -DisplayName "PHP 8.2" -ChocolateyVersion "8.2.30" -RequireWinget

    if ($DryRun) {
        return ""
    }

    $resolvedVersion = Get-PhpMinorVersion

    if (-not (Test-MinimumPhpVersion -VersionText $resolvedVersion)) {
        throw "Es konnte keine geeignete PHP-Version >= 8.2 bereitgestellt werden. Aktuell erkannt: $resolvedVersion"
    }

    if (-not (Test-PhpVersionAgainstConstraint -VersionText $resolvedVersion -Constraint $constraint)) {
        throw "Die bereitgestellte PHP-Version $resolvedVersion erfuellt die Backend-Anforderung '$constraint' nicht. Bitte manuell eine kompatible Version installieren."
    }

    if ([string]::IsNullOrWhiteSpace($constraint)) {
        Write-Status "PASS" "PHP $resolvedVersion ist verfuegbar (>= 8.2)"
    }
    else {
        Write-Status "PASS" "PHP $resolvedVersion ist verfuegbar und erfuellt '$constraint'"
    }

    return (Find-PhpExecutable)
}

function Ensure-ComposerInstalled {
    $composerExecutable = Find-ComposerExecutable

    if (-not [string]::IsNullOrWhiteSpace($composerExecutable)) {
        Write-Status "PASS" "Composer ist bereits vorhanden: $composerExecutable"
        return $composerExecutable
    }

    if (Test-CommandAvailable -Name "choco") {
        Install-WithChocolatey -PackageName "composer" -DisplayName "Composer" -IgnoreDependencies
    }
    elseif (Test-CommandAvailable -Name "winget") {
        throw "Composer ist nicht vorhanden. Fuer Composer ist aktuell nur Chocolatey als automatischer Installationspfad hinterlegt."
    }
    else {
        throw "Weder Chocolatey noch ein vorhandener Composer wurden gefunden."
    }

    if ($DryRun) {
        return ""
    }

    $composerExecutable = Find-ComposerExecutable

    if ([string]::IsNullOrWhiteSpace($composerExecutable)) {
        throw "Composer wurde installiert, aber nicht gefunden."
    }

    Write-Status "PASS" "Composer ist verfuegbar: $composerExecutable"
    return $composerExecutable
}

function Enable-PhpIniExtension {
    param(
        [string[]]$Lines,
        [string]$ExtensionName
    )

    $patterns = @(
        "extension=$ExtensionName",
        "extension=php_$ExtensionName.dll"
    )

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $trimmed = $Lines[$index].Trim()

        if ($trimmed -match '^[;#]\s*extension\s*=') {
            foreach ($pattern in $patterns) {
                if ($trimmed -match [regex]::Escape($pattern)) {
                    $Lines[$index] = $pattern
                    return $Lines
                }
            }
        }

        foreach ($pattern in $patterns) {
            if ($trimmed -eq $pattern) {
                return $Lines
            }
        }
    }

    return $Lines + $patterns[0]
}

function Ensure-PhpRuntimeConfiguration {
    param(
        [string]$PhpExecutable
    )

    if ([string]::IsNullOrWhiteSpace($PhpExecutable)) {
        throw "PHP-Konfiguration kann nicht vorbereitet werden, weil php.exe nicht verfuegbar ist."
    }

    $phpIniPath = Get-PhpIniPath -PhpExecutable $PhpExecutable

    if ([string]::IsNullOrWhiteSpace($phpIniPath)) {
        throw "php.ini konnte nicht ermittelt werden."
    }

    $phpDir = Split-Path -Parent $PhpExecutable
    $extensionDir = Join-Path $phpDir "ext"

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde PHP-Konfiguration in $phpIniPath vorbereiten"
        return
    }

    if (-not (Test-Path -LiteralPath $phpIniPath -PathType Leaf)) {
        throw "php.ini wurde nicht gefunden und konnte nicht automatisch erzeugt werden: $phpIniPath"
    }

    $lines = @(Get-Content -LiteralPath $phpIniPath)
    $extensionDirConfigured = $false

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $trimmed = $lines[$index].Trim()

        if ($trimmed -match '^[;#]?\s*extension_dir\s*=') {
            $lines[$index] = "extension_dir = ""$extensionDir"""
            $extensionDirConfigured = $true
            break
        }
    }

    if (-not $extensionDirConfigured) {
        $lines += "extension_dir = ""$extensionDir"""
    }

    foreach ($extensionName in @("fileinfo", "mbstring", "openssl", "pdo_mysql", "mysqli")) {
        $lines = Enable-PhpIniExtension -Lines $lines -ExtensionName $extensionName
    }

    Set-Content -LiteralPath $phpIniPath -Value $lines -Encoding UTF8
    Write-Status "INFO" "PHP-Konfiguration vorbereitet: $phpIniPath"
}

function Ensure-NginxInstalled {
    $nginxExecutable = Find-NginxExecutable

    if (-not [string]::IsNullOrWhiteSpace($nginxExecutable)) {
        Write-Status "PASS" "Nginx ist bereits vorhanden: $nginxExecutable"
        return $nginxExecutable
    }

    Install-Package -WingetId "nginxinc.nginx" -ChocolateyName "nginx" -DisplayName "Nginx"

    if ($DryRun) {
        return ""
    }

    $nginxExecutable = Find-NginxExecutable

    if ([string]::IsNullOrWhiteSpace($nginxExecutable)) {
        throw "Nginx wurde installiert, aber nginx.exe konnte nicht gefunden werden."
    }

    Write-Status "PASS" "Nginx ist verfuegbar: $nginxExecutable"
    return $nginxExecutable
}

function Wait-ForTcpPort {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $client = New-Object System.Net.Sockets.TcpClient

        try {
            $asyncResult = $client.BeginConnect($HostName, $Port, $null, $null)

            if ($asyncResult.AsyncWaitHandle.WaitOne(1000)) {
                $client.EndConnect($asyncResult)
                return $true
            }
        }
        catch {
        }
        finally {
            $client.Dispose()
        }

        Start-Sleep -Seconds 1
    }

    return $false
}

function Register-MariaDbService {
    $mysqldExecutable = Find-MariaDbServerExecutable

    if ([string]::IsNullOrWhiteSpace($mysqldExecutable)) {
        throw "mysqld.exe wurde nicht gefunden. MariaDB-Dienst kann nicht registriert werden."
    }

    $baseDirectory = Split-Path -Parent (Split-Path -Parent $mysqldExecutable)
    $defaultsFile = Join-Path $baseDirectory "data\my.ini"
    $serviceName = "MariaDB"

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde MariaDB-Dienst ueber mysqld.exe registrieren"
        return
    }

    $arguments = @("--install", $serviceName)

    if (Test-Path -LiteralPath $defaultsFile -PathType Leaf) {
        $arguments += "--defaults-file=$defaultsFile"
    }

    & $mysqldExecutable @arguments | Out-Host

    if ($LASTEXITCODE -ne 0) {
        throw "MariaDB-Dienst konnte nicht ueber mysqld.exe registriert werden (Exit-Code $LASTEXITCODE)."
    }
}

function Ensure-MariaDbInstalled {
    param(
        [pscustomobject]$Context
    )

    if (-not $Context.UseLocalDatabase) {
        Write-Status "INFO" "Remote-Datenbank ausgewaehlt: $($Context.DatabaseHost):$($Context.DatabasePort)"
        return
    }

    $service = Get-MariaDbService

    if ($null -ne $service) {
        Write-Status "PASS" "MariaDB-Service ist bereits vorhanden"
        if ($service.Status -ne "Running" -and -not $DryRun) {
            Start-Service -Name $service.Name
        }

        if (-not (Wait-ForTcpPort -HostName "127.0.0.1" -Port 3306 -TimeoutSeconds 20)) {
            throw "MariaDB-Dienst ist vorhanden, aber Port 3306 wird nicht geoeffnet."
        }

        return
    }

    Install-Package -WingetId "MariaDB.Server" -ChocolateyName "mariadb" -DisplayName "MariaDB Server"

    if ($DryRun) {
        return
    }

    $service = Get-MariaDbService

    if ($null -eq $service) {
        Write-Status "WARN" "MariaDB wurde installiert, aber kein Dienst gefunden. Dienst wird jetzt registriert."
        Register-MariaDbService
        $service = Get-MariaDbService
    }

    if ($null -eq $service) {
        throw "MariaDB wurde installiert, aber es konnte kein Windows-Dienst gefunden oder registriert werden."
    }

    if ($service.Status -ne "Running") {
        Start-Service -Name $service.Name
    }

    if (-not (Wait-ForTcpPort -HostName "127.0.0.1" -Port 3306 -TimeoutSeconds 20)) {
        throw "MariaDB-Dienst wurde gestartet, aber Port 3306 ist nicht erreichbar."
    }

    Write-Status "PASS" "MariaDB ist verfuegbar"
}

function Convert-ToSqlStringLiteral {
    param(
        [string]$Value
    )

    return ($Value -replace "'", "''")
}

function Convert-ToSqlIdentifier {
    param(
        [string]$Value
    )

    return ($Value.Replace('`', '``'))
}

function Deploy-Application {
    param(
        [pscustomobject]$Context,
        [string]$ExpandedBackendDir,
        [string]$ExpandedFrontendDir
    )

    $appRoot = $Context.InstallRoot
    $backendTarget = Join-Path $appRoot "backend"
    $frontendTarget = Join-Path $backendTarget "public"
    $frontendSource = Get-FrontendDeploySource -ExpandedFrontendDir $ExpandedFrontendDir

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde Backend nach $backendTarget kopieren"
        Write-Status "INFO" "Dry-run: wuerde Frontend nach $frontendTarget kopieren"
        return
    }

    Reset-DirectoryContents -Path $backendTarget
    Copy-DirectoryContents -SourceDir $ExpandedBackendDir -TargetDir $backendTarget
    Reset-DirectoryContents -Path $frontendTarget
    Copy-DirectoryContents -SourceDir $frontendSource -TargetDir $frontendTarget

    Write-Status "INFO" "Backend bereitgestellt: $backendTarget"
    Write-Status "INFO" "Frontend in public bereitgestellt: $frontendTarget"
}

function Get-ApplicationRoot {
    param(
        [string]$BackendTarget
    )

    $artisanPath = Join-Path $BackendTarget "artisan"

    if (Test-Path -LiteralPath $artisanPath -PathType Leaf) {
        return $BackendTarget
    }

    $nestedRoot = Get-ChildItem -LiteralPath $BackendTarget -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "artisan") -PathType Leaf } |
        Select-Object -First 1

    if ($null -ne $nestedRoot) {
        return $nestedRoot.FullName
    }

    return $BackendTarget
}

function Convert-ToNginxPath {
    param(
        [string]$Path
    )

    return ($Path -replace "\\", "/")
}

function Convert-ToEnvValue {
    param(
        [string]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    $text = [string]$Value
    $text = $text -replace "`r", ""
    $text = $text -replace "`n", "\n"
    $text = $text -replace '"', '\"'
    return $text
}

function Get-ApplicationUrl {
    param(
        [pscustomobject]$Context
    )

    $scheme = "http"

    if ($Context.UseSsl) {
        $scheme = "https"
    }

    return "${scheme}://$($Context.PrimaryDomain)"
}

function Get-BackendPhpConstraint {
    param(
        [pscustomobject]$Context
    )

    if ($DryRun) {
        return ""
    }

    $appRoot = Get-ApplicationRoot -BackendTarget (Join-Path $Context.InstallRoot "backend")
    $composerManifest = Join-Path $appRoot "composer.json"

    if (-not (Test-Path -LiteralPath $composerManifest -PathType Leaf)) {
        return ""
    }

    try {
        $composer = Get-Content -LiteralPath $composerManifest -Raw | ConvertFrom-Json
        $requireNode = $composer.PSObject.Properties["require"]

        if ($null -eq $requireNode -or $null -eq $requireNode.Value) {
            return ""
        }

        $phpNode = $requireNode.Value.PSObject.Properties["php"]

        if ($null -eq $phpNode -or $null -eq $phpNode.Value) {
            return ""
        }

        return [string]$phpNode.Value
    }
    catch {
        Write-Status "WARN" "composer.json konnte nicht fuer die PHP-Anforderung gelesen werden."
        return ""
    }
}

function Test-PhpConstraintToken {
    param(
        [version]$VersionValue,
        [string]$Token
    )

    $trimmed = $Token.Trim()

    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -eq "*") {
        return $true
    }

    if ($trimmed -match '^\^(?<version>\d+\.\d+(?:\.\d+)?)$') {
        $lower = Convert-ToVersion -Value $Matches.version
        $parts = $Matches.version.Split('.')
        $major = [int]$parts[0]
        $upper = [version]"$($major + 1).0.0"
        return ($VersionValue -ge $lower -and $VersionValue -lt $upper)
    }

    if ($trimmed -match '^~(?<version>\d+\.\d+(?:\.\d+)?)$') {
        $lower = Convert-ToVersion -Value $Matches.version
        $parts = $Matches.version.Split('.')
        $major = [int]$parts[0]
        $minor = [int]$parts[1]
        $upper = [version]"$major.$($minor + 1).0"
        return ($VersionValue -ge $lower -and $VersionValue -lt $upper)
    }

    if ($trimmed -match '^(?<operator>>=|<=|>|<|=)?\s*(?<version>\d+\.\d+(?:\.\d+)?)$') {
        $operator = $Matches.operator
        $target = Convert-ToVersion -Value $Matches.version

        switch ($operator) {
            ">=" { return $VersionValue -ge $target }
            "<=" { return $VersionValue -le $target }
            ">" { return $VersionValue -gt $target }
            "<" { return $VersionValue -lt $target }
            "=" { return $VersionValue -eq $target }
            default {
                $parts = $Matches.version.Split('.')
                if ($parts.Length -eq 2) {
                    $upper = [version]"$($parts[0]).$([int]$parts[1] + 1).0"
                    return ($VersionValue -ge $target -and $VersionValue -lt $upper)
                }

                return $VersionValue -eq $target
            }
        }
    }

    return $false
}

function Test-PhpConstraintGroup {
    param(
        [version]$VersionValue,
        [string]$ConstraintGroup
    )

    $tokens = $ConstraintGroup -split '\s*,\s*|\s+'

    foreach ($token in $tokens) {
        if ([string]::IsNullOrWhiteSpace($token)) {
            continue
        }

        if (-not (Test-PhpConstraintToken -VersionValue $VersionValue -Token $token)) {
            return $false
        }
    }

    return $true
}

function Test-PhpVersionAgainstConstraint {
    param(
        [string]$VersionText,
        [string]$Constraint
    )

    if ([string]::IsNullOrWhiteSpace($Constraint)) {
        return $true
    }

    $versionValue = Convert-ToVersion -Value $VersionText

    if ($null -eq $versionValue) {
        return $false
    }

    $groups = $Constraint -split '\|\|'

    foreach ($group in $groups) {
        if (Test-PhpConstraintGroup -VersionValue $versionValue -ConstraintGroup $group) {
            return $true
        }
    }

    return $false
}

function Write-EnvironmentFile {
    param(
        [pscustomobject]$Context
    )

    $backendTarget = Join-Path $Context.InstallRoot "backend"
    $envPath = Join-Path $backendTarget ".env"
    $databaseHost = $Context.DatabaseHost

    if ($Context.UseLocalDatabase) {
        $databaseHost = "127.0.0.1"
    }

    $mailMailer = "log"
    $mailHost = "127.0.0.1"
    $mailPort = "2525"
    $mailUser = ""
    $mailPassword = ""
    $mailEncryption = ""
    $mailFrom = $Context.AdminEmail

    if ($Context.EnableSmtp) {
        $mailMailer = "smtp"
        $mailHost = $Context.SmtpHost
        $mailPort = $Context.SmtpPort
        $mailUser = $Context.SmtpUser
        $mailPassword = $Context.SmtpPassword
        $mailEncryption = $Context.SmtpEncryption
        $mailFrom = $Context.MailFromAddress
    }

    $lines = @(
        "APP_NAME=""TenantPlatform""",
        "APP_ENV=production",
        "APP_KEY=",
        "APP_DEBUG=false",
        "APP_URL=""$(Convert-ToEnvValue -Value (Get-ApplicationUrl -Context $Context))""",
        "ADMIN_EMAIL=""$(Convert-ToEnvValue -Value $Context.AdminEmail)""",
        "ADMIN_PASSWORD=""$(Convert-ToEnvValue -Value $Context.AdminPassword)""",
        "DB_CONNECTION=mysql",
        "DB_HOST=""$(Convert-ToEnvValue -Value $databaseHost)""",
        "DB_PORT=$($Context.DatabasePort)",
        "DB_DATABASE=""$(Convert-ToEnvValue -Value $Context.DatabaseName)""",
        "DB_USERNAME=""$(Convert-ToEnvValue -Value $Context.DatabaseUser)""",
        "DB_PASSWORD=""$(Convert-ToEnvValue -Value $Context.DatabasePassword)""",
        "MAIL_MAILER=$mailMailer",
        "MAIL_HOST=""$(Convert-ToEnvValue -Value $mailHost)""",
        "MAIL_PORT=$mailPort",
        "MAIL_USERNAME=""$(Convert-ToEnvValue -Value $mailUser)""",
        "MAIL_PASSWORD=""$(Convert-ToEnvValue -Value $mailPassword)""",
        "MAIL_ENCRYPTION=""$(Convert-ToEnvValue -Value $mailEncryption)""",
        "MAIL_FROM_ADDRESS=""$(Convert-ToEnvValue -Value $mailFrom)"""
    )

    if (-not [string]::IsNullOrWhiteSpace($Context.TenantId)) {
        $lines += "TENANT_ID=""$(Convert-ToEnvValue -Value $Context.TenantId)"""
    }

    if (-not [string]::IsNullOrWhiteSpace($Context.LicenseKeys)) {
        $lines += "LICENSE_KEYS=""$(Convert-ToEnvValue -Value $Context.LicenseKeys)"""
    }

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde .env nach $envPath schreiben"
        return
    }

    $appRoot = Get-ApplicationRoot -BackendTarget $backendTarget
    $envPath = Join-Path $appRoot ".env"

    $content = $lines -join "`r`n"
    Set-Content -LiteralPath $envPath -Value $content -Encoding UTF8
    Write-Status "INFO" ".env geschrieben: $envPath"
}

function Invoke-ComposerInstall {
    param(
        [pscustomobject]$Context,
        [string]$ComposerExecutable
    )

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde 'composer install' im bereitgestellten Backend ausfuehren"
        return
    }

    $appRoot = Get-ApplicationRoot -BackendTarget (Join-Path $Context.InstallRoot "backend")
    $composerManifest = Join-Path $appRoot "composer.json"

    if (-not (Test-Path -LiteralPath $composerManifest -PathType Leaf)) {
        Write-Status "WARN" "Kein composer.json gefunden. Composer-Install wird uebersprungen."
        return
    }

    if ([string]::IsNullOrWhiteSpace($ComposerExecutable)) {
        throw "Composer-Install wurde angefordert, aber Composer ist nicht verfuegbar."
    }

    $arguments = @(
        "install",
        "--no-interaction",
        "--prefer-dist",
        "--optimize-autoloader"
    )

    Write-Status "INFO" "Fuehre Composer-Install aus"
    Push-Location -LiteralPath $appRoot
    try {
        & $ComposerExecutable @arguments

        if ($LASTEXITCODE -ne 0) {
            throw "composer install ist fehlgeschlagen (Exit-Code $LASTEXITCODE)."
        }
    }
    finally {
        Pop-Location
    }

    Write-Status "INFO" "Composer-Abhaengigkeiten installiert"
}

function Invoke-ArtisanCommand {
    param(
        [string]$PhpExecutable,
        [string]$AppRoot,
        [string[]]$Arguments,
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($PhpExecutable)) {
        throw "$Description kann nicht ausgefuehrt werden, weil php.exe nicht verfuegbar ist."
    }

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde $Description ausfuehren"
        return
    }

    Push-Location -LiteralPath $AppRoot
    try {
        & $PhpExecutable "artisan" @Arguments

        if ($LASTEXITCODE -ne 0) {
            throw "$Description ist fehlgeschlagen (Exit-Code $LASTEXITCODE)."
        }
    }
    finally {
        Pop-Location
    }
}

function Ensure-LaravelWritablePaths {
    param(
        [pscustomobject]$Context
    )

    $appRoot = Get-ApplicationRoot -BackendTarget (Join-Path $Context.InstallRoot "backend")
    $requiredDirectories = @(
        (Join-Path $appRoot "bootstrap\cache"),
        (Join-Path $appRoot "storage\app"),
        (Join-Path $appRoot "storage\app\public"),
        (Join-Path $appRoot "storage\framework"),
        (Join-Path $appRoot "storage\framework\cache"),
        (Join-Path $appRoot "storage\framework\cache\data"),
        (Join-Path $appRoot "storage\framework\sessions"),
        (Join-Path $appRoot "storage\framework\views"),
        (Join-Path $appRoot "storage\logs")
    )

    if ($DryRun) {
        foreach ($directoryPath in $requiredDirectories) {
            Write-Status "INFO" "Dry-run: wuerde Laravel-Verzeichnis sicherstellen: $directoryPath"
        }

        return
    }

    foreach ($directoryPath in $requiredDirectories) {
        New-Item -ItemType Directory -Force -Path $directoryPath | Out-Null
    }

    Write-Status "INFO" "Laravel-Verzeichnisse vorbereitet"
}

function Invoke-LaravelBootstrap {
    param(
        [pscustomobject]$Context,
        [string]$PhpExecutable
    )

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde Laravel-Bootstrap (key:generate, migrate, cache/storage) ausfuehren"
        return
    }

    $appRoot = Get-ApplicationRoot -BackendTarget (Join-Path $Context.InstallRoot "backend")
    $artisanPath = Join-Path $appRoot "artisan"

    if (-not (Test-Path -LiteralPath $artisanPath -PathType Leaf)) {
        Write-Status "WARN" "Kein Laravel-Artisan gefunden. Laravel-Bootstrap wird uebersprungen."
        return
    }

    Ensure-LaravelWritablePaths -Context $Context
    Invoke-ArtisanCommand -PhpExecutable $PhpExecutable -AppRoot $appRoot -Arguments @("key:generate", "--force") -Description "php artisan key:generate"
    Invoke-ArtisanCommand -PhpExecutable $PhpExecutable -AppRoot $appRoot -Arguments @("config:clear") -Description "php artisan config:clear"
    Invoke-ArtisanCommand -PhpExecutable $PhpExecutable -AppRoot $appRoot -Arguments @("cache:clear") -Description "php artisan cache:clear"
    Invoke-ArtisanCommand -PhpExecutable $PhpExecutable -AppRoot $appRoot -Arguments @("storage:link") -Description "php artisan storage:link"
    Invoke-ArtisanCommand -PhpExecutable $PhpExecutable -AppRoot $appRoot -Arguments @("migrate", "--force") -Description "php artisan migrate --force"
}

function Ensure-PhpFastCgiNssmService {
    param(
        [pscustomobject]$Context
    )

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde einen NSSM-Service fuer php-cgi.exe auf 127.0.0.1:9000 einrichten"
        return
    }

    $phpCgiExecutable = Find-PhpCgiExecutable

    if ([string]::IsNullOrWhiteSpace($phpCgiExecutable)) {
        throw "php-cgi.exe wurde nicht gefunden. Der NSSM-Service kann nicht eingerichtet werden."
    }

    $nssmExecutable = Find-NssmExecutable

    if ([string]::IsNullOrWhiteSpace($nssmExecutable)) {
        if (Test-CommandAvailable -Name "choco") {
            Install-WithChocolatey -PackageName "nssm" -DisplayName "NSSM"
        }
        else {
            throw "NSSM wurde nicht gefunden und Chocolatey ist fuer die Installation nicht verfuegbar."
        }
    }

    $nssmExecutable = Find-NssmExecutable

    if ([string]::IsNullOrWhiteSpace($nssmExecutable)) {
        throw "NSSM wurde installiert, aber nssm.exe konnte nicht gefunden werden."
    }

    $serviceName = "TenantPhpFastCgi"
    $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

    if ($null -eq $existingService) {
        & $nssmExecutable install $serviceName $phpCgiExecutable "-b" "127.0.0.1:9000" | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "NSSM konnte den Dienst $serviceName nicht anlegen."
        }
    }

    & $nssmExecutable set $serviceName AppDirectory (Split-Path -Parent $phpCgiExecutable) | Out-Null
    & $nssmExecutable set $serviceName Start SERVICE_AUTO_START | Out-Null

    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    Write-Status "INFO" "PHP-FastCGI-Service ueber NSSM eingerichtet: $serviceName"
}

function Ensure-PhpFastCgiScheduledTask {
    param(
        [pscustomobject]$Context
    )

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde einen Scheduled Task fuer php-cgi.exe auf 127.0.0.1:9000 einrichten"
        return
    }

    $phpCgiExecutable = Find-PhpCgiExecutable

    if ([string]::IsNullOrWhiteSpace($phpCgiExecutable)) {
        throw "php-cgi.exe wurde nicht gefunden. Der FastCGI-Starttask kann nicht eingerichtet werden."
    }

    $launcherRoot = Join-Path $Context.InstallRoot "installer"
    $launcherPath = Join-Path $launcherRoot "start-php-fastcgi.ps1"
    $taskName = "TenantInstaller-PHP-FastCGI"
    $phpDir = Split-Path -Parent $phpCgiExecutable

    $launcherContent = @"
param()

\$existing = Get-CimInstance Win32_Process -Filter "Name = 'php-cgi.exe'" -ErrorAction SilentlyContinue |
    Where-Object { \$_.CommandLine -like '*127.0.0.1:9000*' }

if (\$null -eq \$existing) {
    Start-Process -FilePath "$phpCgiExecutable" -ArgumentList @('-b', '127.0.0.1:9000') -WorkingDirectory "$phpDir" -WindowStyle Hidden
}
"@

    New-Item -ItemType Directory -Force -Path $launcherRoot | Out-Null
    Set-Content -LiteralPath $launcherPath -Value $launcherContent -Encoding UTF8

    $taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$launcherPath`""

    & schtasks.exe /Create /TN $taskName /SC ONSTART /RU SYSTEM /TR $taskCommand /F | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Geplanter Task fuer PHP-FastCGI konnte nicht erstellt werden."
    }

    & schtasks.exe /Run /TN $taskName | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Geplanter Task fuer PHP-FastCGI konnte nicht gestartet werden."
    }

    Write-Status "INFO" "PHP-FastCGI-Starttask eingerichtet: $taskName"
}

function Ensure-PhpFastCgiRunner {
    param(
        [pscustomobject]$Context
    )

    if ($Context.PhpRuntimeMode -eq "Nssm") {
        Ensure-PhpFastCgiNssmService -Context $Context
        return
    }

    Ensure-PhpFastCgiScheduledTask -Context $Context
}

function Invoke-MariaDbStatement {
    param(
        [string]$ClientExecutable,
        [string]$Sql
    )

    $arguments = @(
        "-u", "root",
        "-h", "127.0.0.1",
        "--protocol=TCP",
        "--execute", $Sql
    )

    if (-not [string]::IsNullOrWhiteSpace($env:MARIADB_ROOT_PASSWORD)) {
        $arguments = @("-u", "root", "-h", "127.0.0.1", "-p$($env:MARIADB_ROOT_PASSWORD)", "--protocol=TCP", "--execute", $Sql)
    }

    & $ClientExecutable @arguments | Out-Null
    return $LASTEXITCODE
}

function Ensure-MariaDbProvisioning {
    param(
        [pscustomobject]$Context
    )

    if (-not $Context.UseLocalDatabase) {
        return
    }

    $clientExecutable = Find-MariaDbClientExecutable

    if ([string]::IsNullOrWhiteSpace($clientExecutable)) {
        Write-Status "WARN" "MariaDB-Client wurde nicht gefunden. Datenbank und Benutzer konnten nicht automatisch angelegt werden."
        return
    }

    $databaseName = Convert-ToSqlIdentifier -Value $Context.DatabaseName
    $databaseUser = Convert-ToSqlStringLiteral -Value $Context.DatabaseUser
    $databasePassword = Convert-ToSqlStringLiteral -Value $Context.DatabasePassword
    $sql = @(
        "CREATE DATABASE IF NOT EXISTS ``$databaseName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;",
        "CREATE USER IF NOT EXISTS '$databaseUser'@'localhost' IDENTIFIED BY '$databasePassword';",
        "CREATE USER IF NOT EXISTS '$databaseUser'@'%' IDENTIFIED BY '$databasePassword';",
        "GRANT ALL PRIVILEGES ON ``$databaseName``.* TO '$databaseUser'@'localhost';",
        "GRANT ALL PRIVILEGES ON ``$databaseName``.* TO '$databaseUser'@'%';",
        "FLUSH PRIVILEGES;"
    ) -join " "

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde MariaDB-Datenbank und Benutzer provisionieren"
        return
    }

    $exitCode = Invoke-MariaDbStatement -ClientExecutable $clientExecutable -Sql $sql

    if ($exitCode -ne 0) {
        Write-Status "WARN" "MariaDB-Provisionierung ist fehlgeschlagen. Falls fuer root ein Passwort gesetzt ist, setze MARIADB_ROOT_PASSWORD und starte den Lauf erneut."
        return
    }

    Write-Status "INFO" "MariaDB-Datenbank und Benutzer wurden angelegt"
}

function Test-DatabaseConnectivity {
    param(
        [pscustomobject]$Context
    )

    $hostName = $Context.DatabaseHost

    if ($Context.UseLocalDatabase) {
        $hostName = "127.0.0.1"
    }

    $port = 0

    if (-not [int]::TryParse([string]$Context.DatabasePort, [ref]$port)) {
        throw "DatabasePort ist keine gueltige Portnummer: $($Context.DatabasePort)"
    }

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde Datenbank-Verbindung zu ${hostName}:$port pruefen"
        return
    }

    $client = New-Object System.Net.Sockets.TcpClient

    try {
        $asyncResult = $client.BeginConnect($hostName, $port, $null, $null)
        $connected = $asyncResult.AsyncWaitHandle.WaitOne(5000)

        if (-not $connected) {
            throw "Zeitueberschreitung"
        }

        $client.EndConnect($asyncResult)
        Write-Status "INFO" "Datenbank-Verbindung erreichbar: ${hostName}:$port"
    }
    catch {
        if ($Context.UseLocalDatabase) {
            throw "Die lokal vorgesehene MariaDB ist auf ${hostName}:$port nicht erreichbar. Bitte lokale Datenbankinstallation pruefen."
        }

        throw "Die konfigurierte Remote-Datenbank ist auf ${hostName}:$port nicht erreichbar. Bitte Host, Port und Firewall pruefen."
    }
    finally {
        $client.Dispose()
    }
}

function Set-NginxConfiguration {
    param(
        [pscustomobject]$Context,
        [string]$NginxExecutable
    )

    if ([string]::IsNullOrWhiteSpace($NginxExecutable)) {
        if ($DryRun) {
            Write-Status "INFO" "Dry-run: ueberspringe konkrete Nginx-Konfiguration ohne nginx.exe-Pfad"
            return
        }

        throw "Nginx-Konfiguration konnte nicht erstellt werden, weil nginx.exe nicht gefunden wurde."
    }

    $nginxRoot = Get-NginxRoot -NginxExecutable $NginxExecutable
    $confPath = Join-Path $nginxRoot "conf\nginx.conf"
    $appRoot = Get-ApplicationRoot -BackendTarget (Join-Path $Context.InstallRoot "backend")
    $publicRoot = Convert-ToNginxPath -Path (Join-Path $appRoot "public")
    $sslNote = ""

    if ($Context.UseSsl) {
        $sslNote = "        # SSL wurde im Wizard angefordert. Zertifikat und 443-Listener muessen im naechsten Schritt ergaenzt werden.`r`n"
    }

    $configContent = @"
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout  65;

    server {
        listen       80;
        server_name  $($Context.PrimaryDomain);
$sslNote        root   $publicRoot;
        index  index.php index.html;

        location / {
            try_files `$uri `$uri/ /index.php?`$query_string;
        }

        location ~ \.php$ {
            fastcgi_pass   127.0.0.1:9000;
            fastcgi_index  index.php;
            include        fastcgi.conf;
            fastcgi_param  SCRIPT_FILENAME  `$document_root`$fastcgi_script_name;
        }
    }
}
"@

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde Nginx-Konfiguration nach $confPath schreiben"
        return
    }

    Write-FileUtf8NoBom -Path $confPath -Content $configContent
    Write-Status "INFO" "Nginx-Konfiguration geschrieben: $confPath"

    if ($Context.UseSsl) {
        Write-Status "WARN" "SSL ist angefordert, aber Zertifikat und 443-Listener sind noch nicht automatisiert konfiguriert."
    }
}

function Start-OrReloadNginx {
    param(
        [string]$NginxExecutable
    )

    if ([string]::IsNullOrWhiteSpace($NginxExecutable)) {
        if ($DryRun) {
            Write-Status "INFO" "Dry-run: wuerde Nginx starten oder neu laden"
            return
        }

        throw "Nginx kann nicht gestartet werden, weil nginx.exe nicht gefunden wurde."
    }

    $nginxRoot = Get-NginxRoot -NginxExecutable $NginxExecutable
    $nginxArguments = @("-p", "$nginxRoot\", "-c", "conf/nginx.conf")

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde Nginx mit $NginxExecutable starten oder neu laden"
        return
    }

    Push-Location -LiteralPath $nginxRoot
    try {
        & $NginxExecutable @nginxArguments -t | Out-Host

        if ($LASTEXITCODE -ne 0) {
            throw "Nginx-Konfigurationstest ist fehlgeschlagen (Exit-Code $LASTEXITCODE)."
        }
    }
    finally {
        Pop-Location
    }

    $running = Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($null -ne $running) {
        Push-Location -LiteralPath $nginxRoot
        try {
            & $NginxExecutable @nginxArguments -s reload | Out-Host

            if ($LASTEXITCODE -ne 0) {
                throw "Nginx konnte nicht neu geladen werden (Exit-Code $LASTEXITCODE)."
            }
        }
        finally {
            Pop-Location
        }

        Write-Status "INFO" "Nginx neu geladen"
        return
    }

    Push-Location -LiteralPath $nginxRoot
    try {
        Start-Process -FilePath $NginxExecutable -ArgumentList $nginxArguments -WorkingDirectory $nginxRoot -WindowStyle Hidden
    }
    finally {
        Pop-Location
    }

    if (-not (Wait-ForTcpPort -HostName "127.0.0.1" -Port 80 -TimeoutSeconds 10)) {
        throw "Nginx wurde gestartet, aber Port 80 ist nicht erreichbar. Bitte pruefe, ob Port 80 bereits belegt ist oder ob nginx den Port binden darf."
    }

    Write-Status "INFO" "Nginx gestartet"
}

function Write-InstallSummary {
    param(
        [pscustomobject]$Context,
        [string]$TargetOutputRoot,
        [string]$BackendReleaseDir,
        [string]$FrontendReleaseDir
    )

    $summaryRoot = Join-Path $Context.InstallRoot "installer"
    $summaryPath = Join-Path $summaryRoot "install-summary.json"

    $summary = [ordered]@{
        installed_at_utc = [DateTime]::UtcNow.ToString("o")
        install_root = $Context.InstallRoot
        primary_domain = $Context.PrimaryDomain
        use_ssl = [bool]$Context.UseSsl
        use_local_database = [bool]$Context.UseLocalDatabase
        php_runtime_mode = $Context.PhpRuntimeMode
        backend_release_dir = $BackendReleaseDir
        frontend_release_dir = $FrontendReleaseDir
        fetched_release_root = $TargetOutputRoot
        next_steps = @(
            "Weitere Anwendungsgeheimnisse und produktive Queue-/Cron-Prozesse konfigurieren",
            "SSL-Zertifikate fuer produktive HTTPS-Nutzung hinterlegen",
            "Anwendung nach Erstinstallation funktional pruefen"
        )
    }

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde Install-Zusammenfassung nach $summaryPath schreiben"
        return
    }

    New-Item -ItemType Directory -Force -Path $summaryRoot | Out-Null
    $json = $summary | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $summaryPath -Value $json -Encoding UTF8
    Write-Status "INFO" "Install-Zusammenfassung gespeichert: $summaryPath"
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$windowsRoot = Split-Path -Parent $scriptRoot
$preflightScript = Join-Path $scriptRoot "preflight.ps1"
$fetchReleasesScript = Join-Path $scriptRoot "fetch-releases.ps1"

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $windowsRoot "output\releases"
}

if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
    $GitHubToken = $env:GITHUB_TOKEN
}

Write-Status "INFO" "Starte Windows-Installationsfluss"

$configObject = Read-InstallConfig -Path $ConfigPath
$context = ConvertTo-InstallContext -Config $configObject

if (-not [string]::IsNullOrWhiteSpace($PhpRuntimeMode)) {
    $context.PhpRuntimeMode = $PhpRuntimeMode
}

Validate-InstallContext -Context $context

if (-not $SkipPreflight) {
    Invoke-Preflight -ScriptPath $preflightScript
}
else {
    Write-Status "WARN" "Preflight wurde uebersprungen"
}

Invoke-FetchReleases -ScriptPath $fetchReleasesScript -TargetOutputRoot $OutputRoot -Token $GitHubToken

$backendReleaseDir = Get-LatestReleaseDirectory -ComponentRoot (Join-Path $OutputRoot "backend")
$frontendReleaseDir = Get-LatestReleaseDirectory -ComponentRoot (Join-Path $OutputRoot "frontend")

$backendAsset = Get-PrimaryAssetFile -AssetsRoot (Join-Path $backendReleaseDir "assets")
$frontendAsset = Get-PrimaryAssetFile -AssetsRoot (Join-Path $frontendReleaseDir "assets")

$expandRoot = Join-Path $context.InstallRoot "installer\expanded"
$expandedBackendDir = Join-Path $expandRoot "backend"
$expandedFrontendDir = Join-Path $expandRoot "frontend"

Expand-ReleaseArchive -ArchivePath $backendAsset -TargetDir $expandedBackendDir
Expand-ReleaseArchive -ArchivePath $frontendAsset -TargetDir $expandedFrontendDir
Deploy-Application -Context $context -ExpandedBackendDir $expandedBackendDir -ExpandedFrontendDir $expandedFrontendDir
Write-EnvironmentFile -Context $context

$phpExecutable = Ensure-Php82Installed -Context $context
if (-not [string]::IsNullOrWhiteSpace($phpExecutable)) {
    Write-Status "INFO" "PHP CLI erkannt: $phpExecutable"
}
Ensure-PhpRuntimeConfiguration -PhpExecutable $phpExecutable
$composerExecutable = Ensure-ComposerInstalled
Invoke-ComposerInstall -Context $context -ComposerExecutable $composerExecutable
Ensure-MariaDbInstalled -Context $context
Ensure-MariaDbProvisioning -Context $context
Test-DatabaseConnectivity -Context $context
Invoke-LaravelBootstrap -Context $context -PhpExecutable $phpExecutable
Ensure-PhpFastCgiRunner -Context $context
$nginxExecutable = Ensure-NginxInstalled
Set-NginxConfiguration -Context $context -NginxExecutable $nginxExecutable
Start-OrReloadNginx -NginxExecutable $nginxExecutable

Write-InstallSummary -Context $context -TargetOutputRoot $OutputRoot -BackendReleaseDir $backendReleaseDir -FrontendReleaseDir $frontendReleaseDir

Write-Status "INFO" "Windows-Installationsfluss abgeschlossen"
