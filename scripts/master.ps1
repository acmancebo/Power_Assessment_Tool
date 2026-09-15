# ===================================================================================
# Powe Assessment Toolkit - Master Execution Script
# Description: Orchestrates the entire assessment process from collection to scoring.
# ===================================================================================

<#
.SYNOPSIS
    Runs the complete ProjectWise datasource assessment.
.PARAMETER DatasourceA
    The source datasource name (e.g., "pw.host.com:DatasourceA").
.PARAMETER DatasourceB
    The target datasource name (e.g., "pw.host.com:DatasourceB").
.PARAMETER Paths
    A semicolon-separated string of folder paths to assess.
.EXAMPLE
    .\master.ps1 -DatasourceA "host:ds_a" -DatasourceB "host:ds_b" -Paths "Folder1;Folder2\Sub"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$DatasourceA,

    [Parameter(Mandatory = $true)]
    [string]$DatasourceB,

    [Parameter(Mandatory = $true)]
    [string]$Paths,

    # Controls how ProjectWise authenticates: Auto (default, tries Bentley IMS then falls back
    # to native/Windows login), BentleyIMS (CONNECT Edition only), or Native (older ProjectWise
    # versions without IMS). Defaults to the value in config/settings.json when not provided.
    [ValidateSet('Auto', 'BentleyIMS', 'Native')]
    [string]$AuthMode,

    # This parameter is passed by the Node.js backend for parallel runs.
    # It defaults to the root output directory for manual execution.
    [string]$RunOutputPath
)

$startTime = Get-Date

# --- 0. Set Output Encoding ---
# Force PowerShell to use UTF-8 for all console output to prevent character corruption when called by Node.js
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# Also set the default encoding for pipeline operations to ensure consistency.
$OutputEncoding = [System.Text.Encoding]::UTF8
# Set the default encoding for file-reading cmdlets to prevent misinterpretation of BOM-less UTF-8 files.
$PSDefaultParameterValues['Get-Content:Encoding'] = 'UTF8'

# --- 1. Initialization ---
# If RunOutputPath was not provided (e.g., manual run), set a default relative to the script's location.
if ($RunOutputPath) {
    $RunOutputPath = $RunOutputPath.Trim().Trim("'").Trim('"')
} else {
    $RunOutputPath = (Join-Path $PSScriptRoot '..\output')
}
# Ensure the dynamic run output directory exists before proceeding
if (-not (Test-Path $RunOutputPath)) {
    [void][System.IO.Directory]::CreateDirectory($RunOutputPath)
}
# $PSScriptRoot is an automatic variable containing the script's directory.
$baseDir = Resolve-Path (Join-Path $PSScriptRoot "..\")

# Define paths for key directories
$srcDir = Join-Path $baseDir 'src'
$configDir = Join-Path $baseDir 'config'
$outputDir = Join-Path $baseDir 'output'
$logDir = Join-Path $baseDir 'logs'
$utilsModule = Join-Path $srcDir 'utils\utils.ps1'

# Validate that the core utility module exists before proceeding.
if (-not (Test-Path $utilsModule)) {
    throw "Critical file missing: Could not find utils.ps1 at '$utilsModule'. Please restore the file and try again."
}
# Dot-source utility functions to make them available in the current scope.
. $utilsModule

# Setup logging and output directories, creating them if they don't exist.
if (-not (Test-Path $logDir)) {
    Write-Host "Creating log directory at '$logDir'..."
    New-Item -ItemType Directory -Path $logDir | Out-Null
}
$script:logFilePath = Join-Path $logDir "assessment_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Load configuration
$configFile = Join-Path $configDir 'settings.json'
if (-not (Test-Path $configFile)) {
    throw "Configuration file missing: settings.json not found at '$configFile'."
}
$script:config = Get-Configuration -ConfigPath $configFile

# Resolve the authentication mode: explicit parameter wins, otherwise fall back to config, then 'Auto'.
if (-not $AuthMode) {
    $AuthMode = if ($script:config.authMode) { $script:config.authMode } else { 'Auto' }
}

Write-Log -Level Info -Message "=================================================="
Write-Log -Level Info -Message " Powe Assessment Toolkit - Started"
Write-Log -Level Info -Message "=================================================="
Write-Log -Level Info -Message "Datasource A (Source): $DatasourceA"
Write-Log -Level Info -Message "Datasource B (Target): $DatasourceB"
Write-Log -Level Info -Message "Paths to Assess: $Paths"
Write-Log -Level Info -Message "Authentication Mode: $AuthMode"

try {
    Import-PWPSDabModule | Out-Null

    # Split the paths string into an array.
    # Crucially, trim whitespace and then any surrounding single or double quotes
    # that might be added by the shell or calling environment.
    $pathsArray = $Paths -split ';' | ForEach-Object { $_.Trim().Trim("'").Trim('"') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    # --- Dot-source module functions ---
    $moduleFiles = @(
        (Join-Path $srcDir 'collector\collector.ps1')
        (Join-Path $srcDir 'comparer\comparer.ps1')
        (Join-Path $srcDir 'scoring\scoring.ps1')
    )

    foreach ($moduleFile in $moduleFiles) {
        if (-not (Test-Path $moduleFile)) {
            throw "Module file missing: '$moduleFile' not found."
        }
        Write-Log -Level Info "Loading module: $(Split-Path $moduleFile -Leaf)"
        . $moduleFile
    }

    # --- 2. Pre-flight Checks ---
    Write-Log -Level Info "--- Starting Pre-flight Checks ---"
    Test-Prerequisites

    # Check Datasource A connection
    Write-Log -Level Info "Checking connection to Datasource A: $DatasourceA"
    Connect-PWDatasource -DatasourceName $DatasourceA -AuthMode $AuthMode
    
    # Check Datasource B connection
    Write-Log -Level Info "Checking connection to Datasource B: $DatasourceB"
    Connect-PWDatasource -DatasourceName $DatasourceB -AuthMode $AuthMode

    # Set session to A for path validation
    [void](Set-PWSession -Datasource $DatasourceA)
    Write-Log -Level Info "Session for Datasource A is active. Validating input paths..."

    # Validate each path before starting the long collection process
    foreach ($path in $pathsArray) {
        Write-Log -Level Info "Validating path: '$path'..."
        if (-not (Get-PWFolders -FolderPath $path -JustOne -ErrorAction SilentlyContinue)) {
            # Throw a specific, helpful error that stops the script immediately
            throw "Path validation failed. The folder path '$path' was not found in Datasource A '$DatasourceA'. Please correct the path and try again."
        }
    }
    Write-Log -Level Info "All input paths are valid."
    Write-Log -Level Info "--- Pre-flight Checks Finished ---"

    # --- 3. Data Collection ---
    Write-Log -Level Info "--- Starting Data Collection Phase ---"
    Invoke-SourceDataCollection -Paths $pathsArray -RunOutputPath $RunOutputPath
    $outputA = Join-Path $RunOutputPath 'A.json'
    if (-not (Test-Path $outputA)) {
        throw "Data collection for Datasource A failed. The output file '$outputA' was not created, likely because the source path was not found or was empty."
    }

    Write-Log -Level Info "--- Data Collection Finished ---"

    # --- 4. Comparison Phase ---
    Write-Log -Level Info "--- Starting Comparison Phase ---"
    Write-Log -Level Info "Session for Datasource B is active. Starting comparison..."
    [void](Set-PWSession -Datasource $DatasourceB)

    # The comparison script needs the path to the source data (A.json)
    Invoke-Comparison -SourceJsonPath $outputA -RunOutputPath $RunOutputPath
    $outputC = Join-Path $RunOutputPath 'C.json'
    if (-not (Test-Path $outputC)) {
        throw "Comparison phase failed. The output file '$outputC' was not created."
    }
    Write-Log -Level Info "--- Comparison Finished ---"

    # --- 5. Scoring Phase ---
    # This script generates the Score.json and Comparison.csv files needed by the backend.
    # The scoring script needs the path to the comparison results (C.json)
    Invoke-Scoring -ComparisonPath $outputC -OutputPath (Join-Path $RunOutputPath 'Score.json')

}
catch {
    Write-Log -Level Error -Message "A critical error occurred: $($_.Exception.Message)"
    # Provide a more helpful message for the most common collection failure.
    if ($_.Exception.Message -like '*No folders were found*') {
        Write-Log -Level Warn -Message "This usually means the folder path specified in the '-Paths' parameter could not be found or is empty."
        Write-Log -Level Warn -Message "Please verify the folder path exists in ProjectWise Explorer and that you have permission to view it."
    }
    Write-Log -Level Debug -Message "Stack Trace: $($_.ScriptStackTrace)"
}
finally {
    $endTime = Get-Date
    # Ensure all sessions are closed, even if an error occurred.
    [void](Undo-PWLogin -ErrorAction SilentlyContinue)
    $duration = New-TimeSpan -Start $startTime -End $endTime
    Write-Log -Level Info -Message "=================================================="
    Write-Log -Level Info -Message " Assessment Finished"
    Write-Log -Level Info -Message " Total Execution Time: $($duration.TotalSeconds) seconds"
    Write-Log -Level Info -Message " Review the results using the 'View Dashboard' button in the web interface."
    Write-Log -Level Info -Message "=================================================="
}