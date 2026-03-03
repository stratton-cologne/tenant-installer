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
    if (-not (Test-CommandAvailable -Name "php")) {
        return ""
    }

    return (& php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
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
    & winget @arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$DisplayName konnte nicht ueber winget installiert werden (Exit-Code $LASTEXITCODE)."
    }
}

function Install-WithChocolatey {
    param(
        [string]$PackageName,
        [string]$DisplayName
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

    Write-Status "INFO" "Installiere $DisplayName ueber Chocolatey"
    & choco @arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$DisplayName konnte nicht ueber Chocolatey installiert werden (Exit-Code $LASTEXITCODE)."
    }
}

function Install-Package {
    param(
        [string]$WingetId,
        [string]$ChocolateyName,
        [string]$DisplayName,
        [switch]$RequireWinget
    )

    if (Test-CommandAvailable -Name "winget") {
        Install-WithWinget -PackageId $WingetId -DisplayName $DisplayName
        return
    }

    if ($RequireWinget) {
        throw "$DisplayName erfordert aktuell winget, weil dafuer eine feste Paketversion benoetigt wird."
    }

    if (Test-CommandAvailable -Name "choco") {
        Install-WithChocolatey -PackageName $ChocolateyName -DisplayName $DisplayName
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

    if (-not [string]::IsNullOrWhiteSpace($commandPath)) {
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
    $installedVersion = Get-PhpMinorVersion

    if ($installedVersion -eq "8.2") {
        Write-Status "PASS" "PHP 8.2 ist bereits vorhanden"
        return (Find-PhpExecutable)
    }

    if (-not [string]::IsNullOrWhiteSpace($installedVersion)) {
        Write-Status "WARN" "Gefundene PHP-Version $installedVersion wird durch PHP 8.2 ersetzt oder ergaenzt"
    }
    else {
        Write-Status "INFO" "PHP 8.2 ist noch nicht vorhanden"
    }

    Install-Package -WingetId "PHP.PHP.8.2" -ChocolateyName "php" -DisplayName "PHP 8.2" -RequireWinget

    if ($DryRun) {
        return ""
    }

    $resolvedVersion = Get-PhpMinorVersion

    if ($resolvedVersion -ne "8.2") {
        throw "PHP 8.2 wurde nicht erfolgreich bereitgestellt. Aktuell erkannt: $resolvedVersion"
    }

    Write-Status "PASS" "PHP 8.2 ist verfuegbar"
    return (Find-PhpExecutable)
}

function Ensure-ComposerInstalled {
    $composerExecutable = Find-ComposerExecutable

    if (-not [string]::IsNullOrWhiteSpace($composerExecutable)) {
        Write-Status "PASS" "Composer ist bereits vorhanden: $composerExecutable"
        return $composerExecutable
    }

    if (Test-CommandAvailable -Name "choco") {
        Install-WithChocolatey -PackageName "composer" -DisplayName "Composer"
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

function Ensure-MariaDbInstalled {
    param(
        [pscustomobject]$Context
    )

    if (-not $Context.UseLocalDatabase) {
        Write-Status "INFO" "Remote-Datenbank ausgewaehlt: $($Context.DatabaseHost):$($Context.DatabasePort)"
        return
    }

    $service = Get-Service -Name "MariaDB" -ErrorAction SilentlyContinue

    if ($null -ne $service) {
        Write-Status "PASS" "MariaDB-Service ist bereits vorhanden"
        return
    }

    Install-Package -WingetId "MariaDB.Server" -ChocolateyName "mariadb" -DisplayName "MariaDB Server"

    if ($DryRun) {
        return
    }

    $service = Get-Service -Name "MariaDB" -ErrorAction SilentlyContinue

    if ($null -eq $service) {
        Write-Status "WARN" "MariaDB wurde installiert, aber der Dienstname 'MariaDB' wurde noch nicht gefunden."
        return
    }

    if ($service.Status -ne "Running") {
        Start-Service -Name $service.Name
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

    return "$scheme://$($Context.PrimaryDomain)"
}

function Write-EnvironmentFile {
    param(
        [pscustomobject]$Context
    )

    $appRoot = Get-ApplicationRoot -BackendTarget (Join-Path $Context.InstallRoot "backend")
    $envPath = Join-Path $appRoot ".env"
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

    $content = $lines -join "`r`n"
    Set-Content -LiteralPath $envPath -Value $content -Encoding UTF8
    Write-Status "INFO" ".env geschrieben: $envPath"
}

function Invoke-ComposerInstall {
    param(
        [pscustomobject]$Context,
        [string]$ComposerExecutable
    )

    $appRoot = Get-ApplicationRoot -BackendTarget (Join-Path $Context.InstallRoot "backend")
    $composerManifest = Join-Path $appRoot "composer.json"

    if (-not (Test-Path -LiteralPath $composerManifest -PathType Leaf)) {
        Write-Status "WARN" "Kein composer.json gefunden. Composer-Install wird uebersprungen."
        return
    }

    if ([string]::IsNullOrWhiteSpace($ComposerExecutable)) {
        throw "Composer-Install wurde angefordert, aber Composer ist nicht verfuegbar."
    }

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde 'composer install' in $appRoot ausfuehren"
        return
    }

    $arguments = @(
        "install",
        "--no-interaction",
        "--no-dev",
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

function Invoke-LaravelBootstrap {
    param(
        [pscustomobject]$Context,
        [string]$PhpExecutable
    )

    $appRoot = Get-ApplicationRoot -BackendTarget (Join-Path $Context.InstallRoot "backend")
    $artisanPath = Join-Path $appRoot "artisan"

    if (-not (Test-Path -LiteralPath $artisanPath -PathType Leaf)) {
        Write-Status "WARN" "Kein Laravel-Artisan gefunden. Laravel-Bootstrap wird uebersprungen."
        return
    }

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

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde NSSM fuer den PHP-FastCGI-Dienst einrichten"
        return
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

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde PHP-FastCGI-Startskript nach $launcherPath schreiben"
        Write-Status "INFO" "Dry-run: wuerde geplanten Task $taskName anlegen und starten"
        return
    }

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
        "--protocol=TCP",
        "--execute", $Sql
    )

    if (-not [string]::IsNullOrWhiteSpace($env:MARIADB_ROOT_PASSWORD)) {
        $arguments = @("-u", "root", "-p$($env:MARIADB_ROOT_PASSWORD)", "--protocol=TCP", "--execute", $Sql)
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
            try_files \$uri \$uri/ /index.php?\$query_string;
        }

        location ~ \.php$ {
            fastcgi_pass   127.0.0.1:9000;
            fastcgi_index  index.php;
            include        fastcgi.conf;
            fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
        }
    }
}
"@

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde Nginx-Konfiguration nach $confPath schreiben"
        return
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $confPath) | Out-Null
    Set-Content -LiteralPath $confPath -Value $configContent -Encoding UTF8
    Write-Status "INFO" "Nginx-Konfiguration geschrieben: $confPath"

    if ($Context.UseSsl) {
        Write-Status "WARN" "SSL ist angefordert, aber Zertifikat und 443-Listener sind noch nicht automatisiert konfiguriert."
    }
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

$phpExecutable = Ensure-Php82Installed
if (-not [string]::IsNullOrWhiteSpace($phpExecutable)) {
    Write-Status "INFO" "PHP CLI erkannt: $phpExecutable"
}
$composerExecutable = Ensure-ComposerInstalled
Invoke-ComposerInstall -Context $context -ComposerExecutable $composerExecutable
Invoke-LaravelBootstrap -Context $context -PhpExecutable $phpExecutable
Ensure-PhpFastCgiRunner -Context $context
$nginxExecutable = Ensure-NginxInstalled
Set-NginxConfiguration -Context $context -NginxExecutable $nginxExecutable
Ensure-MariaDbInstalled -Context $context
Ensure-MariaDbProvisioning -Context $context

Write-InstallSummary -Context $context -TargetOutputRoot $OutputRoot -BackendReleaseDir $backendReleaseDir -FrontendReleaseDir $frontendReleaseDir

Write-Status "INFO" "Windows-Installationsfluss abgeschlossen"
