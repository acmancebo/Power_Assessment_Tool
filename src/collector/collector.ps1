function Invoke-SourceDataCollection {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Paths,

        [Parameter(Mandatory = $true)]
        [string]$RunOutputPath
    )

    $RunOutputPath = $RunOutputPath.Trim().Trim("'").Trim('"')
    $startTime = Get-Date
    Write-Log -Level Info -Message "Starting ProjectWise data collection at $startTime"

    # ==========================================
    # 1. FOLDER TRAVERSAL
    # ==========================================
    Write-Log -Level Info -Message "Phase 1: Starting folder traversal..."

    $allFoldersInSubtree = [System.Collections.Generic.List[object]]::new()

    foreach ($rootPath in $Paths) {
        if ([string]::IsNullOrWhiteSpace($rootPath)) {
            continue
        }
        try {
            # Sanitize the path by removing any trailing backslash, which can cause errors with Get-PWFolders.
            $sanitizedRootPath = $rootPath.TrimEnd('\')
            if ([string]::IsNullOrWhiteSpace($sanitizedRootPath)) {
                continue
            }

            Write-Log -Level Info -Message "Discovering all folders recursively under '$sanitizedRootPath'..."
            # Get all folders recursively under the root path, including the root itself.
            # This ensures 'Depth' is populated for all folders.
            $currentSubtreeFolders = $null

            # Tentativa 1 (Preferencial): Usar -FolderPath.
            # O cmdlet retorna $null se não encontrar, então não usamos try/catch aqui.
            $currentSubtreeFolders = Get-PWFolders -FolderPath $sanitizedRootPath -PopulatePaths -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            # Tentativa 2 (Fallback): Se -FolderPath falhar (retornar $null), tente com -FolderName.
            if ($null -eq $currentSubtreeFolders) {
                Write-Log -Level Debug -Message "Get-PWFolders with -FolderPath returned null. Retrying with -FolderName as a fallback."
                $currentSubtreeFolders = Get-PWFolders -FolderName $sanitizedRootPath -PopulatePaths -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            }

            # If Get-PWFolders fails or returns nothing (e.g., invalid path), it might return $null.
            if ($null -eq $currentSubtreeFolders) {
                Write-Log -Level Warn -Message "No folders returned for path '$sanitizedRootPath'. It might be an invalid path. Skipping."
                continue # Skip to the next root path in the loop
            }

            $rootFolderObject = $currentSubtreeFolders | Where-Object { $_.FullPath -eq $sanitizedRootPath } | Select-Object -First 1

            $excludedProjectIDs = [System.Collections.Generic.HashSet[int]]::new()

            if ($rootFolderObject) {
                # Identify direct children of the root (Level 2 folders relative to the initial root)
                # that start with '_'
                $level2FoldersToExclude = $currentSubtreeFolders | Where-Object {
                    $_.ParentID -eq $rootFolderObject.ProjectID -and $_.Name -like '_*'
                }

                foreach ($folderToExclude in $level2FoldersToExclude) {
                    Write-Log -Level Debug -Message "Marking folder '$($folderToExclude.FullPath)' (ID: $($folderToExclude.ProjectID)) and its descendants for exclusion (starts with '_')."
                    # Add the folder itself to the exclusion list
                    [void]$excludedProjectIDs.Add($folderToExclude.ProjectID)

                    # Add all its descendants
                    $descendants = $currentSubtreeFolders | Where-Object {
                        $_.FullPath -like "$($folderToExclude.FullPath)\*"
                    }
                    foreach ($descendant in $descendants) {
                        [void]$excludedProjectIDs.Add($descendant.ProjectID)
                    }
                }
            }

            # Filter the initial list of all folders, keeping only those not in the excluded list
            $finalFilteredFolders = $currentSubtreeFolders | Where-Object {
                -not $excludedProjectIDs.Contains($_.ProjectID)
            }

            $allFoldersInSubtree.AddRange($finalFilteredFolders)
        }
        catch {
            Write-Log -Level Error -Message "Root folder error: '$($rootPath)' -> $($_.Exception.Message)"
        }
    }
    if ($allFoldersInSubtree.Count -eq 0) {
        # CRITICAL FIX: Throw an error to stop the master script from proceeding with stale data.
        throw "No folders were found for the specified paths. Aborting data collection."
    }

    # Garante que as pastas sejam únicas pelo ID e remove quaisquer objetos nulos.
    $uniqueFolders = @($allFoldersInSubtree | Where-Object { $_ } | Sort-Object -Property ProjectID -Unique)

    # HIDRATAÇÃO DOS OBJETOS: A chamada inicial com -PopulatePaths é rápida, mas retorna objetos "leves".
    # Desativado por padrão para evitar gargalos e falhas de lote da API PWPS_DAB. Os objetos leves já possuem todos os metadados necessários.
    $needsHydration = $false
    $hasCreationDate = $false
    if ($uniqueFolders.Count -gt 0) {
        $sample = $uniqueFolders[0]
        $dateProp = $sample.CreationDate
        if (-not $dateProp) { $dateProp = $sample.CreationDateTime }
        if (-not $dateProp) { $dateProp = $sample.CreateDateTime }
        if ($dateProp -and $dateProp -is [System.DateTime] -and $dateProp.Year -gt 1900) {
            $hasCreationDate = $true
        }
    }

    if ($hasCreationDate) {
        $needsHydration = $false
        Write-Log -Level Info -Message "Folder properties are already populated on root objects. Skipping hydration phase!"
    }

    if ($needsHydration) {
        Write-Log -Level Info -Message "Retrieving full properties for $($uniqueFolders.Count) folders in high-performance batches..."
        $hydratedFolders = [System.Collections.Generic.List[object]]::new()
        $folderIDs = $uniqueFolders.ProjectID | Where-Object { $null -ne $_ }
        $chunkSize = 300 
        $totalIDs = $folderIDs.Count

        # Detecta dinamicamente se o cmdlet nativo Get-PWFolders aceita array de IDs
        $supportsArray = $false
        try {
            $folderIDParam = (Get-Command Get-PWFolders -ErrorAction SilentlyContinue).Parameters['FolderID']
            if ($null -ne $folderIDParam) {
                $supportsArray = $folderIDParam.ParameterType.IsArray -or $folderIDParam.ParameterType.FullName -like '*[]*'
            }
        } catch {
            $supportsArray = $false
        }
        Write-Log -Level Debug -Message "Natively supports folder ID array hydration: $supportsArray"

        for ($i = 0; $i -lt $totalIDs; $i += $chunkSize) {
            # Evita padding de nulos no final do fatiamento de arrays usando Select-Object
            $batchIDs = @($folderIDs | Select-Object -Skip $i -First $chunkSize)
            $batchNumber = [math]::Floor($i / $chunkSize) + 1
            $totalBatches = [math]::Ceiling($totalIDs / $chunkSize)
            
            Write-Log -Level Info -Message "Hydrating batch $batchNumber of $totalBatches (folders $i to $($i + $batchIDs.Count - 1))..."
            
            $batchFolders = $null
            $success = $false

            # Método 1: Chamada nativa otimizada por Array tipado (Se suportado)
            if ($supportsArray) {
                try {
                    $batchFolders = Get-PWFolders -FolderID ([int[]]$batchIDs) -ErrorAction Stop
                    $success = $true
                } catch {
                    Write-Log -Level Debug -Message "Native array folder ID batch failed: $($_.Exception.Message)"
                }
            }

            # Método 2: Fallback SQL qualificado de alta performance (Garante não-ambiguidade)
            if (-not $success) {
                try {
                    $sqlClause = "o_projectno IN ($($batchIDs -join ','))"
                    $batchFolders = Get-PWFolders -SQLSelect $sqlClause -ErrorAction Stop
                    $success = $true
                } catch {
                    Write-Log -Level Debug -Message "SQLSelect folder ID batch failed: $($_.Exception.Message)"
                }
            }

            if ($success -and $batchFolders) {
                $hydratedFolders.AddRange($batchFolders)
            } else {
                Write-Log -Level Warn -Message "Batch $batchNumber failed bulk hydration. Falling back to safe individual hydration..."
                foreach ($id in $batchIDs) {
                    try {
                        $singleFolder = Get-PWFolders -FolderID $id -JustOne -ErrorAction SilentlyContinue
                        if ($singleFolder) { $hydratedFolders.Add($singleFolder) }
                    }
                    catch {
                        $light = $uniqueFolders | Where-Object { $_.ProjectID -eq $id } | Select-Object -First 1
                        if ($light) { $hydratedFolders.Add($light) }
                    }
                }
            }
        }
        if ($hydratedFolders.Count -lt $uniqueFolders.Count) {
            $hydratedIDs = [System.Collections.Generic.HashSet[int]]::new([int[]]$hydratedFolders.ProjectID)
            foreach ($folder in $uniqueFolders) {
                if (-not $hydratedIDs.Contains($folder.ProjectID)) { $hydratedFolders.Add($folder) }
            }
        }
        $uniqueFolders = $hydratedFolders.ToArray()
    }

    $maxDepth = ($uniqueFolders.Depth | Measure-Object -Maximum).Maximum

    Write-Log -Level Info -Message "Phase 1 complete: $($uniqueFolders.Count) unique folders found. Max Depth: $($maxDepth)."

    # ==========================================
    # 2. PREPARE FOLDER DATA FOR OUTPUT
    # ==========================================
    Write-Log -Level Info -Message "Phase 2: Preparing detailed folder data for output..."
    Write-Log -Level Info -Message "Bulk-loading all documents in optimized folder-ID batches..."

    $allDocsHashtable = @{}
    $folderIDs = $uniqueFolders.ProjectID | Where-Object { $null -ne $_ }
    $chunkSize = 100
    $totalIDs = $folderIDs.Count

    for ($i = 0; $i -lt $totalIDs; $i += $chunkSize) {
        $batchIDs = @($folderIDs | Select-Object -Skip $i -First $chunkSize)
        $batchNumber = [math]::Floor($i / $chunkSize) + 1
        $totalBatches = [math]::Ceiling($totalIDs / $chunkSize)
        
        Write-Log -Level Info -Message "Fetching documents for folder batch $batchNumber of $totalBatches (folders $i to $($i + $batchIDs.Count - 1))..."
        try {
            $chunkDocs = Get-PWDocumentsBySearch -FolderID ([int[]]$batchIDs) -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            if ($chunkDocs) {
                foreach ($doc in $chunkDocs) {
                    if ($null -ne $doc.ProjectID) {
                        if (-not $allDocsHashtable.ContainsKey($doc.ProjectID)) {
                            $allDocsHashtable[$doc.ProjectID] = [System.Collections.Generic.List[object]]::new()
                        }
                        $allDocsHashtable[$doc.ProjectID].Add($doc)
                    }
                }
            }
        }
        catch {
            Write-Log -Level Warn -Message "Failed to fetch documents for folder batch ${batchNumber}: $($_.Exception.Message)"
        }
    }

    # Reestruturado para um loop foreach para maior robustez e clareza.
    $folderDetailsList = [System.Collections.Generic.List[object]]::new()
    $processedFolderCount = 0
    $totalFolderCount = $uniqueFolders.Count

    foreach ($folder in ($uniqueFolders | Sort-Object -Property FullPath)) {
        $processedFolderCount++
        $progress = [math]::Round(($processedFolderCount / $totalFolderCount) * 100)
        Write-Log -Level Info -Message "Processing folder ${processedFolderCount} of ${totalFolderCount}: $($folder.FullPath)"
        
        # Envia o progresso para o Information Stream, que pode ser capturado pela UI.
        # O formato "PROGRESS::valor" é uma convenção para ser facilmente identificado.
        Write-Host "PROGRESS::$progress"
        $docCount = 0
        $totalSize = 0
        
        if ($allDocsHashtable.ContainsKey($folder.ProjectID)) {
            $docsInFolder = $allDocsHashtable[$folder.ProjectID]
            $docCount = $docsInFolder.Count
            $totalSize = ($docsInFolder | Measure-Object -Property FileSize -Sum).Sum
        }

        $folderCreationDate = $folder.CreationDate
        if (-not $folderCreationDate) { $folderCreationDate = $folder.CreationDateTime }
        if (-not $folderCreationDate) { $folderCreationDate = $folder.CreateDateTime }

        $folderObject = [PSCustomObject]@{
            Name            = $folder.Name
            FullPath        = $folder.FullPath
            ProjectID       = $folder.ProjectID
            ParentID        = $folder.ParentID
            Depth           = if ($folder.FullPath) { ($folder.FullPath.Split('\').Count - 1) } else { 0 }
            Description     = $folder.Description
            OwnerName       = $folder.OwnerName
            EnvironmentName = $folder.Environment
            WorkflowName    = $folder.Workflow
            Storage         = $folder.Storage
            CreationDate    = $folderCreationDate
            DocumentCount   = $docCount
            TotalSizeBytes  = $totalSize
        }
        $folderDetailsList.Add($folderObject)
    }
    $folderDetails = $folderDetailsList # Converte a lista para um array para uso posterior

    if ($folderDetails.Count -gt 0) {
        Write-Log -Level Info -Message "Phase 2 complete: Processed details for $($folderDetails.Count) folders."
    }

    # ==========================================
    # 3. OUTPUT
    # ==========================================
    $endTime  = Get-Date
    $duration = $endTime - $startTime

    # Recalculate MaxDepth from the processed folders, which now have the 'Depth' property.
    $maxDepth = ($folderDetails.Depth | Measure-Object -Maximum).Maximum
    # Recalcula o tamanho total da estrutura somando o tamanho de todas as pastas.
    $totalStructureSizeBytes = ($folderDetails.TotalSizeBytes | Measure-Object -Sum).Sum
    # Calcula o número total de documentos somando a contagem de cada pasta.
    $totalDocuments = ($folderDetails.DocumentCount | Measure-Object -Sum).Sum

    # Agrega os nomes únicos de Environments, Workflows e States a partir dos detalhes das pastas.
    $uniqueEnvironmentNames = $folderDetails | Where-Object { -not [string]::IsNullOrWhiteSpace($_.EnvironmentName) } | Select-Object -ExpandProperty EnvironmentName -Unique | Sort-Object
    $uniqueWorkflowNames = $folderDetails | Where-Object { -not [string]::IsNullOrWhiteSpace($_.WorkflowName) } | Select-Object -ExpandProperty WorkflowName -Unique | Sort-Object

    # Otimização: Busca todos os workflows uma única vez e os armazena em um hashtable para acesso rápido.
    $allWorkflows = @{}
    Get-PWWorkflows | ForEach-Object { $allWorkflows[$_.Name] = $_ }

    # Coleta detalhes dos ambientes, incluindo seus atributos. Inicializa como uma lista para garantir que seja sempre um array.
    $environmentDetails = [System.Collections.Generic.List[object]]::new()
    foreach ($envName in $uniqueEnvironmentNames) {
        try {
            $columns = Get-PWEnvironmentColumns -EnvironmentName $envName -ErrorAction Stop | Select-Object Name, ColumnType, ColumnWidth, IsMandatory
            # Adiciona o detalhe à lista
            $environmentDetails.Add(@{
                Name    = $envName
                # CORREÇÃO: Garante que 'Columns' seja sempre um array.
                # O resultado de Select-Object pode ser um único objeto se houver apenas uma coluna.
                # @() força a conversão para um array. Se $columns for $null, @($null) resulta em um array vazio.
                # Isso corrige o problema de um objeto com propriedades nulas ser criado.
                Columns = @($columns)
            })
        } catch {
            Write-Log -Level Warn -Message "Could not retrieve columns for environment '$($envName)'. Error: $($_.Exception.Message)"
            # Continua para o próximo ambiente em caso de erro
        }
    }
    
    # Garante que a estrutura de dados para ambientes no JSON seja consistente.
    # Se não houver detalhes (por exemplo, por erro), usa a lista de nomes como fallback.
    $finalEnvironmentData = @{
        Count   = if ($null -ne $environmentDetails) { $environmentDetails.Count } else { 0 }
        # Garante que 'Details' seja sempre um array, mesmo que esteja vazio.
        Details = @(if ($null -ne $environmentDetails) { $environmentDetails } else { @() })
    }

    # Para cada nome de workflow único, busca seus estados definidos usando o hashtable.
    $workflowDetailsList = [System.Collections.Generic.List[object]]::new()
    foreach ($workflowName in $uniqueWorkflowNames) {
        try {
            $workflowObject = $allWorkflows[$workflowName]
            if ($null -eq $workflowObject) {
                throw "Workflow object for name '$workflowName' not found."
            }
            $states = Get-PWWorkflowStateLinks -WorkflowName $workflowObject.Name -ErrorAction Stop | Select-Object -ExpandProperty Name | Sort-Object
            $workflowDetailsList.Add(@{
                Name   = $workflowName
                States = @($states) # Garante que States seja sempre um array
            })
        } catch {
            Write-Log -Level Warn -Message "Could not retrieve states for workflow '$($workflowName)'. Error: $($_.Exception.Message)"
        }
    }
    # Garante que $workflowDetails seja sempre um array, mesmo que a lista esteja vazia.
    $workflowDetails = @($workflowDetailsList)

    $output = @{
        CollectionStart   = $startTime.ToString('o')
        CollectionEnd     = $endTime.ToString('o')
        TotalDuration_sec = [math]::Round($duration.TotalSeconds, 2)
        TotalFolders      = $uniqueFolders.Count
        MaxDepth          = if ($maxDepth) { $maxDepth } else { 0 }
        TotalStructureSizeBytes = $totalStructureSizeBytes
        TotalDocuments    = $totalDocuments
        Environments      = $finalEnvironmentData
        Workflows         = @{
            Count   = $workflowDetails.Count
            Details = @($workflowDetails)
        } # FIM DA CORREÇÃO
        Folders           = if ($folderDetails) {
            @($folderDetails | ForEach-Object { $_ | Select-Object -Property Name, FullPath, `
                @{Name = 'Environment'; Expression = { $_.EnvironmentName } }, `
                @{Name = 'Workflow'; Expression = { $_.WorkflowName } }, `
                DocumentCount, TotalSizeBytes, `
                @{Name = 'CreationDate'; Expression = { 
                    if ($_.CreationDate) { 
                        if ($_.CreationDate -is [System.DateTime]) { 
                            $_.CreationDate.ToString('o') 
                        } else { 
                            $parsedDate = $null
                            if ([System.DateTime]::TryParse($_.CreationDate, [ref]$parsedDate)) {
                                $parsedDate.ToString('o')
                            } else {
                                $_.CreationDate
                            }
                        } 
                    } else { $null } 
                } }, `
                ProjectID, ParentID, Depth, Description, OwnerName, Storage})
        } else { [System.Collections.ArrayList]@() }

    }

    try {
                if (-not (Test-Path $RunOutputPath)) {
                    [void][System.IO.Directory]::CreateDirectory($RunOutputPath)
                }
        $finalPath = Join-Path -Path $RunOutputPath -ChildPath "A.json"
        $jsonContent = $output | ConvertTo-Json -Depth 10
        $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($finalPath, $jsonContent, $Utf8NoBomEncoding)
        Write-Log -Level Info -Message "Source data collection report saved to '$finalPath'"
    }
    catch {
        Write-Log -Level Error -Message "Failed to write output: $($_.Exception.Message)"
            throw $_
    }

    Write-Log -Level Info -Message "Source data collection completed in $([math]::Round($duration.TotalSeconds,2)) seconds."
}


function Invoke-TargetConfigCollection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunOutputPath
    )

    $RunOutputPath = $RunOutputPath.Trim().Trim("'").Trim('"')
    Write-Log -Level Info -Message "Collecting target configuration..."

    try {
            if (-not (Test-Path $RunOutputPath)) {
                [void][System.IO.Directory]::CreateDirectory($RunOutputPath)
            }
        $output = @{
            CollectionDate = (Get-Date).ToString('o')
            Environments   = Get-PWEnvironments | Select-Object -ExpandProperty Name | Sort-Object
            Workflows      = Get-PWWorkflows    | Select-Object -ExpandProperty Name | Sort-Object
            States         = Get-PWStates       | Select-Object -ExpandProperty Name | Sort-Object
        }

        $finalPath = Join-Path -Path $RunOutputPath -ChildPath "B.json"
        $jsonContent = $output | ConvertTo-Json -Depth 5
        $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($finalPath, $jsonContent, $Utf8NoBomEncoding)
        Write-Log -Level Info -Message "Target config saved to '$finalPath'"
    }
    catch {
        Write-Log -Level Error -Message "Target collection failed: $($_.Exception.Message)"
            throw $_
    }
}

function Invoke-Comparison {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceJsonPath,

        [Parameter(Mandatory = $true)]
        [string]$RunOutputPath
    )

    $RunOutputPath = $RunOutputPath.Trim().Trim("'").Trim('"')
    $startTime = Get-Date
    Write-Log -Level Info -Message "Starting comparison analysis at $startTime"

    if (-not (Test-Path $SourceJsonPath)) {
        Write-Log -Level Error -Message "Source data file not found at '$SourceJsonPath'. Aborting."
        return
    }

    $sourceData = Get-Content $SourceJsonPath | ConvertFrom-Json

    # --- 1. Comparação de Ambientes e Atributos ---
    Write-Log -Level Info -Message "Comparing Environments and their attributes..."
    # CORREÇÃO: O cmdlet Get-PWEnvironments pode retornar objetos com a propriedade 'Name' ou 'EnvironmentName'.
    # Esta lógica verifica qual propriedade existe e a utiliza, garantindo compatibilidade.    
    $targetEnvironments = Get-PWEnvironments | ForEach-Object {
        if ($_.PSObject.Properties['Name']) { $_.Name }
        elseif ($_.PSObject.Properties['EnvironmentName']) { $_.EnvironmentName }
    }

    $environmentComparison = foreach ($sourceEnv in $sourceData.Environments.Details) {
        $envResult = @{ Name = $sourceEnv.Name; Status = 'Not Found'; Columns = @() }
        if ($sourceEnv.Name -in $targetEnvironments) {
            $envResult.Status = 'Found'
            
            # CORREÇÃO: Verifica se a propriedade 'Columns' existe e é um array antes de tentar a comparação.
            if ($sourceEnv.PSObject.Properties['Columns'] -and $sourceEnv.Columns -is [array] -and $sourceEnv.Columns.Count -gt 0) {
                $targetColumns = Get-PWEnvironmentColumns -EnvironmentName $sourceEnv.Name | Select-Object Name, ColumnType, ColumnWidth
                $targetColumnsHash = $targetColumns | Group-Object -Property Name -AsHashTable -AsString

                $columnComparison = foreach ($sourceColumn in $sourceEnv.Columns) {
                    $colResult = @{ Name = $sourceColumn.Name; Status = 'Not Found' }
                    if ($targetColumnsHash.ContainsKey($sourceColumn.Name)) {
                        $targetCol = $targetColumnsHash[$sourceColumn.Name].Group[0]
                        if (($sourceColumn.ColumnType -eq $targetCol.ColumnType) -and ($sourceColumn.ColumnWidth -eq $targetCol.ColumnWidth)) {
                            $colResult.Status = 'Match'
                        } else {
                            $colResult.Status = 'Mismatch'
                            $colResult.SourceProps = "Type: $($sourceColumn.ColumnType), Width: $($sourceColumn.ColumnWidth)"
                            $colResult.TargetProps = "Type: $($targetCol.ColumnType), Width: $($targetCol.ColumnWidth)"
                        }
                    }
                    $colResult
                }
                $envResult.Columns = $columnComparison
            }
        }
        $envResult
    }

    # --- 2. Comparação de Workflows e Estados ---
    Write-Log -Level Info -Message "Comparing Workflows and their states..."
    $targetWorkflows = Get-PWWorkflows | Select-Object -ExpandProperty Name
    $workflowComparison = foreach ($sourceWf in $sourceData.Workflows.Details) {
        $wfResult = @{ Name = $sourceWf.Name; Status = 'Not Found'; States = @() }
        if ($sourceWf.Name -in $targetWorkflows) {
            $wfResult.Status = 'Found'
            $targetStates = Get-PWWorkflowStateLinks -WorkflowName $sourceWf.Name | Select-Object -ExpandProperty Name

            $stateComparison = foreach ($sourceState in $sourceWf.States) {
                $stateResult = @{ Name = $sourceState; Status = 'Not Found' }
                if ($sourceState -in $targetStates) {
                    $stateResult.Status = 'Found'
                }
                $stateResult
            }
            $wfResult.States = $stateComparison
        }
        $wfResult
    }

    # --- 3. Verificação da Estrutura de Pastas ---
    Write-Log -Level Info -Message "Comparing Folder structure..."

    # Identify the top-level (root) folder paths from the source data
    $sourceProjectIDs = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($f in $sourceData.Folders) {
        [void]$sourceProjectIDs.Add($f.ProjectID)
    }
    
    $targetRootPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $sourceData.Folders) {
        if (-not $sourceProjectIDs.Contains($f.ParentID)) {
            $targetRootPaths.Add($f.FullPath)
        }
    }

    Write-Log -Level Info -Message "Bulk-loading target folder structure to optimize comparison..."
    $targetFolderPathsSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    
    foreach ($rootPath in $targetRootPaths) {
        try {
            $sanitizedRootPath = $rootPath.TrimEnd('\')
            Write-Log -Level Info -Message "Pre-fetching target folders recursively under '$sanitizedRootPath'..."
            $targetSubtreeFolders = Get-PWFolders -FolderPath $sanitizedRootPath -PopulatePaths -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            if ($null -eq $targetSubtreeFolders) {
                # Fallback to -FolderName
                $targetSubtreeFolders = Get-PWFolders -FolderName $sanitizedRootPath -PopulatePaths -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            }
            
            if ($targetSubtreeFolders) {
                foreach ($f in $targetSubtreeFolders) {
                    [void]$targetFolderPathsSet.Add($f.FullPath)
                }
            }
        }
        catch {
            Write-Log -Level Warn -Message "Failed to pre-fetch target folders under '$rootPath': $($_.Exception.Message)"
        }
    }

    $folderComparison = foreach ($sourceFolder in $sourceData.Folders) {
        $folderResult = @{
            Path      = $sourceFolder.FullPath
            Status    = 'Not Found'
            ProjectID = $sourceFolder.ProjectID
            ParentID  = $sourceFolder.ParentID
            Depth     = $sourceFolder.Depth
        }
        
        # In-memory lookup: extremely fast (microseconds) instead of a network call!
        if ($targetFolderPathsSet.Contains($sourceFolder.FullPath)) {
            $folderResult.Status = 'Found'
        }
        $folderResult
    }

    # --- 4. Geração do Relatório Final ---
    $endTime = Get-Date
    $duration = $endTime - $startTime

    $output = @{
        ComparisonStart   = $startTime.ToString('o')
        ComparisonEnd     = $endTime.ToString('o')
        ComparisonDuration_sec = [math]::Round($duration.TotalSeconds, 2)
        SourceInfo = @{
            TotalFolders = $sourceData.TotalFolders
            TotalDocuments = $sourceData.TotalDocuments
            TotalSize = $sourceData.TotalStructureSizeBytes
            Environments = $sourceData.Environments
            Workflows = $sourceData.Workflows
        }
        ComparisonResults = @{
            Environments = $environmentComparison
            Workflows    = $workflowComparison
            Folders      = $folderComparison
        }
    }

    try {
        if (-not (Test-Path $RunOutputPath)) {
            [void][System.IO.Directory]::CreateDirectory($RunOutputPath)
        }
        $finalPath = Join-Path -Path $RunOutputPath -ChildPath "C.json"
        $jsonContent = $output | ConvertTo-Json -Depth 10
        $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($finalPath, $jsonContent, $Utf8NoBomEncoding)
        Write-Log -Level Info -Message "Comparison report saved to '$finalPath'"
    }
    catch {
        Write-Log -Level Error -Message "Failed to write comparison report: $($_.Exception.Message)"
    }

    Write-Log -Level Info -Message "Comparison analysis completed in $([math]::Round($duration.TotalSeconds,2)) seconds."
}