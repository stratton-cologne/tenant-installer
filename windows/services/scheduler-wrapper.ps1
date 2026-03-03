param(
    [Parameter(Mandatory = $true)]
    [string]$AppRoot
)

$ErrorActionPreference = "Stop"

Set-Location -LiteralPath (Join-Path $AppRoot "current")

while ($true) {
    & php artisan schedule:run
    Start-Sleep -Seconds 60
}
