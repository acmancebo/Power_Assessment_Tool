 # ===================================================================================
# Powe Assessment Toolkit - Utility Functions
# Description: Contains shared functions for logging, configuration, and connections.
# ===================================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Log {
    <#
    .SYNOPSIS
        Writes a formatted message to the console and a log file.
    .PARAMETER Message
        The message to log.
    .PARAMETER Level
        The log level (Info, Warn, Error, Debug).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warn', 'Error', 'Debug')]
        [string]$Level = 'Info'
    )

    # Stop if log level is lower than configured
    $logLevels = @{'Debug' = 0; 'Info' = 1; 'Warn' = 2; 'Error' = 3 }
    if ($logLevels[$Level] -lt $logLevels[$script:config.logLevel]) {
        return
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $formattedMessage = "[$timestamp] [$Level] $Message"

    # Console output with color
    $color = @{
        'Info'  = 'White'
        'Warn'  = 'Yellow'
        'Error' = 'Red'
        'Debug' = 'Gray'
    }[$Level]

    Write-Host $formattedMessage -ForegroundColor $color

    # File output
    if ($script:logFilePath) {
        try {
            Add-Content -Path $script:logFilePath -Value $formattedMessage
        }
        catch {
            Write-Warning "Failed to write to log file: $($script:logFilePath). Error: $($_.Exception.Message)"
        }
    }
}

function Get-Configuration {
    <#
    .SYNOPSIS
        Loads settings from the config.json file.
    #>
    param(
        [string]$ConfigPath
    )
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found at '$ConfigPath'."
    }
    try {
        return Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to read or parse configuration file '$ConfigPath'. Error: $($_.Exception.Message)"
    }
}

function Import-PWPSDabModule {
    <#
    .SYNOPSIS
        Imports PWPS_DAB, honoring an optional version pinned in config/settings.json.
    .DESCRIPTION
        ProjectWise rejects logins with error 58506 ("Client and server versions are
        incompatible") when the installed PWPS_DAB/Explorer client version doesn't match
        what the datasource server expects. Setting 'pwpsDabVersion' in config/settings.json
        (via scripts/Set-PWPSDabVersion.ps1) forces this exact version to be loaded every run.
    #>
    $pinnedVersion = $script:config.pwpsDabVersion
    try {
        if ($pinnedVersion) {
            Import-Module -Name PWPS_DAB -RequiredVersion $pinnedVersion -ErrorAction Stop
        }
        else {
            Import-Module -Name PWPS_DAB -ErrorAction Stop
        }
    }
    catch {
        if ($pinnedVersion) {
            throw "PWPS_DAB version '$pinnedVersion' (pinned in config/settings.json) is not installed. Run '.\scripts\Set-PWPSDabVersion.ps1 -Version $pinnedVersion' to install it, or clear 'pwpsDabVersion' in config/settings.json. Error: $($_.Exception.Message)"
        }
        throw "Could not import the 'PWPS_DAB' module. Run 'Install-Module -Name PWPS_DAB -Scope CurrentUser -Force', or run '.\scripts\Set-PWPSDabVersion.ps1' to pick a version compatible with your ProjectWise server. Error: $($_.Exception.Message)"
    }

    $moduleInfo = Get-Module -Name PWPS_DAB
    if ($moduleInfo) { return $moduleInfo.Version.ToString() }
    return 'unknown'
}

function Connect-PWDatasource {
    <#
    .SYNOPSIS
        Connects to a ProjectWise datasource with a single login attempt.
    .DESCRIPTION
        Performs exactly ONE New-PWLogin call. The native ProjectWise login dialog
        (-UseGui) already lets the user pick the authentication method (Bentley IMS or
        Windows/native) interactively, so retrying with different auth modes automatically
        only produces repeated, confusing login popups and never fixes a real problem.
        Most connection failures for a mismatched client are version issues (error 58506),
        not authentication issues - see Import-PWPSDabModule / scripts/Set-PWPSDabVersion.ps1.
    .PARAMETER AuthMode
        'Auto' (default) lets the login dialog's own Authentication dropdown decide.
        'BentleyIMS' forces IMS-only login (ProjectWise CONNECT Edition).
        'Native' forces native/Windows login (older ProjectWise versions without IMS).
    #>
    param(
        [string]$DatasourceName,
        [ValidateSet('Auto', 'BentleyIMS', 'Native')]
        [string]$AuthMode = 'Auto'
    )
    Write-Log -Level 'Info' -Message "Connecting to datasource '$DatasourceName' (AuthMode: $AuthMode)..."

    $loginParams = @{
        DatasourceName = $DatasourceName
        UseGui         = $true
        ErrorAction    = 'Stop'
    }
    # 'Native' intentionally omits -BentleyIMS. 'Auto' also omits it and leaves the choice
    # to the login dialog's Authentication dropdown, which already supports both methods.
    if ($AuthMode -eq 'BentleyIMS') { $loginParams['BentleyIMS'] = $true }

    try {
        if (New-PWLogin @loginParams) {
            Write-Log -Level 'Info' -Message "Successfully connected to '$DatasourceName'."
            return $true
        }
        throw "Login was cancelled or did not complete."
    }
    catch {
        $errorMessage = $_.Exception.Message

        # Error 58506 / "Client and server versions are incompatible" means the installed
        # PWPS_DAB/Explorer client is a different version than the datasource server expects.
        # This is not an authentication problem, so retrying the login will never help.
        if ($errorMessage -match '(?i)incompatible|58506') {
            Write-Log -Level 'Error' -Message "ProjectWise reported a client/server version mismatch (Error 58506) while connecting to '$DatasourceName'."
            Write-Log -Level 'Error' -Message "Fix: run '.\scripts\Set-PWPSDabVersion.ps1' to check the installed PWPS_DAB version and install one compatible with this server (ask your ProjectWise administrator which version it requires)."
        }
        else {
            Write-Log -Level 'Error' -Message "Failed to connect to '$DatasourceName'. Error: $errorMessage"
        }
        exit 1 # Encerra o processo do PowerShell com um código de erro.
    }
}

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Checks for required modules and PowerShell version.
    #>
    Write-Log -Level Info -Message "Verifying prerequisites..."

    # 1. Check for PWPS_DAB module (honors a pinned version from config/settings.json)
    # Surfaced BEFORE any login attempt: version mismatches (error 58506) are the most
    # common connection failure and are never fixed by retrying the login dialog.
    try {
        $moduleVersion = Import-PWPSDabModule
        $pinnedNote = if ($script:config.pwpsDabVersion) { " (pinned via config/settings.json)" } else { " (not pinned - using default installed version)" }
        Write-Log -Level Info -Message "=================================================="
        Write-Log -Level Info -Message " PWPS_DAB client version: $moduleVersion$pinnedNote"
        Write-Log -Level Info -Message " If login fails with 'Client and server versions are"
        Write-Log -Level Info -Message " incompatible' (error 58506), do NOT retry the login."
        Write-Log -Level Info -Message " Run .\scripts\Set-PWPSDabVersion.ps1 to install the"
        Write-Log -Level Info -Message " version your ProjectWise server requires."
        Write-Log -Level Info -Message "=================================================="
    }
    catch {
        # If import fails, provide a clear error message.
        throw "Prerequisite check failed: $($_.Exception.Message)"
    }

    # 2. Check PowerShell Version (minimum 5.1 recommended)
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Log -Level Warn -Message "PowerShell version is older than 5.1. Some features may not work as expected."
    }

    Write-Log -Level Info -Message "Prerequisites check passed."
    return $true
}