# ===================================================================================
# Powe Assessment Toolkit - Comparison Engine
# Description: Compares source and target datasource profiles to identify gaps.
# ===================================================================================

function Invoke-ReadinessComparison {
    <#
    .SYNOPSIS
        Compares a source and target datasource profile to find missing configurations.
    .PARAMETER SourceProfilePath
        Path to the JSON file containing the source datasource profile.
    .PARAMETER TargetProfilePath
        Path to the JSON file containing the target datasource configuration.
    .PARAMETER OutputPath
        Path to save the JSON comparison report.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$SourceProfilePath,
        [Parameter(Mandatory = $true)][string]$TargetProfilePath,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    Write-Log -Level Info -Message "Starting readiness comparison between '$SourceProfilePath' and '$TargetProfilePath'."

    $sourceProfile = Get-Content -Path $SourceProfilePath -Raw | ConvertFrom-Json
    $targetProfile = Get-Content -Path $TargetProfilePath -Raw | ConvertFrom-Json

    # --- Helper function for safe data extraction and HashSet creation ---
    function Get-SafeHashSet {
        param($Profile, $PropertyName)

        $data = @()
        if ($Profile.PSObject.Properties[$PropertyName]) {
            # CRITICAL FIX: @() forces the result to always be an array,
            # preventing the HashSet constructor overload error when JSON
            # returns a single string instead of a collection.
            $data = @($Profile.$PropertyName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        return [System.Collections.Generic.HashSet[string]]::new(
            [string[]]$data,
            [System.StringComparer]::OrdinalIgnoreCase
        )
    }

    # --- Use HashSets for efficient, case-insensitive comparison ---
    $sourceEnvironments = Get-SafeHashSet -Profile $sourceProfile -PropertyName 'Environments'
    $targetEnvironments = Get-SafeHashSet -Profile $targetProfile -PropertyName 'Environments'
    Write-Log -Level Debug -Message "Source Environments: $($sourceEnvironments.Count), Target Environments: $($targetEnvironments.Count)"

    $sourceWorkflows = Get-SafeHashSet -Profile $sourceProfile -PropertyName 'Workflows'
    $targetWorkflows = Get-SafeHashSet -Profile $targetProfile -PropertyName 'Workflows'
    Write-Log -Level Debug -Message "Source Workflows: $($sourceWorkflows.Count), Target Workflows: $($targetWorkflows.Count)"

    $sourceStates = Get-SafeHashSet -Profile $sourceProfile -PropertyName 'States'
    $targetStates = Get-SafeHashSet -Profile $targetProfile -PropertyName 'States'
    Write-Log -Level Debug -Message "Source States: $($sourceStates.Count), Target States: $($targetStates.Count)"

    # --- Perform the comparison using the highly efficient ExceptWith method ---
    # This modifies the source hashset in-place, leaving only the items not present in the target.
    $sourceEnvironments.ExceptWith($targetEnvironments)
    $sourceWorkflows.ExceptWith($targetWorkflows)
    $sourceStates.ExceptWith($targetStates)

    $missingItems = @{
        MissingEnvironments = $sourceEnvironments | Sort-Object
        MissingWorkflows    = $sourceWorkflows    | Sort-Object
        MissingStates       = $sourceStates       | Sort-Object
        Summary             = @{
            MissingEnvironmentsCount = $sourceEnvironments.Count
            MissingWorkflowsCount    = $sourceWorkflows.Count
            MissingStatesCount       = $sourceStates.Count
        }
    }

    $missingItems | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8

    # FIX: Use the correct *Count properties in the log message, not the arrays themselves.
    Write-Log -Level Info -Message "Readiness comparison complete. Found $($missingItems.Summary.MissingEnvironmentsCount) missing environments, $($missingItems.Summary.MissingWorkflowsCount) missing workflows, $($missingItems.Summary.MissingStatesCount) missing states. Report saved to '$OutputPath'."
}