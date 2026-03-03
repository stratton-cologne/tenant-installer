param(
    [switch]$CheckOnly,
    [switch]$DryRun,
    [string]$AssetBaseUrl = "",
    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptRoot)
$PreflightScript = Join-Path $ScriptRoot "preflight.ps1"
$ManifestDir = Join-Path $ProjectRoot "shared/manifests"
$ArtifactDir = Join-Path $ProjectRoot "artifacts"
$WindowsNginxDir = Join-Path $ProjectRoot "windows/nginx"
$WindowsServicesDir = Join-Path $ProjectRoot "windows/services"

$script:CurrentReleaseDir = $null
$script:FrontendPublicDir = $null
$script:RuntimeConfigDir = $null
$script:BackendReleaseDir = $null
$script:FrontendReleaseDir = $null
$script:BackendArtifact = $null
$script:FrontendArtifact = $null
$script:BootstrapStatus = "pending"
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

function Prompt-Value {
    param(
        [string]$Label,
        [string]$Default = ""
    )

    $suffix = ""
    if ($Default -ne "") {
        $suffix = " [$Default]"
    }

    $value = Read-Host "$Label$suffix"
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    return $value
}

function Prompt-Secret {
    param(
        [string]$Label
    )

    $secure = Read-Host $Label -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Prompt-YesNo {
    param(
        [string]$Label,
        [bool]$Default = $true
    )

    $defaultText = if ($Default) { "yes" } else { "no" }

    while ($true) {
        $value = Read-Host "$Label [$defaultText]"
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $Default
        }

        switch ($value.ToLowerInvariant()) {
            "y" { return $true }
            "yes" { return $true }
            "n" { return $false }
            "no" { return $false }
        }

        Write-Status "WARN" "Bitte yes oder no eingeben."
    }
}

function Read-ConfigOverrides {
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        return $null
    }

    Require-File $ConfigPath
    $json = Get-Content -LiteralPath $ConfigPath -Raw

    if ([string]::IsNullOrWhiteSpace($json)) {
        throw "Config-Datei ist leer: $ConfigPath"
    }

    return $json | ConvertFrom-Json
}

function Get-OverrideString {
    param(
        [AllowNull()]
        [object]$Overrides,
        [string]$Name
    )

    if ($null -eq $Overrides) {
        return $null
    }

    $property = $Overrides.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $null
    }

    if ($null -eq $property.Value) {
        return ""
    }

    return [string]$property.Value
}

function Get-OverrideBool {
    param(
        [AllowNull()]
        [object]$Overrides,
        [string]$Name
    )

    if ($null -eq $Overrides) {
        return $null
    }

    $property = $Overrides.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $null
    }

    if ($property.Value -is [bool]) {
        return [bool]$property.Value
    }

    $text = [string]$property.Value

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $false
    }

    return $text.ToLowerInvariant() -in @("1", "true", "yes", "y")
}

function Resolve-StringValue {
    param(
        [AllowNull()]
        [string]$OverrideValue,
        [string]$PromptLabel,
        [string]$DefaultValue = ""
    )

    if ($null -ne $OverrideValue) {
        return $OverrideValue
    }

    return Prompt-Value -Label $PromptLabel -Default $DefaultValue
}

function Resolve-SecretValue {
    param(
        [AllowNull()]
        [string]$OverrideValue,
        [string]$PromptLabel
    )

    if ($null -ne $OverrideValue) {
        return $OverrideValue
    }

    return Prompt-Secret -Label $PromptLabel
}

function Resolve-BoolValue {
    param(
        [AllowNull()]
        [object]$OverrideValue,
        [string]$PromptLabel,
        [bool]$DefaultValue = $true
    )

    if ($null -ne $OverrideValue) {
        return [bool]$OverrideValue
    }

    return Prompt-YesNo -Label $PromptLabel -Default $DefaultValue
}

function ConvertTo-TemplateValue {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return $Value
}

function Invoke-Preflight {
    Require-File $PreflightScript
    Write-Status "INFO" "Fuehre Windows-Preflight aus"
    & powershell -ExecutionPolicy Bypass -File $PreflightScript
}

function New-AppKey {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return "base64:" + [Convert]::ToBase64String($bytes)
}

function New-HexSecret {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Get-KeyFromPassphrase {
    param(
        [string]$Passphrase
    )

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Passphrase))
    }
    finally {
        $sha.Dispose()
    }
}

function Get-LatestStableManifest {
    param(
        [string]$Component
    )

    $manifest = Get-ChildItem -LiteralPath $ManifestDir -Filter *.json -File |
        ForEach-Object {
            $json = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            [PSCustomObject]@{
                Path = $_.FullName
                Component = $json.component
                Channel = $json.release_channel
                Version = $json.version
            }
        } |
        Where-Object { $_.Component -eq $Component -and $_.Channel -eq "stable" } |
        Sort-Object Version |
        Select-Object -Last 1

    if ($null -eq $manifest) {
        throw "Kein stabiles Manifest gefunden fuer $Component"
    }

    return $manifest
}

function Get-FileHashString {
    param(
        [string]$Path
    )

    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Stage-Artifact {
    param(
        [pscustomobject]$ManifestObject,
        [string]$CacheDir
    )

    $manifestJson = Get-Content -LiteralPath $ManifestObject.Path -Raw | ConvertFrom-Json
    $fileName = $manifestJson.artifact.file_name
    $expectedHash = $manifestJson.artifact.sha256.ToLowerInvariant()
    $targetPath = Join-Path $CacheDir $fileName

    if ($DryRun) {
        if ([string]::IsNullOrWhiteSpace($AssetBaseUrl)) {
            $sourcePath = Join-Path $ArtifactDir $fileName
            Write-Status "INFO" "Dry-run: wuerde Artefakt stagen $sourcePath -> $targetPath"
        }
        else {
            Write-Status "INFO" "Dry-run: wuerde Artefakt von $AssetBaseUrl/$fileName nach $targetPath laden"
        }
        return $targetPath
    }

    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

    if ([string]::IsNullOrWhiteSpace($AssetBaseUrl)) {
        $sourcePath = Join-Path $ArtifactDir $fileName

        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Artefakt fehlt: $sourcePath"
        }

        $actualHash = Get-FileHashString -Path $sourcePath
        if ($actualHash -ne $expectedHash) {
            throw "Checksumme stimmt nicht fuer $sourcePath"
        }

        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        Write-Status "INFO" "Artefakt gestaged: $targetPath"
        return $targetPath
    }

    $assetUrl = ($AssetBaseUrl.TrimEnd('/')) + "/" + $fileName
    Invoke-WebRequest -Uri $assetUrl -OutFile $targetPath -UseBasicParsing
    $actualHash = Get-FileHashString -Path $targetPath

    if ($actualHash -ne $expectedHash) {
        throw "Checksumme stimmt nicht fuer heruntergeladenes Artefakt: $assetUrl"
    }

    Write-Status "INFO" "Artefakt geladen: $targetPath"
    return $targetPath
}

function Expand-StagedArtifact {
    param(
        [string]$ZipPath,
        [string]$TargetDir
    )

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde $ZipPath nach $TargetDir entpacken"
        return
    }

    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $TargetDir -Force
    Write-Status "INFO" "Entpackt: $TargetDir"
}

function Copy-DirectoryContents {
    param(
        [string]$SourceDir,
        [string]$TargetDir
    )

    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    Copy-Item -Path (Join-Path $SourceDir "*") -Destination $TargetDir -Recurse -Force
}

function New-TenantEnvContent {
    param(
        [pscustomobject]$Config
    )

    $scheme = if ($Config.UseSsl) { "https" } else { "http" }
    $mailMailer = if ($Config.EnableSmtp) { "smtp" } else { "log" }
    $mailHost = if ($Config.EnableSmtp) { $Config.MailHost } else { "" }
    $mailPort = if ($Config.EnableSmtp) { $Config.MailPort } else { "" }
    $mailUser = if ($Config.EnableSmtp) { $Config.MailUsername } else { "" }
    $mailPassword = if ($Config.EnableSmtp) { $Config.MailPassword } else { "" }
    $mailEncryption = if ($Config.EnableSmtp) { $Config.MailEncryption } else { "" }
    $mailFromAddress = if ($Config.EnableSmtp) { $Config.MailFromAddress } else { $Config.AdminEmail }

    @"
APP_NAME=TenantBackend
APP_ENV=production
APP_KEY=$(New-AppKey)
APP_DEBUG=false
APP_URL=$scheme://$($Config.Domain)
TENANT_PORTAL_URL=$scheme://$($Config.Domain)

APP_LOCALE=de
APP_FALLBACK_LOCALE=en
APP_FAKER_LOCALE=en_US

LOG_CHANNEL=stack
LOG_STACK=single
LOG_LEVEL=info

DB_CONNECTION=mysql
DB_HOST=$($Config.DbHost)
DB_PORT=$($Config.DbPort)
DB_DATABASE=$($Config.DbName)
DB_USERNAME=$($Config.DbUser)
DB_PASSWORD=$($Config.DbPassword)

CACHE_STORE=file
QUEUE_CONNECTION=database
SESSION_DRIVER=file
FILESYSTEM_DISK=local

MAIL_MAILER=$mailMailer
MAIL_HOST=$(ConvertTo-TemplateValue $mailHost)
MAIL_PORT=$(ConvertTo-TemplateValue $mailPort)
MAIL_USERNAME=$(ConvertTo-TemplateValue $mailUser)
MAIL_PASSWORD=$(ConvertTo-TemplateValue $mailPassword)
MAIL_ENCRYPTION=$(ConvertTo-TemplateValue $mailEncryption)
MAIL_FROM_ADDRESS=$(ConvertTo-TemplateValue $mailFromAddress)
MAIL_FROM_NAME="Tenant Portal"

LICENSE_API_URL=
CORE_API_TOKEN=
CORE_TO_TENANT_SYNC_TOKEN=
AUTO_LICENSE_SYNC_ENABLED=false
E2E_CORE_TENANT_UUID=$(ConvertTo-TemplateValue $Config.TenantId)
MFA_APP_ACTIVATION_TTL_MINUTES=30
LOGIN_RATE_LIMIT=5
MFA_VERIFY_RATE_LIMIT=5
MFA_CODE_TTL_MINUTES=10
TRUSTED_DEVICE_TTL_DAYS=30
TRUSTED_DEVICE_COOKIE=tenant_trusted_device
PASSWORD_MIN_LENGTH=12
JWT_ACTIVE_KID=default
JWT_KEYS_JSON=
JWT_TTL_MINUTES=480
JWT_REFRESH_TTL_MINUTES=10080
JWT_SECRET=$(New-HexSecret)
NOTIFICATIONS_STREAM_ENABLED=false
"@
}

function New-NginxSiteContent {
    param(
        [pscustomobject]$Config
    )

    @"
server {
    listen 80;
    server_name $($Config.Domain);

    root $($Config.AppRoot)\public;
    index index.php index.html;

    client_max_body_size 32m;

    location / {
        try_files `$uri `$uri/ /index.php?`$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME `$document_root`$fastcgi_script_name;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_read_timeout 300;
    }
}
"@
}

function New-QueueWorkerCmdContent {
    param(
        [string]$AppRoot
    )

    @"
@echo off
cd /d "$AppRoot\current"
php artisan queue:work --sleep=3 --tries=3 --timeout=90
"@
}

function Render-GeneratedFiles {
    param(
        [pscustomobject]$Config
    )

    $generatedDir = Join-Path $Config.AppRoot "installer\generated"
    $systemDir = Join-Path $generatedDir "services"

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde generierte Dateien in $generatedDir erzeugen"
        return
    }

    Require-File (Join-Path $WindowsNginxDir "nginx.conf")
    Require-File (Join-Path $WindowsServicesDir "queue-worker-wrapper.ps1")
    Require-File (Join-Path $WindowsServicesDir "scheduler-wrapper.ps1")
    Require-File (Join-Path $WindowsServicesDir "register-runtime-services.ps1")

    New-Item -ItemType Directory -Force -Path $generatedDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $generatedDir "nginx") | Out-Null
    New-Item -ItemType Directory -Force -Path $systemDir | Out-Null

    Set-Content -LiteralPath (Join-Path $generatedDir "tenant.env") -Value (New-TenantEnvContent -Config $Config) -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $generatedDir "nginx-site.conf") -Value (New-NginxSiteContent -Config $Config) -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $WindowsNginxDir "nginx.conf") -Destination (Join-Path $generatedDir "nginx\nginx.conf") -Force
    Set-Content -LiteralPath (Join-Path $systemDir "tenant-queue-worker.cmd") -Value (New-QueueWorkerCmdContent -AppRoot $Config.AppRoot) -Encoding ASCII
    Copy-Item -LiteralPath (Join-Path $WindowsServicesDir "queue-worker-wrapper.ps1") -Destination (Join-Path $systemDir "queue-worker-wrapper.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $WindowsServicesDir "scheduler-wrapper.ps1") -Destination (Join-Path $systemDir "scheduler-wrapper.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $WindowsServicesDir "register-runtime-services.ps1") -Destination (Join-Path $systemDir "register-runtime-services.ps1") -Force

    Write-Status "INFO" "Generierte Dateien erstellt in $generatedDir"
}

function Deploy-ApplicationLayout {
    param(
        [pscustomobject]$Config
    )

    $script:CurrentReleaseDir = Join-Path $Config.AppRoot "current"
    $script:FrontendPublicDir = Join-Path $Config.AppRoot "public"
    $script:RuntimeConfigDir = Join-Path $Config.AppRoot "runtime"
    $generatedDir = Join-Path $Config.AppRoot "installer\generated"
    $frontendBackupDir = Join-Path $Config.AppRoot ("backups\frontend-" + ([DateTime]::UtcNow.ToString("yyyyMMddHHmmss")))

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde Backend nach $script:CurrentReleaseDir deployen"
        Write-Status "INFO" "Dry-run: wuerde Frontend nach $script:FrontendPublicDir deployen"
        Write-Status "INFO" "Dry-run: wuerde Runtime-Dateien nach $script:RuntimeConfigDir deployen"
        return
    }

    Copy-DirectoryContents -SourceDir $script:BackendReleaseDir -TargetDir $script:CurrentReleaseDir

    if ((Test-Path -LiteralPath $script:FrontendPublicDir) -and (Get-ChildItem -LiteralPath $script:FrontendPublicDir -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        New-Item -ItemType Directory -Force -Path $frontendBackupDir | Out-Null
        Copy-DirectoryContents -SourceDir $script:FrontendPublicDir -TargetDir $frontendBackupDir
        Get-ChildItem -LiteralPath $script:FrontendPublicDir -Force | Remove-Item -Recurse -Force
    }

    Copy-DirectoryContents -SourceDir $script:FrontendReleaseDir -TargetDir $script:FrontendPublicDir

    New-Item -ItemType Directory -Force -Path (Join-Path $script:RuntimeConfigDir "nginx") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $script:RuntimeConfigDir "services") | Out-Null

    Copy-Item -LiteralPath (Join-Path $generatedDir "tenant.env") -Destination (Join-Path $script:CurrentReleaseDir ".env") -Force
    Copy-Item -LiteralPath (Join-Path $generatedDir "tenant.env") -Destination (Join-Path $script:RuntimeConfigDir "tenant.env") -Force
    Copy-Item -LiteralPath (Join-Path $generatedDir "nginx\nginx.conf") -Destination (Join-Path $script:RuntimeConfigDir "nginx\nginx.conf") -Force
    Copy-Item -LiteralPath (Join-Path $generatedDir "nginx-site.conf") -Destination (Join-Path $script:RuntimeConfigDir "nginx\tenant-site.conf") -Force
    Copy-Item -LiteralPath (Join-Path $generatedDir "services\tenant-queue-worker.cmd") -Destination (Join-Path $script:RuntimeConfigDir "services\tenant-queue-worker.cmd") -Force
    Copy-Item -LiteralPath (Join-Path $generatedDir "services\queue-worker-wrapper.ps1") -Destination (Join-Path $script:RuntimeConfigDir "services\queue-worker-wrapper.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $generatedDir "services\scheduler-wrapper.ps1") -Destination (Join-Path $script:RuntimeConfigDir "services\scheduler-wrapper.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $generatedDir "services\register-runtime-services.ps1") -Destination (Join-Path $script:RuntimeConfigDir "services\register-runtime-services.ps1") -Force

    Write-Status "INFO" "Basis-Deploy abgeschlossen"
}

function Invoke-InCurrentRelease {
    param(
        [string]$Command
    )

    if ([string]::IsNullOrWhiteSpace($script:CurrentReleaseDir)) {
        throw "Current release directory nicht gesetzt."
    }

    Push-Location $script:CurrentReleaseDir
    try {
        & powershell -NoProfile -Command $Command
    }
    finally {
        Pop-Location
    }
}

function Bootstrap-LaravelApp {
    param(
        [pscustomobject]$Config
    )

    $composerCommand = 'composer install --no-interaction --prefer-dist --optimize-autoloader'
    $keygenCommand = 'php artisan key:generate --force'
    $migrateCommand = 'php artisan migrate --force'
    $seedCommand = 'php artisan db:seed --force'

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde in $script:CurrentReleaseDir ausfuehren -> $composerCommand"
        Write-Status "INFO" "Dry-run: wuerde in $script:CurrentReleaseDir ausfuehren -> $keygenCommand"
        Write-Status "INFO" "Dry-run: wuerde in $script:CurrentReleaseDir ausfuehren -> $migrateCommand"
        if ($Config.RunSeeders) {
            Write-Status "INFO" "Dry-run: wuerde in $script:CurrentReleaseDir ausfuehren -> $seedCommand"
        }
        $script:BootstrapStatus = "dry-run"
        return
    }

    if (-not (Test-Path -LiteralPath (Join-Path $script:CurrentReleaseDir "artisan") -PathType Leaf)) {
        Write-Status "WARN" "Laravel-Bootstrap uebersprungen, da artisan fehlt."
        $script:BootstrapStatus = "skipped-missing-artisan"
        return
    }

    Write-Status "INFO" "Starte composer install"
    Invoke-InCurrentRelease -Command $composerCommand

    Write-Status "INFO" "Generiere Application Key"
    Invoke-InCurrentRelease -Command $keygenCommand

    Write-Status "INFO" "Fuehre Migrationen aus"
    Invoke-InCurrentRelease -Command $migrateCommand

    if ($Config.RunSeeders) {
        Write-Status "INFO" "Fuehre Seeder aus"
        Invoke-InCurrentRelease -Command $seedCommand
    }

    $script:BootstrapStatus = "completed"
}

function Save-InstallerState {
    param(
        [pscustomobject]$Config,
        [pscustomobject]$BackendManifestObject,
        [pscustomobject]$FrontendManifestObject
    )

    $stateDir = Join-Path $Config.AppRoot "installer\state"
    $statePath = Join-Path $stateDir "install-state.enc.json"
    $installationId = [guid]::NewGuid().ToString()

    $stateObject = [ordered]@{
        schema_version = "1.0.0"
        installation_id = $installationId
        platform = "windows"
        app_root = $Config.AppRoot
        state_file = @{
            path = $statePath
            encrypted = $true
        }
        deployed = @{
            backend_version = $BackendManifestObject.Version
            frontend_version = $FrontendManifestObject.Version
            backend_artifact = $script:BackendArtifact
            frontend_artifact = $script:FrontendArtifact
            backend_release_dir = $script:BackendReleaseDir
            frontend_release_dir = $script:FrontendReleaseDir
            current_release_dir = $script:CurrentReleaseDir
            frontend_public_dir = $script:FrontendPublicDir
            bootstrap_status = $script:BootstrapStatus
            modules = @()
        }
        services = @{
            web_server = "nginx"
            scheduler = "tenant-scheduler"
            queue_worker = "tenant-queue-worker"
            runtime_config_dir = $script:RuntimeConfigDir
        }
        database = @{
            engine = "mysql"
            host = $Config.DbHost
            port = [int]$Config.DbPort
            name = $Config.DbName
            managed_by_installer = $false
        }
        timestamps = @{
            installed_at_utc = [DateTime]::UtcNow.ToString("o")
        }
    }

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde verschluesselten Installer-State nach $statePath schreiben"
        return
    }

    $key = Get-KeyFromPassphrase -Passphrase $Config.AdminPassword
    $plaintext = $stateObject | ConvertTo-Json -Depth 8
    $secure = ConvertTo-SecureString -String $plaintext -AsPlainText -Force
    $ciphertext = ConvertFrom-SecureString -SecureString $secure -Key $key

    $envelope = @{
        version = "1"
        cipher = "ConvertFrom-SecureString-AES"
        payload = $ciphertext
    } | ConvertTo-Json -Depth 4

    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    Set-Content -LiteralPath $statePath -Value $envelope -Encoding UTF8
    Write-Status "INFO" "Installer-State gespeichert: $statePath"
}

function Collect-Input {
    param(
        [AllowNull()]
        [object]$Overrides
    )

    $config = [ordered]@{}
    $config.AppRoot = Resolve-StringValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "AppRoot") -PromptLabel "Application root directory" -DefaultValue "C:\TenantPlatform"
    $config.Domain = Resolve-StringValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "Domain") -PromptLabel "Primary domain"
    $config.UseSsl = Resolve-BoolValue -OverrideValue (Get-OverrideBool -Overrides $Overrides -Name "UseSsl") -PromptLabel "Enable SSL" -DefaultValue $true
    $config.AdminEmail = Resolve-StringValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "AdminEmail") -PromptLabel "Admin email"
    $config.AdminPassword = Resolve-SecretValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "AdminPassword") -PromptLabel "Admin password"
    $config.DbHost = Resolve-StringValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "DbHost") -PromptLabel "Database host" -DefaultValue "127.0.0.1"
    $config.DbPort = Resolve-StringValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "DbPort") -PromptLabel "Database port" -DefaultValue "3306"
    $config.DbName = Resolve-StringValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "DbName") -PromptLabel "Database name" -DefaultValue "tenant_platform"
    $config.DbUser = Resolve-StringValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "DbUser") -PromptLabel "Database user" -DefaultValue "tenant_user"
    $config.DbPassword = Resolve-SecretValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "DbPassword") -PromptLabel "Database password"
    $config.EnableSmtp = Resolve-BoolValue -OverrideValue (Get-OverrideBool -Overrides $Overrides -Name "EnableSmtp") -PromptLabel "Configure SMTP" -DefaultValue $false
    if ($config.EnableSmtp) {
        $config.MailHost = Resolve-StringValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "MailHost") -PromptLabel "SMTP host"
        $config.MailPort = Resolve-StringValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "MailPort") -PromptLabel "SMTP port" -DefaultValue "587"
        $config.MailUsername = Resolve-StringValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "MailUsername") -PromptLabel "SMTP username"
        $config.MailPassword = Resolve-SecretValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "MailPassword") -PromptLabel "SMTP password"
        $config.MailEncryption = Resolve-StringValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "MailEncryption") -PromptLabel "SMTP encryption" -DefaultValue "tls"
        $config.MailFromAddress = Resolve-StringValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "MailFromAddress") -PromptLabel "Mail from address" -DefaultValue $config.AdminEmail
    }
    else {
        $config.MailHost = ""
        $config.MailPort = ""
        $config.MailUsername = ""
        $config.MailPassword = ""
        $config.MailEncryption = ""
        $config.MailFromAddress = $config.AdminEmail
    }
    $config.TenantId = Resolve-StringValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "TenantId") -PromptLabel "Tenant ID (optional)"
    $config.LicenseKey = Resolve-StringValue -OverrideValue (Get-OverrideString -Overrides $Overrides -Name "LicenseKey") -PromptLabel "License key (optional)"
    $config.RunSeeders = Resolve-BoolValue -OverrideValue (Get-OverrideBool -Overrides $Overrides -Name "RunSeeders") -PromptLabel "Run database seeders after migrations" -DefaultValue $false
    return [pscustomobject]$config
}

function Initialize-RunArtifacts {
    param(
        [pscustomobject]$Config
    )

    $script:LogFile = Join-Path $Config.AppRoot "installer\logs\install.log"
    $script:SuccessMarker = Join-Path $Config.AppRoot "installer\state\install.success"

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde Installer-Log nach $script:LogFile schreiben"
        Write-Status "INFO" "Dry-run: wuerde Success-Marker nach $script:SuccessMarker schreiben"
        return
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:LogFile) | Out-Null
    "" | Set-Content -LiteralPath $script:LogFile -Encoding UTF8
    Write-Status "INFO" "Installer-Log initialisiert"
}

function Write-SuccessMarker {
    param(
        [pscustomobject]$BackendManifestObject,
        [pscustomobject]$FrontendManifestObject
    )

    if ($DryRun) {
        Write-Status "INFO" "Dry-run: wuerde Success-Marker nach $script:SuccessMarker schreiben"
        return
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $script:SuccessMarker) | Out-Null
    @(
        "installed_at_utc=$([DateTime]::UtcNow.ToString('o'))"
        "backend_version=$($BackendManifestObject.Version)"
        "frontend_version=$($FrontendManifestObject.Version)"
    ) | Set-Content -LiteralPath $script:SuccessMarker -Encoding UTF8

    Write-Status "INFO" "Success-Marker geschrieben"
}

Write-Status "INFO" "Starte Windows-Installationsfluss"
Invoke-Preflight

if ($CheckOnly) {
    Write-Status "INFO" "Check-only Modus aktiv; Abbruch nach Preflight"
    exit 0
}

$overrides = Read-ConfigOverrides
$config = Collect-Input -Overrides $overrides

if ([string]::IsNullOrWhiteSpace($config.Domain)) { throw "Domain ist erforderlich." }
if ([string]::IsNullOrWhiteSpace($config.AdminEmail)) { throw "Admin email ist erforderlich." }
if ([string]::IsNullOrWhiteSpace($config.AdminPassword)) { throw "Admin password ist erforderlich." }
if ([string]::IsNullOrWhiteSpace($config.DbPassword)) { throw "Database password ist erforderlich." }

Initialize-RunArtifacts -Config $config

$backendManifest = Get-LatestStableManifest -Component "tenant-backend"
$frontendManifest = Get-LatestStableManifest -Component "tenant-frontend"

Write-Status "INFO" "Backend-Manifest: $([IO.Path]::GetFileName($backendManifest.Path)) ($($backendManifest.Version))"
Write-Status "INFO" "Frontend-Manifest: $([IO.Path]::GetFileName($frontendManifest.Path)) ($($frontendManifest.Version))"

$cacheDir = Join-Path $config.AppRoot "installer\cache"
$backendZip = Stage-Artifact -ManifestObject $backendManifest -CacheDir $cacheDir
$frontendZip = Stage-Artifact -ManifestObject $frontendManifest -CacheDir $cacheDir
$script:BackendArtifact = $backendZip
$script:FrontendArtifact = $frontendZip

$script:BackendReleaseDir = Join-Path $config.AppRoot ("releases\backend-" + $backendManifest.Version)
$script:FrontendReleaseDir = Join-Path $config.AppRoot ("releases\frontend-" + $frontendManifest.Version)

Expand-StagedArtifact -ZipPath $backendZip -TargetDir $script:BackendReleaseDir
Expand-StagedArtifact -ZipPath $frontendZip -TargetDir $script:FrontendReleaseDir

Render-GeneratedFiles -Config $config
Deploy-ApplicationLayout -Config $config
Bootstrap-LaravelApp -Config $config
Save-InstallerState -Config $config -BackendManifestObject $backendManifest -FrontendManifestObject $frontendManifest
Write-SuccessMarker -BackendManifestObject $backendManifest -FrontendManifestObject $frontendManifest

Write-Status "INFO" "Windows-Install-Skelett abgeschlossen."
Write-Status "INFO" "Naechste Schritte:"
Write-Status "INFO" "1. Runtime-Dateien systemweit aktivieren und Nginx anbinden."
Write-Status "INFO" "2. Windows-Service-Wrapper fuer Queue und Scheduler anbinden."
Write-Status "INFO" "3. Repair- und Uninstall-Skripte auf Basis des State-Files anlegen."
