document.addEventListener('DOMContentLoaded', () => {
    // --- Element References ---
    const form = document.getElementById('assessment-form');
    const runButton = document.getElementById('run-button');
    const spinner = runButton.querySelector('.spinner');
    const btnText = runButton.querySelector('.btn-text');
    const logOutput = document.getElementById('log-output');
    const statusMessage = document.getElementById('status-message');
    const progressBar = document.getElementById('progress-bar');
    const resultsContent = document.getElementById('results-content');
    const resultsPlaceholder = document.getElementById('results-placeholder');
    const dashboardButton = document.getElementById('dashboard-button');
    const themeToggle = document.getElementById('theme-toggle');
    const logSelector = document.getElementById('log-selector');
    const historyList = document.getElementById('history-list');
    const historyPlaceholder = document.getElementById('history-placeholder');

    let currentRunId = null;

    // --- WebSocket Setup ---
    const ws = new WebSocket(`ws://${window.location.host}`);

    ws.onopen = () => {
        console.log('WebSocket connection established.');
        logOutput.textContent = 'Connected to backend. Ready for assessment.\n';
        checkUrlForErrors(); // Check for errors on initial load/reconnect
        populateLogSelector();
        populateHistoryList();
    };

    ws.onmessage = (event) => {
        const data = JSON.parse(event.data);
        handleWebSocketMessage(data);
    };

    ws.onerror = (error) => {
        console.error('WebSocket Error:', error);
        logOutput.textContent += '\nERROR: Could not connect to the backend server.\n';
    };

    // --- Event Handlers ---
    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        resetUI();
        toggleLoading(true);
        saveInputs();

        const formData = new FormData(form);
        const data = Object.fromEntries(formData.entries());

        try {
            const response = await fetch('/run', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data),
            });

            if (!response.ok) {
                const error = await response.json();
                throw new Error(error.message || 'Failed to start assessment.');
            }
            const responseData = await response.json();
            currentRunId = responseData.runId;
        } catch (error) {
            console.error('Error starting assessment:', error);
            appendLog(`ERROR: ${error.message}`, 'error');
            toggleLoading(false);
        }
    });

    dashboardButton.addEventListener('click', () => {
        if (currentRunId) {
            window.open(`/dashboard/dashboard.html?runId=${currentRunId}`, '_blank');
        }
    });

    // Use event delegation for dynamically added buttons in the history list
    historyList.addEventListener('click', async (e) => {
        const target = e.target;
        const runId = target.closest('li')?.dataset.runid;

        if (!runId) return;

        if (target.classList.contains('btn-view')) {
            // Open the dashboard for the selected run
            window.open(`/dashboard/dashboard.html?runId=${runId}`, '_blank');
        } else if (target.classList.contains('btn-delete')) {
            // Ask for confirmation before deleting
            if (confirm(`Are you sure you want to delete the assessment run from ${new Date(parseInt(runId, 10)).toLocaleString()}? This action cannot be undone.`)) {
                try {
                    const response = await fetch('/delete-run', {
                        method: 'DELETE',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ runId }),
                    });
                    if (!response.ok) {
                        const error = await response.json();
                        throw new Error(error.message || 'Failed to delete run.');
                    }
                    populateHistoryList(); // Refresh the list after deletion
                } catch (error) {
                    console.error('Error deleting run:', error);
                    alert(`Error: ${error.message}`);
                }
            }
        }
    });

    themeToggle.addEventListener('change', () => {
        document.body.classList.toggle('dark-mode', themeToggle.checked);
        localStorage.setItem('darkMode', themeToggle.checked);
    });

    logSelector.addEventListener('change', async () => {
        const selectedLog = logSelector.value;
        logOutput.innerHTML = ''; // Clear the log view

        if (selectedLog) {
            // Fetch and display a historical log
            try {
                const response = await fetch(`/get-log-content?file=${selectedLog}`);
                if (!response.ok) {
                    throw new Error(`Failed to load log file. Status: ${response.status}`);
                }
                const logContent = await response.text();
                appendLog(logContent);
                statusMessage.textContent = `Displaying historical log: ${selectedLog}`;
            } catch (error) {
                console.error('Error fetching log content:', error);
                appendLog(`ERROR: ${error.message}`, 'error');
            }
        } else {
            // Switched back to live log
            statusMessage.textContent = 'Switched to live log view. Run an assessment to see output.';
        }
    });

    // --- UI Update Functions ---
    function handleWebSocketMessage(data) {
        // Ignore messages from other runs
        if (data.runId && data.runId !== currentRunId) {
            return;
        }

        switch (data.type) {
            case 'log':
            case 'error':
                const level = data.message.includes('[Error]') || data.type === 'error' ? 'error' : 'log';
                appendLog(data.message, level);
                updateProgress(data.message);
                break;
            case 'status':
                statusMessage.textContent = data.message;
                break;
            case 'complete':
                toggleLoading(false);
                progressBar.style.width = '100%';
                // A run has completed. It might be the one we started, or one that finished
                // while the page was reloaded. We must use the runId from the message to fetch the correct results.
                if (data && data.runId) {
                    currentRunId = data.runId;
                    fetchAndDisplayResults(data.runId);
                } else {
                    // This case should not happen, but as a safeguard:
                    const errorMsg = 'Could not process completion: "complete" message received from backend without a runId.';
                    console.error(errorMsg, data);
                    appendLog(`ERROR: ${errorMsg}`, 'error');
                }
                populateHistoryList(); // Refresh history list after a run completes
                populateLogSelector(); // Refresh log list after run
                break;
        }
    }

    function toggleLoading(isLoading) {
        runButton.disabled = isLoading;
        spinner.style.display = isLoading ? 'inline-block' : 'none';
        btnText.textContent = isLoading ? 'Running...' : 'Run Assessment';
    }

    function appendLog(message, level = 'log') {
        // If viewing a historical log, don't append live messages
        if (logSelector.value !== '') {
            return;
        }

        const line = document.createElement('div');
        line.textContent = message;
        line.classList.add(level); // for styling 'error' logs differently
        logOutput.appendChild(line);
        logOutput.scrollTop = logOutput.scrollHeight; // Auto-scroll
    }

    function updateProgress(logMessage) {
        // The 'PROGRESS::xx' message from collector.ps1 provides granular updates for the collection phase.
        if (logMessage.startsWith('PROGRESS::')) {
            const progressValue = parseInt(logMessage.split('::')[1], 10);
            if (!isNaN(progressValue)) {
                // Map the 0-100 collection progress to the 10-45% range of the UI progress bar.
                const mappedProgress = 10 + (progressValue * 0.35);
                setProgress(mappedProgress);
            }
        }
        else if (logMessage.includes('--- Starting Data Collection Phase ---')) setProgress(5);
        else if (logMessage.includes('--- Data Collection Finished ---')) setProgress(45);
        else if (logMessage.includes('--- Starting Comparison Phase ---')) setProgress(50);
        else if (logMessage.includes('--- Comparison Finished ---')) setProgress(90);
    }

    function setProgress(percentage) {
        progressBar.style.width = `${percentage}%`;
    }

    function resetUI() {
        logOutput.innerHTML = '';
        statusMessage.textContent = 'Ready to start.';
        setProgress(0);
        resultsContent.style.display = 'none';
        resultsPlaceholder.style.display = 'block';
        dashboardButton.style.display = 'none';
        logSelector.value = ''; // Default to live log
    }

    
    async function fetchAndDisplayResults(runIdToFetch) {
        if (!runIdToFetch) {
            const errorMsg = 'Could not fetch results: The backend did not provide a runId.';
            console.error(errorMsg);
            appendLog(`ERROR: ${errorMsg}`, 'error');
            return;
        }

        try {
            const response = await fetch(`/get-results?runId=${runIdToFetch}`);
            if (!response.ok) {
                const errorData = await response.json().catch(() => ({ message: `Server responded with status ${response.status}` }));
                throw new Error(errorData.message || 'Unknown error fetching results.');
            }
            const results = await response.json();

            document.getElementById('result-score').textContent = results.scoreData.Score;
            const classificationEl = document.getElementById('result-classification');
            classificationEl.textContent = results.scoreData.Classification;
            classificationEl.className = `kpi-classification ${results.scoreData.Classification.replace(' ', '-')}`;

            document.getElementById('result-folders').textContent = results.totalFolders;
            document.getElementById('result-issues').textContent = results.issuesCount;

            resultsPlaceholder.style.display = 'none';
            resultsContent.style.display = 'grid';
            dashboardButton.style.display = 'block';

        } catch (error) {
            console.error('Failed to fetch results:', error);
            appendLog(`ERROR: Could not fetch final results. ${error.message}`, 'error');
        }
    }

    function checkUrlForErrors() {
        const urlParams = new URLSearchParams(window.location.search);
        if (urlParams.has('error') && urlParams.get('error') === 'no_run_id') {
            // Use a more user-friendly message to guide the user.
            const errorMessage = 'Reports must be opened from the "View Dashboard" button after a run is complete. Please start a new assessment.';
            statusMessage.textContent = errorMessage;
            appendLog(`INFO: ${errorMessage}`, 'log');
            // Clean the URL so the message doesn't reappear on refresh.
            window.history.replaceState({}, document.title, "/");
        }
    }

    // --- New History Functions ---
    async function populateHistoryList() {
        try {
            const response = await fetch('/get-runs');
            if (!response.ok) {
                throw new Error('Failed to fetch past runs.');
            }
            const runs = await response.json();

            historyList.innerHTML = ''; // Clear the list

            if (runs.length === 0) {
                historyPlaceholder.style.display = 'block';
            } else {
                historyPlaceholder.style.display = 'none';
                runs.forEach(runId => {
                    const li = document.createElement('li');
                    li.dataset.runid = runId;

                    const runTimestamp = parseInt(runId, 10);
                    const runDate = new Date(runTimestamp);

                    li.innerHTML = `
                        <div>
                            <span class="run-info">Assessment from:</span>
                            <span class="run-date">${runDate.toLocaleString()}</span>
                        </div>
                        <div class="run-actions">
                            <button class="btn-secondary btn-view">View Reports</button>
                            <button class="btn-delete">Delete</button>
                        </div>
                    `;
                    historyList.appendChild(li);
                });
            }
        } catch (error) {
            console.error('Error populating history list:', error);
            historyPlaceholder.textContent = 'Error loading past assessments.';
            historyPlaceholder.style.display = 'block';
        }
    }

    // --- Bonus Features: Persistence ---
    function saveInputs() {
        const inputs = {
            datasourceA: form.datasourceA.value,
            datasourceB: form.datasourceB.value,
            paths: form.paths.value,
        };
        localStorage.setItem('assessmentInputs', JSON.stringify(inputs));
    }

    function loadInputs() {
        const savedInputs = localStorage.getItem('assessmentInputs');
        if (savedInputs) {
            const inputs = JSON.parse(savedInputs);
            form.datasourceA.value = inputs.datasourceA || '';
            form.datasourceB.value = inputs.datasourceB || '';
            form.paths.value = inputs.paths || '';
        }

        const darkMode = localStorage.getItem('darkMode') === 'true';
        themeToggle.checked = darkMode;
        document.body.classList.toggle('dark-mode', darkMode);
    }

    async function populateLogSelector() {
        try {
            const response = await fetch('/get-log-files');
            const files = await response.json();
            
            // Clear existing options except for the first "Live Log"
            logSelector.innerHTML = '<option value="">Live Log</option>';

            files.forEach(file => {
                const option = document.createElement('option');
                option.value = file;
                option.textContent = file;
                logSelector.appendChild(option);
            });
        } catch (error) {
            console.error('Failed to populate log selector:', error);
        }
    }

    // --- Initial Load ---
    loadInputs();
    populateHistoryList();
});