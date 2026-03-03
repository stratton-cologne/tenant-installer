param(
    [Parameter(Mandatory = $true)]
    [string]$AppRoot
)

$ErrorActionPreference = "Stop"

Set-Location -LiteralPath (Join-Path $AppRoot "current")

while ($true) {
    & php artisan queue:work --sleep=3 --tries=3 --timeout=90
    Start-Sleep -Seconds 5
}
