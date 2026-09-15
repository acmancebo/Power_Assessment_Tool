function formatBytes(bytes, decimals = 2) {
    if (!bytes || bytes === 0) return '0 Bytes';

    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];

    const i = Math.floor(Math.log(bytes) / Math.log(k));

    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
}

$(document).ready(function() {
    const urlParams = new URLSearchParams(window.location.search);
    const runId = urlParams.get('runId');

    if (!runId) {
        // If no runId is present, the page was accessed incorrectly. Redirect to the main portal with an error message.
        window.location.href = '/?error=no_run_id';
    }

    const dataUrl = `/output/${runId}/A.json`;

    // Adiciona os links de navegação imediatamente ao carregar a página.
    const navDiv = $('#nav-links');
    navDiv.html(`
        <a href="/">Portal</a> | 
        <a href="dashboard.html?runId=${runId}"><strong>Collection Dashboard</strong></a> | 
        <a href="comparison.html?runId=${runId}">Comparison Report</a>
    `);

    fetch(dataUrl, { cache: 'no-cache' })
        .then(response => {
            if (!response.ok) {
                throw new Error(`Network error: ${response.statusText} (Was A.json generated?)`);
            }
            return response.json();
        })
        .then(data => {
            // Defensivamente, verifica se os dados são válidos. Se não, exibe um erro e para.
            if (!data || typeof data !== 'object' || Object.keys(data).length === 0) {
                $('#summary').html(`<p class="error">Failed to load data. The A.json file is empty or invalid. Please run the collection script.</p>`);
                // Esconde outros elementos que dependem dos dados
                $('#config-summary-panel').hide();
                $('.table-container').hide();
                return; // Para a execução
            }

            // Usa o operador de coalescência nula (??) para acessar os dados de forma segura
            const maxDepth = data.MaxDepth ?? 0;
            const totalFolders = data.TotalFolders ?? 0;
            const totalDocuments = data.TotalDocuments ?? 0;
            const totalSize = data.TotalStructureSizeBytes ?? 0;
            const duration = data.TotalDuration_sec ?? 0;
            const collectionStart = data.CollectionStart ? new Date(data.CollectionStart) : null;
            const environments = data.Environments ?? { Count: 0, Details: [] };
            const workflows = data.Workflows ?? { Count: 0, Details: [] };
            const folders = data.Folders ?? [];

            // Preenche o painel de resumo
            const summaryDiv = $('#summary');
            summaryDiv.html(`
                <p><strong>Max Depth:</strong> ${maxDepth}</p>
                <p><strong>Total Folders:</strong> ${totalFolders.toLocaleString('en-US')}</p>
                <p><strong>Total Size:</strong> ${formatBytes(totalSize)}</p>
                <p><strong>Collection Duration:</strong> ${duration} seconds</p>
                <p><strong>Collection Date:</strong> ${collectionStart ? collectionStart.toLocaleString('en-US') : '<em>N/A</em>'}</p>
            `);

            // Preenche o painel de resumo de configuração
            const configSummaryDiv = $('#config-summary-panel');
            let configHtml = '';

            const createEnvironmentsCard = (title, count, details) => {
                let listItems = (details ?? []).map(env => {
                    const attributesList = (env.Columns ?? []).filter(c => c.Name).map(col => `<li class="state-item">${col.Name}</li>`).join('');
                    return `<li><span class="workflow-name">${env.Name || 'Unnamed'}</span><ul class="states-list">${attributesList}</ul></li>`;
                }).join('');
                if (!listItems) listItems = '<li>None found</li>';
                return `
                    <div class="config-card">
                        <div class="config-card-header"><h3>${title} (${count ?? 0})</h3></div>
                        <div class="config-card-body"><ul>${listItems}</ul></div>
                    </div>
                `;
            };

            const createWorkflowsCard = (title, count, details) => {
                let listItems = (details ?? []).map(wf => {
                    const statesList = (wf.States ?? []).map(state => `<li class="state-item">${state}</li>`).join('');
                    return `<li><span class="workflow-name">${wf.Name || 'Unnamed'}</span><ul class="states-list">${statesList}</ul></li>`;
                }).join('');
                if (!listItems) listItems = '<li>None found</li>';
                return `
                    <div class="config-card">
                        <div class="config-card-header"><h3>${title} (${count ?? 0})</h3></div>
                        <div class="config-card-body"><ul>${listItems}</ul></div>
                    </div>
                `;
            };

            configHtml += createEnvironmentsCard('Environments', environments.Count, environments.Details);
            configHtml += createWorkflowsCard('Workflows & States', workflows.Count, workflows.Details);
            configSummaryDiv.html(configHtml);

            // Inicializa a tabela interativa (DataTable)
            $('#foldersTable').DataTable({
                dom: 'Bfrtip', // Adiciona os botões (B) ao DOM da tabela
                buttons: [
                    'copy',                    
                    {
                        extend: 'pdf',
                        title: () => `Data Collection Report - ${collectionStart ? collectionStart.toLocaleString('en-US') : 'N/A'}`,
                        messageTop: () => `Max Depth: ${data.MaxDepth ?? 0} | Total Folders: ${(data.TotalFolders ?? 0).toLocaleString('pt-BR')} | Total Size: ${formatBytes(data.TotalStructureSizeBytes ?? 0)} | Duration: ${data.TotalDuration_sec ?? 0}s`,
                        orientation: 'landscape',
                        pageSize: 'A4',
                        customize: function (doc) {
                            // Get fresh data for export, not from the outer scope which might be stale.
                            const collectionDate = data.CollectionStart ? new Date(data.CollectionStart).toLocaleString('en-US') : 'N/A';

                            // 1. Extract the original table created by DataTables
                            const originalTable = doc.content[1];
                            originalTable.table.widths = ['15%', '45%', '10%', '10%', '5%', '8%', '7%'];
                            originalTable.layout = 'lightHorizontalLines';
                            originalTable.style = 'tableStyle';

                            // 2. Create Cover Page content
                            const coverPage = [
                                { text: 'Data Collection Report', style: 'header', alignment: 'center', margin: [0, 180, 0, 20] },
                                { text: `Generated on: ${collectionDate}`, style: 'subheader', alignment: 'center', margin: [0, 0, 0, 50] },
                                {
                                    style: 'summaryTable',
                                    table: {
                                        widths: ['*', '*'],
                                        body: [
                                            [{ text: 'Summary Metric', style: 'summaryTableHeader' }, { text: 'Value', style: 'summaryTableHeader' }],
                                            [{ text: 'Max Depth', style: 'summaryTableBody' }, { text: data.MaxDepth ?? 0, style: 'summaryTableBody' }],
                                            [{ text: 'Total Folders', style: 'summaryTableBody' }, { text: (data.TotalFolders ?? 0).toLocaleString('en-US'), style: 'summaryTableBody' }],
                                            [{ text: 'Total Documents', style: 'summaryTableBody' }, { text: (data.TotalDocuments ?? 0).toLocaleString('en-US'), style: 'summaryTableBody' }],
                                            [{ text: 'Total Size', style: 'summaryTableBody' }, { text: formatBytes(data.TotalStructureSizeBytes ?? 0), style: 'summaryTableBody' }],
                                            [{ text: 'Collection Duration', style: 'summaryTableBody' }, { text: `${data.TotalDuration_sec ?? 0} seconds`, style: 'summaryTableBody' }],
                                        ]
                                    },
                                    layout: 'lightHorizontalLines'
                                }
                            ];

                            // 3. Create Environments content
                            const envContent = [];
                            if (data.Environments?.Details?.length > 0) {
                                envContent.push({ text: 'Environments Details', style: 'sectionHeader', pageBreak: 'before' });
                                data.Environments.Details.forEach(env => {
                                    envContent.push({ text: env.Name || 'Unnamed Environment', style: 'subheader', margin: [0, 10, 0, 5] });
                                    if (env.Columns && env.Columns.length > 0) {
                                        const body = [[{ text: 'Attribute', style: 'tableHeader' }, { text: 'Type', style: 'tableHeader' }, { text: 'Mandatory', style: 'tableHeader' }]];
                                        env.Columns.forEach(col => body.push([col.Name || 'Unnamed Attribute', col.ColumnType || 'N/A', col.IsMandatory ? 'Yes' : 'No']));
                                        envContent.push({
                                            style: 'tableStyle',
                                            table: { widths: ['*', 'auto', 'auto'], body: body },
                                            layout: 'lightHorizontalLines'
                                        });
                                    } else {
                                        envContent.push({ text: 'No attributes defined.', italics: true, margin: [0, 0, 0, 10] });
                                    }
                                });
                            }

                            // 4. Create Workflows content
                            const wfContent = [];
                            if (data.Workflows?.Details?.length > 0) {
                                wfContent.push({ text: 'Workflows & States', style: 'sectionHeader', pageBreak: 'before' });
                                data.Workflows.Details.forEach(wf => {
                                    wfContent.push({ text: wf.Name || 'Unnamed Workflow', style: 'subheader', margin: [0, 10, 0, 5] });
                                    if (wf.States && wf.States.length > 0) {
                                        wfContent.push({ ul: wf.States.map(s => ({ text: s || 'Unnamed State' })) });
                                    } else {
                                        wfContent.push({ text: 'No states defined.', italics: true, margin: [0, 0, 0, 10] });
                                    }
                                });
                            }

                            // 5. Rebuild the entire doc.content
                            doc.content = [
                                ...coverPage,
                                { text: 'Folders Details', style: 'sectionHeader', pageBreak: 'before', pageOrientation: 'landscape' },
                                originalTable,
                                ...envContent,
                                ...wfContent
                            ];

                            // 6. Define all styles
                            Object.assign(doc.styles, {
                                header: { fontSize: 20, bold: true },
                                subheader: { fontSize: 12, bold: true },
                                sectionHeader: { fontSize: 14, bold: true, margin: [0, 15, 0, 10] },
                                summaryTable: { margin: [0, 20, 0, 20] },
                                summaryTableHeader: { bold: true, fontSize: 10, color: 'black' },
                                summaryTableBody: { fontSize: 9 },
                                tableHeader: { bold: true, fontSize: 8, color: 'black' },
                                tableStyle: { margin: [0, 5, 0, 15] }
                            });
                            doc.defaultStyle.fontSize = 7;
                            doc.pageMargins = [20, 20, 20, 20];
                        }
                    },
                    'print',
                    {
                        text: 'Export All (XLSX)',
                        action: function (e, dt, node, config) {
                            // Helper to calculate and set column widths
                            const getColumnWidths = (sheetData) => {
                                if (!sheetData || sheetData.length === 0) return [];
                                const headers = Object.keys(sheetData[0]);
                                return headers.map(header => {
                                    const headerWidth = header.length;
                                    const maxWidth = Math.max(headerWidth, ...sheetData.map(row => (row[header] || '').toString().length));
                                    // Cap width at 70 chars for very long fields like paths
                                    return { wch: Math.min(maxWidth + 2, 70) };
                                });
                            };

                            // Helper to style the header row of a sheet
                            const styleHeader = (sheet) => {
                                if (!sheet || !sheet['!ref']) return;
                                const range = XLSX.utils.decode_range(sheet['!ref']);
                                for (let C = range.s.c; C <= range.e.c; ++C) {
                                    const address = XLSX.utils.encode_cell({ r: 0, c: C }); // First row
                                    if (!sheet[address]) continue;
                                    sheet[address].s = {
                                        font: { bold: true, color: { rgb: "FFFFFF" } },
                                        fill: {
                                            patternType: "solid",
                                            fgColor: { rgb: "00529B" } // A nice blue from the theme
                                        }
                                    };
                                }
                            };

                            // 1. Prepara a aba de Resumo
                            const summaryData = [
                                { Key: 'Creation Date', Value: data.CollectionStart ? new Date(data.CollectionStart) : 'N/A' },
                                { Key: 'Collection Duration', Value: `${data.TotalDuration_sec ?? 0} seconds` },
                                { Key: '--- Collection Stats ---', Value: '' },
                                { Key: 'Max Depth', Value: data.MaxDepth ?? 0 },
                                { Key: 'Total Folders', Value: (data.TotalFolders ?? 0).toLocaleString('en-US') },
                                { Key: 'Total Documents', Value: (data.TotalDocuments ?? 0).toLocaleString('en-US') },
                                { Key: 'Total Size', Value: formatBytes(data.TotalStructureSizeBytes ?? 0) },
                                { Key: 'Total Environments', Value: data.Environments?.Count ?? 0 },
                                { Key: 'Total Workflows', Value: data.Workflows?.Count ?? 0 }
                            ];
                            const summarySheet = XLSX.utils.json_to_sheet(summaryData, { skipHeader: true });
                            summarySheet['!cols'] = [{ wch: 30 }, { wch: 25 }];

                            // 2. Prepara a aba de Pastas
                            const folderExportData = (data.Folders ?? []).map(f => {
                                const folderCopy = { ...f };
                                // Check for null/undefined and the specific default date string
                                if (folderCopy.CreationDate && !folderCopy.CreationDate.startsWith('0001-01-01')) {
                                    // Convert valid ISO string to a JS Date object for better Excel formatting
                                    folderCopy.CreationDate = new Date(folderCopy.CreationDate);
                                } else {
                                    folderCopy.CreationDate = 'N/A';
                                }
                                return folderCopy;
                            });
                            const foldersSheet = XLSX.utils.json_to_sheet(folderExportData);
                            foldersSheet['!cols'] = getColumnWidths(folderExportData);
                            styleHeader(foldersSheet);

                            // 3. Prepara a aba de Ambientes (desagrupando os atributos)
                            const envs = (data.Environments?.Details ?? []).flatMap(env => 
                                (env.Columns ?? []).length > 0
                                    ? env.Columns.map(col => ({
                                        Environment: env.Name,
                                        Attribute: col.Name,
                                        Type: col.ColumnType,
                                        Width: col.ColumnWidth,
                                        Mandatory: col.IsMandatory ? 'Yes' : 'No'
                                    }))
                                    : [{ Environment: env.Name, Attribute: 'N/A', Type: '', Width: '', Mandatory: '' }]
                            );
                            const envsSheet = XLSX.utils.json_to_sheet(envs);
                            envsSheet['!cols'] = getColumnWidths(envs);
                            styleHeader(envsSheet);

                            // 4. Prepara a aba de Workflows (desagrupando os estados)
                            const wfs = (data.Workflows?.Details ?? []).flatMap(wf => 
                                (wf.States ?? []).length > 0
                                    ? wf.States.map(state => ({ Workflow: wf.Name, State: state }))
                                    : [{ Workflow: wf.Name, State: 'N/A' }]
                            );
                            const wfsSheet = XLSX.utils.json_to_sheet(wfs);
                            wfsSheet['!cols'] = getColumnWidths(wfs);
                            styleHeader(wfsSheet);

                            // 5. Cria o workbook com as 4 abas e dispara o download
                            const wb = XLSX.utils.book_new();
                            XLSX.utils.book_append_sheet(wb, summarySheet, 'Summary');
                            XLSX.utils.book_append_sheet(wb, foldersSheet, 'Folders');
                            XLSX.utils.book_append_sheet(wb, envsSheet, 'Environments');
                            XLSX.utils.book_append_sheet(wb, wfsSheet, 'Workflows');

                            const collectionDateISO = data.CollectionStart ? new Date(data.CollectionStart).toISOString().split('T')[0] : 'report';
                            XLSX.writeFile(wb, `Powe_Collection_Report_${collectionDateISO}.xlsx`);
                        }
                    }
                ],
                order: [], // Desabilita a ordenação inicial para manter a ordem do JSON
                pageLength: 25, // Define a paginação padrão para 25 itens
                data: folders,
                columns: [
                    { data: 'Name' },
                    { data: 'FullPath' },
                    { data: 'Environment', defaultContent: '<em>N/A</em>' },
                    { data: 'Workflow', defaultContent: '<em>N/A</em>' },                    
                    { data: 'DocumentCount', className: 'dt-body-right', render: $.fn.dataTable.render.number('.', ',', 0, '') }, // Alinha e formata número
                    { 
                        data: 'TotalSizeBytes', 
                        className: 'dt-body-right',
                        render: function(data, type, row) {
                            return formatBytes(data);
                        }
                    },                   
                    { 
                        data: 'CreationDate',
                        render: function(data, type, row) {
                            // Check for null/undefined and the specific default date string from .NET
                            if (!data || data.startsWith('0001-01-01')) {
                                return '<em>N/A</em>';
                            }
                            return new Date(data).toLocaleString('en-US');
                        }
                    }
                ],
                // By removing the language object, DataTables will default to English.
            });
        })
        .catch(error => {
            console.error('Erro ao carregar ou processar os dados:', error);
            $('#summary').html(`<p class="error">Failed to load data. Check if the collection was executed and if A.json exists. Details: ${error.message}</p>`);
        });
});