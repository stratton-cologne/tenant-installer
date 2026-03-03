param(
    [string]$BackendRepoUrl = "git@github.com:stratton-cologne/tenant-backend.git",
    [string]$FrontendRepoUrl = "git@github.com:stratton-cologne/tenant-frontend.git",
    [string]$OutputRoot = "",
    [string]$GitHubToken = "",
    [switch]$IncludePrerelease
)

$ErrorActionPreference = "Stop"

function Write-Status {
    param(
        [string]$Level,
        [string]$Message
    )

    Write-Host "[$Level] $Message"
}

function Get-RepositoryParts {
    param(
        [string]$RepoUrl
    )

    if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
        throw "Repository-URL darf nicht leer sein."
    }

    $value = $RepoUrl.Trim()

    if ($value -match '^git@github\.com:(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$') {
        return [pscustomobject]@{
            Owner = $Matches.owner
            Repo = $Matches.repo
            Slug = "$($Matches.owner)/$($Matches.repo)"
        }
    }

    if ($value -match '^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$') {
        return [pscustomobject]@{
            Owner = $Matches.owner
            Repo = $Matches.repo
            Slug = "$($Matches.owner)/$($Matches.repo)"
        }
    }

    throw "Nicht unterstuetzte Repository-URL: $RepoUrl"
}

function New-GitHubHeaders {
    param(
        [string]$Token
    )

    $headers = @{
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "tenant-installer-fetch-releases"
    }

    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers.Authorization = "Bearer $Token"
    }

    return $headers
}

function Get-LatestRelease {
    param(
        [pscustomobject]$Repository,
        [hashtable]$Headers
    )

    $uri = "https://api.github.com/repos/$($Repository.Owner)/$($Repository.Repo)/releases"
    $releases = Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get

    if ($null -eq $releases) {
        throw "Keine Release-Daten erhalten fuer $($Repository.Slug)"
    }

    $selectedRelease = $releases |
        Where-Object { -not $_.draft } |
        Where-Object { $IncludePrerelease -or (-not $_.prerelease) } |
        Select-Object -First 1

    if ($null -eq $selectedRelease) {
        $mode = if ($IncludePrerelease) { "inklusive Prereleases" } else { "ohne Prereleases" }
        throw "Kein passendes Release gefunden fuer $($Repository.Slug) ($mode)."
    }

    return $selectedRelease
}

function Save-ReleaseMetadata {
    param(
        [string]$TargetPath,
        [pscustomobject]$Repository,
        [object]$Release
    )

    $metadata = [ordered]@{
        repository = $Repository.Slug
        release_id = $Release.id
        release_name = $Release.name
        tag_name = $Release.tag_name
        is_prerelease = [bool]$Release.prerelease
        published_at = $Release.published_at
        html_url = $Release.html_url
        zipball_url = $Release.zipball_url
        tarball_url = $Release.tarball_url
        assets = @(
            @($Release.assets) | ForEach-Object {
                [ordered]@{
                    name = $_.name
                    size = $_.size
                    content_type = $_.content_type
                    download_url = $_.browser_download_url
                }
            }
        )
    }

    $json = $metadata | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $TargetPath -Value $json -Encoding UTF8
}

function Download-ReleaseAssets {
    param(
        [string]$ComponentName,
        [pscustomobject]$Repository,
        [object]$Release,
        [hashtable]$Headers,
        [string]$BaseOutputRoot
    )

    $tag = [string]$Release.tag_name
    $componentRoot = Join-Path $BaseOutputRoot $ComponentName
    $releaseRoot = Join-Path $componentRoot $tag
    $assetsRoot = Join-Path $releaseRoot "assets"
    $metadataPath = Join-Path $releaseRoot "release.json"

    New-Item -ItemType Directory -Force -Path $assetsRoot | Out-Null

    Write-Status "INFO" ("Ausgewaehltes Release fuer {0}: {1} @{2}" -f $ComponentName, $Repository.Slug, $tag)

    $assets = @($Release.assets)

    if ($assets.Count -eq 0) {
        Write-Status "WARN" "Release hat keine Assets: $($Repository.Slug) @$tag"
        $sourceArchiveName = "$ComponentName-$tag-source.zip"
        $sourceArchivePath = Join-Path $assetsRoot $sourceArchiveName
        Write-Status "INFO" "Lade Source-ZIP des Releases: $sourceArchiveName"
        Invoke-WebRequest -Uri $Release.zipball_url -Headers $Headers -OutFile $sourceArchivePath
    }
    else {
        foreach ($asset in $assets) {
            $targetFile = Join-Path $assetsRoot $asset.name
            Write-Status "INFO" "Lade Asset: $($asset.name)"
            Invoke-WebRequest -Uri $asset.browser_download_url -Headers $Headers -OutFile $targetFile
        }
    }

    Save-ReleaseMetadata -TargetPath $metadataPath -Repository $Repository -Release $Release
    Write-Status "INFO" "Release-Metadaten gespeichert: $metadataPath"

    return [pscustomobject]@{
        Component = $ComponentName
        Repository = $Repository.Slug
        Tag = $tag
        ReleaseRoot = $releaseRoot
        AssetCount = $assets.Count
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$windowsRoot = Split-Path -Parent $scriptRoot

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $windowsRoot "output\releases"
}

if ([string]::IsNullOrWhiteSpace($GitHubToken)) {
    $GitHubToken = $env:GITHUB_TOKEN
}

$headers = New-GitHubHeaders -Token $GitHubToken
$backendRepository = Get-RepositoryParts -RepoUrl $BackendRepoUrl
$frontendRepository = Get-RepositoryParts -RepoUrl $FrontendRepoUrl

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

Write-Status "INFO" "Starte Release-Bezug"

$backendRelease = Get-LatestRelease -Repository $backendRepository -Headers $headers
$frontendRelease = Get-LatestRelease -Repository $frontendRepository -Headers $headers

$backendResult = Download-ReleaseAssets -ComponentName "backend" -Repository $backendRepository -Release $backendRelease -Headers $headers -BaseOutputRoot $OutputRoot
$frontendResult = Download-ReleaseAssets -ComponentName "frontend" -Repository $frontendRepository -Release $frontendRelease -Headers $headers -BaseOutputRoot $OutputRoot

Write-Status "INFO" "Release-Bezug abgeschlossen"
Write-Status "INFO" "Backend: $($backendResult.Repository) @$($backendResult.Tag) -> $($backendResult.ReleaseRoot)"
Write-Status "INFO" "Frontend: $($frontendResult.Repository) @$($frontendResult.Tag) -> $($frontendResult.ReleaseRoot)"
