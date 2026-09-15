<#
.SYNOPSIS
    Lists installed/available PWPS_DAB versions and installs a chosen one side-by-side.
.DESCRIPTION
    ProjectWise rejects logins with error 58506 ("Client and server versions are
    incompatible") when the installed PWPS_DAB/Explorer client version does not match what
    the datasource server expects. This script lets you install an older (or specific)
    PWPS_DAB version without removing the one already installed, and pins it in
    config/settings.json so every assessment run uses that exact version.
.PARAMETER Version
    Install this specific PWPS_DAB version non-interactively (e.g. "10.00.02.10").
.PARAMETER ListOnly
    Only list installed and available versions, without installing or pinning anything.
.EXAMPLE
    .\Set-PWPSDabVersion.ps1
.EXAMPLE
    .\Set-PWPSDabVersion.ps1 -Version "10.00.02.10"
.EXAMPLE
    .\Set-PWPSDabVersion.ps1 -ListOnly
#>
param(
    [string]$Version,
    [switch]$ListOnly
)

Write-Host "=== PWPS_DAB Version Manager ===" -ForegroundColor Cyan

$installed = Get-Module -Name PWPS_DAB -ListAvailable | Sort-Object Version -Descending
if ($installed) {
    Write-Host "`nInstalled versions:" -ForegroundColor Green
    $installed | ForEach-Object { Write-Host "  - $($_.Version)  ($($_.ModuleBase))" }
}
else {
    Write-Host "`nNo PWPS_DAB version is currently installed." -ForegroundColor Yellow
}

Write-Host "`nQuerying available versions from the registered PowerShell repository..." -ForegroundColor Cyan
try {
    $available = Find-Module -Name PWPS_DAB -AllVersions -ErrorAction Stop | Sort-Object Version -Descending
}
catch {
    Write-Host "Could not query for available versions: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "If PWPS_DAB is distributed through an internal/private repository, ask your ProjectWise administrator for its name/URL and register it first with Register-PSRepository." -ForegroundColor Yellow
    return
}

if (-not $available) {
    Write-Host "No versions found on the registered repository." -ForegroundColor Yellow
    return
}

Write-Host "`nAvailable versions:" -ForegroundColor Green
$available | Select-Object -First 20 | ForEach-Object { Write-Host "  - $($_.Version)" }

if ($ListOnly) { return }

if (-not $Version) {
    Write-Host "`nAsk your ProjectWise administrator which client version the target datasource server requires." -ForegroundColor Cyan
    $Version = Read-Host "Enter the exact PWPS_DAB version to install (or press Enter to cancel)"
    if ([string]::IsNullOrWhiteSpace($Version)) {
        Write-Host "Cancelled. No changes made." -ForegroundColor Yellow
        return
    }
}

$match = $available | Where-Object { $_.Version -eq $Version }
if (-not $match) {
    Write-Host "Version '$Version' was not found on the repository. See the list above for valid versions." -ForegroundColor Red
    return
}

Write-Host "`nInstalling PWPS_DAB $Version (side-by-side with any existing versions)..." -ForegroundColor Cyan
try {
    Install-Module -Name PWPS_DAB -RequiredVersion $Version -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    Write-Host "Installed successfully." -ForegroundColor Green
}
catch {
    Write-Host "Failed to install PWPS_DAB $Version : $($_.Exception.Message)" -ForegroundColor Red
    return
}

# Pin this version in config/settings.json so master.ps1 always loads it explicitly.
$settingsPath = Join-Path $PSScriptRoot '..\config\settings.json'
if (Test-Path $settingsPath) {
    try {
        $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
        $settings | Add-Member -NotePropertyName 'pwpsDabVersion' -NotePropertyValue $Version -Force
        $settings | ConvertTo-Json -Depth 5 | Set-Content -Path $settingsPath -Encoding UTF8
        Write-Host "Pinned pwpsDabVersion = '$Version' in config/settings.json." -ForegroundColor Green
    }
    catch {
        Write-Host "Installed the module, but could not update config/settings.json automatically: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Set `"pwpsDabVersion`": `"$Version`" manually in config/settings.json." -ForegroundColor Yellow
    }
}

Write-Host "`nDone. Every assessment run will now import PWPS_DAB $Version specifically." -ForegroundColor Cyan
