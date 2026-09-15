$(document).ready(function() {
    const urlParams = new URLSearchParams(window.location.search);
    const runId = urlParams.get('runId');

    if (!runId) {
        // If no runId is present, the page was accessed incorrectly. Redirect to the main portal with an error message.
        window.location.href = '/?error=no_run_id';
    }

    const dataUrl = `/output/${runId}/C.json`;

    fetch(dataUrl, { cache: 'no-cache' })
        .then(response => {
            if (!response.ok) {
                throw new Error(`Network error: ${response.statusText} (Was C.json generated?)`);
            }
            return response.json();
        })
        .then(data => {
            // Defensivamente, verifica se os dados são válidos. Se não, exibe um erro e para.
            if (!data || typeof data !== 'object' || !data.ComparisonResults) {
                $('#summary').html(`<p class="error">Failed to load comparison data. The C.json file is empty or invalid. Please run the comparison script.</p>`);
                // Esconde outros elementos que dependem dos dados
                $('#environments-body').closest('.card').hide();
                $('#workflows-body').closest('.card').hide();
                $('#folders-table-container').hide();
                return; // Para a execução
            }

            // Adiciona links de navegação
            const navDiv = $('#nav-links');
            navDiv.html(`
                <a href="/">Portal</a> | 
                <a href="dashboard.html?runId=${runId}">Collection Dashboard</a> | 
                <a href="comparison.html?runId=${runId}"><strong>Comparison Report</strong></a>
            `);

            // Preenche o painel de resumo
            const summaryDiv = $('#summary');
            summaryDiv.html(`
                <p><strong>Folders in Source:</strong> ${data.SourceInfo.TotalFolders.toLocaleString('en-US')}</p>
                <p><strong>Environments in Source:</strong> ${data.SourceInfo.Environments.Count}</p>
                <p><strong>Documents in Source:</strong> ${data.SourceInfo.TotalDocuments.toLocaleString('en-US')}</p>
                <p><strong>Total Size in Source:</strong> ${formatBytes(data.SourceInfo.TotalSize)}</p>
                <p><strong>Workflows in Source:</strong> ${data.SourceInfo.Workflows.Count}</p>
                <p><strong>Comparison Duration:</strong> ${data.ComparisonDuration_sec} seconds</p>
                <p><strong>Comparison Date:</strong> ${new Date(data.ComparisonStart).toLocaleString('en-US')}</p>
            `);

            // Renderiza a comparação de Ambientes
            const envBody = $('#environments-body');
            let envHtml = '<h4>Source</h4><ul class="comparison-list">';
            if (data.SourceInfo.Environments?.Details?.length > 0) {
                data.SourceInfo.Environments.Details.forEach(env => {
                    envHtml += `<li><span class="workflow-name">${env.Name || 'Unnamed Env'}</span>`;
                    const attributesList = (env.Columns || []).filter(c => c.Name).map(col => `<li class="state-item">${col.Name}</li>`).join('');
                    if (attributesList) {
                        envHtml += `<ul class="states-list">${attributesList}</ul>`;
                    }
                    envHtml += '</li>';
                });
            } else {
                envHtml += '<li>No environments found in source.</li>';
            }
            envHtml += '</ul><h4>Target</h4><ul class="comparison-list">';

            if (data.ComparisonResults.Environments?.length > 0) {
                data.ComparisonResults.Environments.forEach(env => {
                    const envStatusClass = env.Status === 'Found' ? 'status-found' : 'status-not-found';
                    envHtml += `<li><span class="${envStatusClass}">[${env.Status}]</span> <span class="workflow-name">${env.Name || 'Unnamed Env'}</span>`;

                    const attributesList = (env.Columns || []).map(col => {
                        const attrStatusClass = col.Status === 'Match' ? 'status-found' : 'status-not-found';
                        return `<li class="state-item"><span class="${attrStatusClass}">[${col.Status}]</span> ${col.Name}</li>`;
                    }).join('');
                    
                    if (attributesList) {
                        envHtml += `<ul class="states-list">${attributesList}</ul>`;
                    }
                    envHtml += '</li>';
                });
            } else {
                envHtml += '<li>Comparison data not available.</li>';
            }
            envHtml += '</ul>'
            envBody.html(envHtml);

            // Renderiza a comparação de Workflows
            const wfBody = $('#workflows-body');
            let wfHtml = '<h4>Source</h4><ul class="comparison-list">';
            if (data.SourceInfo.Workflows?.Details?.length > 0) {
                data.SourceInfo.Workflows.Details.forEach(wf => {
                    wfHtml += `<li><span class="workflow-name">${wf.Name}</span>`;
                    const statesList = (wf.States || []).map(state => `<li class="state-item">${state}</li>`).join('');
                    wfHtml += `<ul class="states-list">${statesList}</ul></li>`;
                });
            } else {
                wfHtml += '<li>No workflows found in source.</li>';
            }
            wfHtml += '</ul><h4>Target</h4><ul class="comparison-list">';

            if (data.ComparisonResults.Workflows?.length > 0) {
                 data.ComparisonResults.Workflows.forEach(wf => {
                    const wfStatusClass = wf.Status === 'Found' ? 'status-found' : 'status-not-found';
                    wfHtml += `<li><span class="${wfStatusClass}">[${wf.Status}]</span> <span class="workflow-name">${wf.Name}</span>`;

                    const statesList = (wf.States || []).map(state => {
                        const stateStatusClass = state.Status === 'Found' ? 'status-found' : 'status-not-found';
                        return `<li class="state-item"><span class="${stateStatusClass}">[${state.Status}]</span> ${state.Name}</li>`;
                    }).join('');
                    wfHtml += `<ul class="states-list">${statesList}</ul></li>`;
                });
            } else {
                wfHtml += '<li>Comparison data not available.</li>';
            }
            wfHtml += '</ul>';
            wfBody.html(wfHtml);

            // Renderiza a tabela de Pastas
            const foldersContainer = $('#folders-table-container');
            let foldersTableHtml = `<table id="foldersTable" class="display" style="width:100%">
                                        <thead>
                                            <tr>
                                                <th></th>
                                                <th>Folder Path</th>
                                                <th>Status in Target</th>
                                            </tr>
                                        </thead>
                                    </table>`;
            foldersContainer.html(foldersTableHtml);

            // --- Lógica da Árvore de Pastas ---
            const allFolders = data.ComparisonResults.Folders;
            const folderMap = new Map(allFolders.map(f => [f.ProjectID, f]));
            const childMap = new Map();
            allFolders.forEach(f => {
                if (!childMap.has(f.ParentID)) childMap.set(f.ParentID, []);
                childMap.get(f.ParentID).push(f);
            });

            // Add hasChildren property to all folders for the expander icon
            allFolders.forEach(f => {
                f.hasChildren = childMap.has(f.ProjectID) && childMap.get(f.ProjectID).length > 0;
            });

            // Encontra as pastas raiz (aquelas cujo ParentID não está na lista de ProjectIDs)
            const rootFolders = allFolders.filter(f => !folderMap.has(f.ParentID));

            // Inicializa a DataTable para a tabela de pastas
            const table = $('#foldersTable').DataTable({
                dom: 'Bfrtip', // Adiciona os botões (B) ao DOM da tabela
                buttons: [
                    {
                        extend: 'copy',
                        exportOptions: {
                            columns: [1, 2] // Exporta apenas 'Folder Path' e 'Status'
                        }
                    },
                    {
                        extend: 'excel',
                        title: () => `Folder Structure Comparison Report - ${new Date(data.ComparisonStart).toLocaleString('pt-BR')}`,
                        messageTop: () => `Source Folders: ${data.SourceInfo.TotalFolders.toLocaleString('pt-BR')} | Source Docs: ${data.SourceInfo.TotalDocuments.toLocaleString('pt-BR')} | Source Size: ${formatBytes(data.SourceInfo.TotalSize)} | Duration: ${data.ComparisonDuration_sec}s`,
                        exportOptions: {
                            columns: [1, 2] // Exporta apenas 'Folder Path' e 'Status'
                        }
                    },
                    {
                        extend: 'pdf',
                        title: () => `Folder Structure Comparison Report - ${new Date(data.ComparisonStart).toLocaleString('pt-BR')}`,
                        messageTop: () => `Source Folders: ${data.SourceInfo.TotalFolders.toLocaleString('pt-BR')} | Source Docs: ${data.SourceInfo.TotalDocuments.toLocaleString('pt-BR')} | Source Size: ${formatBytes(data.SourceInfo.TotalSize)} | Duration: ${data.ComparisonDuration_sec}s`,
                        exportOptions: {
                            columns: [1, 2] // Exporta apenas 'Folder Path' e 'Status'
                        },
                        customize: function (doc) {
                            // Get fresh data for export
                            const comparisonDate = new Date(data.ComparisonStart).toLocaleString('en-US');

                            // 1. Extract and style original table
                            const originalTable = doc.content[1];
                            originalTable.table.widths = ['75%', '25%'];
                            originalTable.layout = 'lightHorizontalLines';
                            originalTable.style = 'tableStyle';

                            // 2. Create Cover Page content
                            const coverPage = [
                                { text: 'Datasource Comparison Report', style: 'header', alignment: 'center', margin: [0, 200, 0, 20] },
                                { text: `Generated on: ${comparisonDate}`, style: 'subheader', alignment: 'center', margin: [0, 0, 0, 50] },
                                {
                                    style: 'summaryTable',
                                    table: {
                                        widths: ['*', '*'],
                                        body: [
                                            [{ text: 'Summary Metric', style: 'summaryTableHeader' }, { text: 'Value', style: 'summaryTableBody' }],
                                            [{ text: 'Folders in Source', style: 'summaryTableBody' }, { text: (data.SourceInfo?.TotalFolders ?? 0).toLocaleString('en-US'), style: 'summaryTableBody' }],
                                            [{ text: 'Documents in Source', style: 'summaryTableBody' }, { text: (data.SourceInfo?.TotalDocuments ?? 0).toLocaleString('en-US'), style: 'summaryTableBody' }],
                                            [{ text: 'Total Size in Source', style: 'summaryTableBody' }, { text: formatBytes(data.SourceInfo?.TotalSize ?? 0), style: 'summaryTableBody' }],
                                            [{ text: 'Comparison Duration', style: 'summaryTableBody' }, { text: `${data.ComparisonDuration_sec ?? 0} seconds`, style: 'summaryTableBody' }],
                                            [{ text: 'Folders Not Found in Target', style: 'summaryTableBody' }, { text: (data.ComparisonResults?.Folders ?? []).filter(f => f.Status !== 'Found').length, style: 'summaryTableBody' }],
                                        ]
                                    },
                                    layout: 'lightHorizontalLines'
                                }
                            ];

                            // 3. Create Environments Content
                            const envContent = [];
                            if (data.ComparisonResults?.Environments?.length > 0) {
                                envContent.push({ text: 'Environments Comparison', style: 'sectionHeader', pageBreak: 'before' });
                                data.ComparisonResults.Environments.forEach(env => {
                                    envContent.push({ text: `${env.Name || 'Unnamed Env'} (Status: ${env.Status || 'N/A'})`, style: 'subheader', margin: [0, 10, 0, 5] });
                                    if (env.Columns && env.Columns.length > 0) {
                                        const body = [[{ text: 'Attribute', style: 'tableHeader' }, { text: 'Status', style: 'tableHeader' }]];
                                        env.Columns.forEach(col => body.push([col.Name || 'Unnamed Attribute', col.Status || 'N/A']));
                                        envContent.push({ style: 'tableStyle', table: { widths: ['*', 'auto'], body: body }, layout: 'lightHorizontalLines' });
                                    }
                                });
                            }

                            // 4. Create Workflows Content
                            const wfContent = [];
                            if (data.ComparisonResults?.Workflows?.length > 0) {
                                wfContent.push({ text: 'Workflows & States Comparison', style: 'sectionHeader', pageBreak: 'before' });
                                data.ComparisonResults.Workflows.forEach(wf => {
                                    wfContent.push({ text: `${wf.Name || 'Unnamed WF'} (Status: ${wf.Status || 'N/A'})`, style: 'subheader', margin: [0, 10, 0, 5] });
                                    if (wf.States && wf.States.length > 0) {
                                        const body = [[{ text: 'State', style: 'tableHeader' }, { text: 'Status', style: 'tableHeader' }]];
                                        wf.States.forEach(state => body.push([state.Name || 'Unnamed State', state.Status || 'N/A']));
                                        wfContent.push({ style: 'tableStyle', table: { widths: ['*', 'auto'], body: body }, layout: 'lightHorizontalLines' });
                                    }
                                });
                            }

                            // 5. Rebuild the entire doc.content
                            doc.content = [
                                ...coverPage,
                                { text: 'Folder Structure Check', style: 'sectionHeader', pageBreak: 'before', pageOrientation: 'landscape' },
                                originalTable,
                                ...envContent,
                                ...wfContent
                            ];

                            // 6. Define all styles
                            doc.styles.header = { fontSize: 20, bold: true };
                            doc.styles.subheader = { fontSize: 12, bold: true };
                            doc.styles.sectionHeader = { fontSize: 14, bold: true, margin: [0, 15, 0, 10] };
                            doc.styles.summaryTable = { margin: [0, 20, 0, 20] };
                            doc.styles.summaryTableHeader = { bold: true, fontSize: 10, color: 'black' };
                            doc.styles.summaryTableBody = { fontSize: 9 };
                            doc.styles.tableStyle = { margin: [0, 5, 0, 15] };
                            doc.defaultStyle.fontSize = 8;
                            doc.styles.tableHeader = { bold: true, fontSize: 9, color: 'black' };
                            doc.pageMargins = [20, 20, 20, 20];
                        }
                    },
                    {
                        extend: 'print',
                        title: () => `Folder Structure Comparison Report - ${new Date(data.ComparisonStart).toLocaleString('pt-BR')}`,
                        messageTop: () => `Source Folders: ${data.SourceInfo.TotalFolders.toLocaleString('pt-BR')} | Source Docs: ${data.SourceInfo.TotalDocuments.toLocaleString('pt-BR')} | Source Size: ${formatBytes(data.SourceInfo.TotalSize)} | Duration: ${data.ComparisonDuration_sec}s`,
                        exportOptions: {
                            columns: [1, 2] // Exporta apenas 'Folder Path' e 'Status'
                        }
                    },
                    {
                        text: 'Export Full (XLSX)',
                        action: function (e, dt, node, config) {
                            // Helper to calculate and set column widths
                            const getColumnWidths = (data) => {
                                if (!data || data.length === 0) return [];
                                const headers = Object.keys(data[0]);
                                return headers.map(header => {
                                    const headerWidth = header.length;
                                    const maxWidth = Math.max(headerWidth, ...data.map(row => (row[header] || '').toString().length));
                                    // Cap width at 70 chars for very long fields like paths
                                    return { wch: Math.min(maxWidth + 2, 70) };
                                });
                            };
                            // 1. Prepara a aba de Resumo
                            const summaryData = [
                                { Key: 'Comparison Date', Value: data.ComparisonStart ? new Date(data.ComparisonStart) : 'N/A' },
                                { Key: 'Comparison Duration', Value: `${data.ComparisonDuration_sec} seconds` },
                                { Key: '--- Source Datasource Info ---', Value: '' },
                                { Key: 'Folders in Source', Value: data.SourceInfo.TotalFolders.toLocaleString('en-US') },
                                { Key: 'Documents in Source', Value: data.SourceInfo.TotalDocuments.toLocaleString('en-US') },
                                { Key: 'Total Size in Source', Value: formatBytes(data.SourceInfo.TotalSize) },
                                { Key: 'Environments in Source', Value: data.SourceInfo.Environments.Count },
                                { Key: 'Workflows in Source', Value: data.SourceInfo.Workflows.Count },
                                { Key: '--- Comparison Results ---', Value: '' },
                                { Key: 'Folders Not Found in Target', Value: data.ComparisonResults.Folders.filter(f => f.Status !== 'Found').length },
                                { Key: 'Environments Not Found', Value: data.ComparisonResults.Environments.filter(e => e.Status !== 'Found').length },
                                { Key: 'Workflows Not Found', Value: data.ComparisonResults.Workflows.filter(w => w.Status !== 'Found').length }
                            ];
                            const summarySheet = XLSX.utils.json_to_sheet(summaryData, { skipHeader: true });
                            summarySheet['!cols'] = [{ wch: 30 }, { wch: 25 }];

                            // 2. Prepare Folder Structure sheet
                            const folderData = data.ComparisonResults.Folders.map(f => ({ Path: f.Path, Status: f.Status }));
                            const foldersSheet = XLSX.utils.json_to_sheet(folderData);
                            foldersSheet['!cols'] = getColumnWidths(folderData);
                            styleHeader(foldersSheet);

                            // 3. Prepare Environments sheet
                            const envs = data.ComparisonResults.Environments.flatMap(env => 
                                (env.Columns && env.Columns.length > 0)
                                    ? env.Columns.map(col => ({
                                        Environment: env.Name,
                                        EnvStatus: env.Status,
                                        Attribute: col.Name,
                                        AttrStatus: col.Status
                                    }))
                                    : [{ Environment: env.Name, EnvStatus: env.Status, Attribute: 'N/A', AttrStatus: 'N/A' }]
                            );
                            const envsSheet = XLSX.utils.json_to_sheet(envs);
                            envsSheet['!cols'] = getColumnWidths(envs);
                            styleHeader(envsSheet);

                            // 4. Prepare Workflows sheet
                            const wfs = data.ComparisonResults.Workflows.flatMap(wf => 
                                (wf.States && wf.States.length > 0)
                                    ? wf.States.map(state => ({
                                        Workflow: wf.Name,
                                        WfStatus: wf.Status,
                                        State: state.Name,
                                        StateStatus: state.Status
                                    }))
                                    : [{ Workflow: wf.Name, WfStatus: wf.Status, State: 'N/A', StateStatus: 'N/A' }]
                            );
                            const wfsSheet = XLSX.utils.json_to_sheet(wfs);
                            wfsSheet['!cols'] = getColumnWidths(wfs);
                            styleHeader(wfsSheet);

                            // 5. Create workbook and trigger download
                            const wb = XLSX.utils.book_new();
                            XLSX.utils.book_append_sheet(wb, summarySheet, 'Summary');
                            XLSX.utils.book_append_sheet(wb, foldersSheet, 'Folder Structure');
                            XLSX.utils.book_append_sheet(wb, envsSheet, 'Environments Comparison');
                            XLSX.utils.book_append_sheet(wb, wfsSheet, 'Workflows Comparison');

                            const comparisonDateISO = new Date(data.ComparisonStart).toISOString().split('T')[0];
                            XLSX.writeFile(wb, `Powe_Comparison_Report_${comparisonDateISO}.xlsx`);
                        }
                    }
                ],
                data: rootFolders,
                columns: [
                    {
                        className: 'details-control',
                        orderable: false,
                        data: null,
                        defaultContent: '[+]',
                        width: '20px'
                    },
                    { data: 'Path' },
                    { 
                        data: 'Status',
                        className: 'dt-body-center',
                        render: function(data, type, row) {
                            const statusClass = data === 'Found' ? 'status-found' : 'status-not-found';
                            return `<span class="${statusClass}">${data}</span>`;
                        }
                    }
                ],
                pageLength: 10,
                order: [[1, 'asc']] // Ordena por caminho da pasta
            });

            // Event handler for expanding/collapsing rows (delegated from a static parent)
            $('#folders-table-container').on('click', 'td.details-control', function () {
                const tr = $(this).closest('tr');
                const mainTable = $('#foldersTable').DataTable();
                const row = mainTable.row(tr);

                if (row.data()) { // It's a DataTables row (top-level)
                    const rowData = row.data();
                    if (row.child.isShown()) {
                        row.child.hide();
                        tr.removeClass('details');
                        $(this).html('[+]');
                    } else {
                        const children = childMap.get(rowData.ProjectID) || [];
                        if (children.length > 0) {
                            row.child(formatChildRows(children), 'child-row-container').show();
                            tr.addClass('details');
                            $(this).html('[-]');
                        }
                    }
                } else {
                    // It's a manually created row in a child table
                    const projectId = tr.data('project-id');
                    const isShown = tr.next('tr.child-row-container').length > 0;

                    if (isShown) {
                        tr.next('tr.child-row-container').remove();
                        tr.removeClass('details');
                        $(this).html('[+]');
                    } else {
                        const children = childMap.get(projectId) || [];
                        if (children.length > 0) {
                            const childHtml = formatChildRows(children);
                            tr.after(`<tr class="child-row-container"><td colspan="3">${childHtml}</td></tr>`);
                            tr.addClass('details');
                            $(this).html('[-]');
                        }
                    }
                }
            });

        })
        .catch(error => {
            console.error('Erro ao carregar ou processar os dados de comparação:', error);
            $('#summary').html(`<p class="error">Failed to load comparison data. Check if the collection was executed and if C.json exists. Details: ${error.message}</p>`);
        });

    // Função para formatar as linhas filhas (sub-pastas)
    function formatChildRows(childData) {
        if (childData.length === 0) {
            return '<div style="padding-left: 20px;"><em>No subfolders.</em></div>';
        }
        let html = '<table class="child-table">';
        childData.forEach(child => {
            const statusClass = child.Status === 'Found' ? 'status-found' : 'status-not-found';
            // Adiciona um ícone de expandir apenas se a subpasta também tiver filhos
            const expander = child.hasChildren ? '<td class="details-control">[+]</td>' : '<td></td>';
            html += `
                <tr data-project-id="${child.ProjectID}" data-parent-id="${child.ParentID}">
                    ${expander}
                    <td>${child.Path}</td>
                    <td class="${statusClass}">${child.Status}</td>
                </tr>`;
        });
        html += '</table>';
        return html;
    }

    // Função auxiliar para formatar bytes
    function formatBytes(bytes, decimals = 2) {
        if (!bytes || bytes === 0) return '0 Bytes';

        const k = 1024;
        const dm = decimals < 0 ? 0 : decimals;
        const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];

        const i = Math.floor(Math.log(bytes) / Math.log(k));

        return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
    }

    // Função auxiliar para aplicar estilo de negrito ao cabeçalho de uma planilha (worksheet)
    function styleHeader(sheet) {
        if (!sheet || !sheet['!ref']) return;
        const range = XLSX.utils.decode_range(sheet['!ref']);
        const headerRow = range.s.r; // A primeira linha é o cabeçalho
        for (let C = range.s.c; C <= range.e.c; ++C) {
            const cell_address = XLSX.utils.encode_cell({ r: headerRow, c: C });
            if (sheet[cell_address]) {
                if (!sheet[cell_address].s) sheet[cell_address].s = {};
                if (!sheet[cell_address].s.font) sheet[cell_address].s.font = {};
                sheet[cell_address].s.font.bold = true;
            }
        }
    }
});