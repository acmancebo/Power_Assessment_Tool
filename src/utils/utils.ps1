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

function Connect-PWDatasource {
    <#
    .SYNOPSIS
        Connects to a ProjectWise datasource with retry logic.
    #>
    param(
        [string]$DatasourceName
    )
    Write-Log -Level 'Info' -Message "Attempting to connect to datasource '$DatasourceName'..."
    for ($i = 1; $i -le $script:config.retryCount; $i++) {
        try { # Adicionado -ErrorAction Stop para garantir que o catch seja acionado em caso de falha
            if (New-PWLogin -DatasourceName $DatasourceName -BentleyIMS -UseGui -ErrorAction Stop) {
                Write-Log -Level 'Info' -Message "Successfully connected to '$DatasourceName'."
                return $true # Sucesso, sai da função
            } 
            # Se o usuário cancelar a GUI, New-PWLogin retorna $false mas não gera erro.
            throw "User cancelled the login dialog."
        }
        catch {
            Write-Log -Level 'Warn' -Message "Connection attempt $i failed. Error: $($_.Exception.Message)"
            Start-Sleep -Seconds 5
        }
    }
    # Se o loop terminar sem sucesso, encerra o script com uma mensagem clara.
    Write-Log -Level 'Error' -Message "Failed to connect to datasource '$DatasourceName' after $($script:config.retryCount) attempts. Aborting script."
    exit 1 # Encerra o processo do PowerShell com um código de erro.
}

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Checks for required modules and PowerShell version.
    #>
    Write-Log -Level Info -Message "Verifying prerequisites..."

    # 1. Check for PWPS_DAB module
    try {
        # We try to import the module. This is a more robust check than -ListAvailable.
        Import-Module -Name PWPS_DAB -ErrorAction Stop
        Write-Log -Level Debug -Message "PWPS_DAB module imported successfully."
    }
    catch {
        # If import fails, provide a clear error message.
        throw "Prerequisite check failed: Could not import the 'PWPS_DAB' module. Please run 'Install-Module -Name PWPS_DAB -Scope CurrentUser -Force' in an Administrator PowerShell window. Error: $($_.Exception.Message)"
    }

    # 2. Check PowerShell Version (minimum 5.1 recommended)
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Log -Level Warn -Message "PowerShell version is older than 5.1. Some features may not work as expected."
    }

    Write-Log -Level Info -Message "Prerequisites check passed."
    return $true
}