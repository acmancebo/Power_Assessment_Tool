# ===================================================================================
# Powe Assessment Toolkit - Scoring Engine
# Description: Calculates a readiness score based on comparison results.
# ===================================================================================

function Invoke-Scoring {
    <#
    .SYNOPSIS
        Calculates a readiness score from a comparison CSV file.
    .PARAMETER ComparisonPath
        Path to the comparison CSV file.
    .PARAMETER OutputPath
        Path to save the score JSON file.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ComparisonPath,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    Write-Log -Level Info -Message "Starting scoring process for '$ComparisonPath'."

    $comparisonData = Import-Csv -Path $ComparisonPath
    if (-not $comparisonData) {
        Write-Log -Level Warn -Message "Comparison file is empty. Scoring cannot proceed."
        return
    }

    $totalFolders = $comparisonData.Count
    $maxScore = 100.0
    $penalty = 0.0

    # Define penalty weights
    $weights = @{
        "Missing"     = 10  # Per folder
        "Mismatch"    = 2   # Per mismatch (env/workflow)
        "Delta"       = 0.5 # Per document/MB delta
    }

    foreach ($item in $comparisonData) {
        if ($item.Severity -eq 'Critical' -and $item.Issues -match 'Missing') {
            $penalty += $weights.Missing
        }
        if ($item.Issues -match 'Mismatch') {
            $penalty += $weights.Mismatch
        }

        # --- FIX: Safely parse numeric values to prevent crashes on "N/A" ---
        $deltaDocsValue = 0
        [double]::TryParse($item.DeltaDocs, [ref]$deltaDocsValue) | Out-Null

        $deltaSizeValue = 0
        [double]::TryParse($item.DeltaSizeMB, [ref]$deltaSizeValue) | Out-Null

        $penalty += [math]::Abs($deltaDocsValue) * 0.01 * $weights.Delta
        $penalty += [math]::Abs($deltaSizeValue) * 0.01 * $weights.Delta
    }

    # Normalize penalty so it doesn't exceed max score
    $finalPenalty = [math]::Min($penalty, $maxScore)
    $finalScore = [math]::Round($maxScore - $finalPenalty)
    if ($finalScore -lt 0) { $finalScore = 0 }

    $classification = if ($finalScore -ge 90) {
        "Ready"
    } elseif ($finalScore -ge 70) {
        "Moderate Risk"
    } else {
        "High Risk"
    }

    $scoreResult = @{
        Score          = $finalScore
        Classification = $classification
        Details        = "Score calculated from $totalFolders compared items with a total penalty of $([math]::Round($finalPenalty, 2))."
    }

    $scoreResult | ConvertTo-Json | Set-Content -Path $OutputPath
    Write-Log -Level Info -Message "Scoring complete. Score: $finalScore ($classification). Results saved to '$OutputPath'."
}