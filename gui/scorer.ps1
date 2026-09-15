function Invoke-Scoring {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$RunOutputPath
    )

    $startTime = Get-Date
    Write-Log -Level Info -Message "--- Starting Scoring Phase ---"

    $comparisonJsonPath = Join-Path $RunOutputPath 'C.json'
    if (-not (Test-Path $comparisonJsonPath)) {
        throw "Scoring failed: Comparison data file '$comparisonJsonPath' not found."
    }

    # Use -Raw to read the entire file content at once, which is more efficient for JSON parsing.
    $data = Get-Content $comparisonJsonPath -Raw | ConvertFrom-Json

    $issues = [System.Collections.Generic.List[object]]::new()
    $totalItems = 0
    $totalIssues = 0

    # 1. Process Folders
    if ($data.ComparisonResults.Folders) {
        foreach ($folder in $data.ComparisonResults.Folders) {
            $totalItems++
            $severity = 'OK'
            if ($folder.Status -ne 'Found') {
                $severity = 'High'
                $totalIssues++
            }
            $issues.Add([PSCustomObject]@{
                Category = 'Folder Structure'
                Item     = $folder.Path
                Status   = $folder.Status
                Severity = $severity
                Details  = if ($severity -ne 'OK') { "Folder not found in target datasource." } else { "Folder exists in target." }
            })
        }
    }

    # 2. Process Environments and Attributes
    if ($data.ComparisonResults.Environments) {
        foreach ($env in $data.ComparisonResults.Environments) {
            $totalItems++
            $envSeverity = 'OK'
            if ($env.Status -ne 'Found') {
                $envSeverity = 'High'
                $totalIssues++
            }
            $issues.Add([PSCustomObject]@{
                Category = 'Configuration: Environment'
                Item     = $env.Name
                Status   = $env.Status
                Severity = $envSeverity
                Details  = if ($envSeverity -ne 'OK') { "Environment not found in target." } else { "Environment found." }
            })

            if ($env.Status -eq 'Found' -and $env.Columns) {
                foreach ($col in $env.Columns) {
                    $totalItems++
                    $colSeverity = 'OK'
                    if ($col.Status -ne 'Match') {
                        $colSeverity = 'Medium'
                        $totalIssues++
                    }
                    $issues.Add([PSCustomObject]@{
                        Category = 'Configuration: Attribute'
                        Item     = "$($env.Name) | $($col.Name)"
                        Status   = $col.Status
                        Severity = $colSeverity
                        Details  = if ($colSeverity -ne 'OK') { "Attribute mismatch. Source: $($col.SourceProps), Target: $($col.TargetProps)" } else { "Attribute matches." }
                    })
                }
            }
        }
    }

    # 3. Process Workflows and States
    if ($data.ComparisonResults.Workflows) {
        foreach ($wf in $data.ComparisonResults.Workflows) {
            $totalItems++
            $wfSeverity = 'OK'
            if ($wf.Status -ne 'Found') {
                $wfSeverity = 'High'
                $totalIssues++
            }
            $issues.Add([PSCustomObject]@{
                Category = 'Configuration: Workflow'
                Item     = $wf.Name
                Status   = $wf.Status
                Severity = $wfSeverity
                Details  = if ($wfSeverity -ne 'OK') { "Workflow not found in target." } else { "Workflow found." }
            })

            if ($wf.Status -eq 'Found' -and $wf.States) {
                foreach ($state in $wf.States) {
                    $totalItems++
                    $stateSeverity = 'OK'
                    if ($state.Status -ne 'Found') {
                        $stateSeverity = 'Medium'
                        $totalIssues++
                    }
                    $issues.Add([PSCustomObject]@{
                        Category = 'Configuration: State'
                        Item     = "$($wf.Name) | $($state.Name)"
                        Status   = $state.Status
                        Severity = $stateSeverity
                        Details  = if ($stateSeverity -ne 'OK') { "State not found in target workflow." } else { "State exists in target workflow." }
                    })
                }
            }
        }
    }

    # 4. Export Comparison.csv
    $comparisonCsvPath = Join-Path $RunOutputPath 'Comparison.csv'
    try {
        $issues | Export-Csv -Path $comparisonCsvPath -NoTypeInformation -Encoding UTF8
        Write-Log -Level Info -Message "Detailed comparison CSV saved to '$comparisonCsvPath'"
    } catch {
        Write-Log -Level Error -Message "Failed to write Comparison.csv: $($_.Exception.Message)"
    }

    # 5. Calculate Score and Classification
    $score = 0
    if ($totalItems -gt 0) {
        $score = [math]::Round((($totalItems - $totalIssues) / $totalItems) * 100)
    }

    $classification = 'High Risk'
    if ($score -ge 95) {
        $classification = 'Ready'
    } elseif ($score -ge 80) {
        $classification = 'Moderate Risk'
    }

    $breakdown = @{}
    $issues | Group-Object -Property Severity | ForEach-Object { $breakdown[$_.Name] = $_.Count }

    $scoreData = @{
        Score          = $score
        Classification = $classification
        TotalItems     = $totalItems
        TotalIssues    = $totalIssues
        Breakdown      = $breakdown
    }

    # 6. Export Score.json
    $scoreJsonPath = Join-Path $RunOutputPath 'Score.json'
    try {
        $jsonContent = $scoreData | ConvertTo-Json -Depth 5
        $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($scoreJsonPath, $jsonContent, $Utf8NoBomEncoding)
        Write-Log -Level Info -Message "Scoring report saved to '$scoreJsonPath'"
    } catch {
        Write-Log -Level Error -Message "Failed to write Score.json: $($_.Exception.Message)"
    }

    $endTime = Get-Date
    $duration = New-TimeSpan -Start $startTime -End $endTime
    Write-Log -Level Info -Message "Scoring analysis completed in $([math]::Round($duration.TotalSeconds,2)) seconds."
    Write-Log -Level Info -Message "--- Scoring Finished ---"
}