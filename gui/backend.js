// ===================================================================================
// Powe Assessment Toolkit - GUI Backend
// Description: Node.js/Express server to orchestrate the PowerShell assessment script.
// ===================================================================================

const express = require('express');
const { spawn } = require('child_process');
const path = require('path');
const WebSocket = require('ws');
const fs = require('fs');

const app = express();

// app.listen() fails asynchronously via the 'error' event, so port retries
// must be event-driven rather than wrapped in a synchronous try/catch.
function startServer(startPort, maxAttempts = 20) {
    return new Promise((resolve, reject) => {
        const requestedPort = Number(process.env.PORT);
        const initialPort = Number.isInteger(requestedPort) && requestedPort > 0 ? requestedPort : startPort;

        const tryPort = (candidatePort, attemptsLeft) => {
            const server = app.listen(candidatePort);
            server.once('listening', () => resolve({ server, port: candidatePort }));
            server.once('error', (error) => {
                server.removeAllListeners();
                if (error.code === 'EADDRINUSE' && attemptsLeft > 0) {
                    tryPort(candidatePort + 1, attemptsLeft - 1);
                } else {
                    reject(error);
                }
            });
        };

        tryPort(initialPort, maxAttempts);
    });
}

// --- Server Setup ---
app.use(express.json());
// Serve static files (index.html, styles.css, app.js) from the 'gui' directory.
// __dirname will be the 'gui' folder, so this is correct.
app.use(express.static(__dirname));
// Create a dedicated static route for the dashboard to be accessible via /dashboard
app.use('/dashboard', express.static(path.join(__dirname, '..', 'dashboard')));
// Expose the /output directory and ensure JSON files are served with the correct UTF-8 charset header.
app.use('/output', express.static(path.join(__dirname, '..', 'output'), {
    setHeaders: (res, filePath) => {
        if (path.extname(filePath) === '.json') {
            res.setHeader('Content-Type', 'application/json; charset=utf-8');
        }
    }
}));

let wss;

function broadcast(data) {
    if (!wss) return;
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            // Always send data as a stringified JSON object
            client.send(JSON.stringify(data));
        }
    });
}

startServer(3000).then(({ server, port }) => {
    console.log(`✅ Powe Assessment GUI is running.`);
    console.log(`   Please open http://localhost:${port} in your web browser.`);

    wss = new WebSocket.Server({ server });

    // --- WebSocket Connection Handling ---
    wss.on('connection', ws => {
        console.log('Client connected to WebSocket.');
        ws.on('close', () => console.log('Client disconnected.'));
    });
}).catch((error) => {
    console.error(`❌ Failed to start server: ${error.message}`);
    process.exit(1);
});

// --- API Endpoints ---

// Endpoint to trigger the PowerShell script
app.post('/run', (req, res) => {
    const { datasourceA, datasourceB, paths, authMode } = req.body;
    const runId = Date.now().toString(); // Unique ID for this run
    const outputDir = path.join(__dirname, '..', 'output', runId);

    if (!datasourceA || !datasourceB || !paths) {
        return res.status(400).json({ message: 'Missing required parameters.' });
    }

    try {
        fs.mkdirSync(outputDir, { recursive: true });
    } catch (error) {
        console.error(`Failed to create output directory: ${outputDir}`, error);
        return res.status(500).json({ message: 'Failed to create output directory.' });
    }

    const scriptPath = path.join(__dirname, '..', 'scripts', 'master.ps1');
    const pathsString = paths.replace(/\n/g, ';');
    const allowedAuthModes = new Set(['Auto', 'BentleyIMS', 'Native']);
    const resolvedAuthMode = allowedAuthModes.has(authMode) ? authMode : 'Auto';

    console.log(`Starting PowerShell script for runId: ${runId}`);
    // Pass runId in broadcast messages
    broadcast({ type: 'status', message: 'Starting assessment...', runId });

    // Use 'spawn' for long-running processes and streaming output
    // We explicitly avoid `shell: true` for better security and argument handling.
    // Node.js will handle finding powershell.exe in the system's PATH.
    const ps = spawn(
        'powershell.exe',
        [
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', scriptPath,
            '-DatasourceA', datasourceA,
            '-DatasourceB', datasourceB,
            '-Paths', pathsString,
            '-AuthMode', resolvedAuthMode,
            '-RunOutputPath', outputDir // New parameter for isolated output
        ]
    );

    ps.stdout.on('data', (data) => {
        const message = data.toString();
        console.log(`[${runId}] stdout: ${message}`);
        broadcast({ type: 'log', message: message.trim(), runId });
    });

    ps.stderr.on('data', (data) => {
        const message = data.toString();
        console.error(`[${runId}] stderr: ${message}`);
        broadcast({ type: 'error', message: `ERROR: ${message.trim()}`, runId });
    });

    ps.on('close', (code) => {
        console.log(`[${runId}] PowerShell script finished with code ${code}`);
        if (code === 0) {
            broadcast({ type: 'status', message: 'Assessment complete. Fetching results...', runId });
            broadcast({ type: 'complete', runId });
        } else {
            broadcast({ type: 'error', message: `Assessment failed with exit code ${code}. Check logs for details.`, runId });
        }
    });

    res.status(202).send({ message: 'Assessment started.', runId: runId });
});

// Endpoint to fetch results after completion
app.get('/get-results', (req, res) => {
    const runId = req.query.runId;
    if (!runId) {
        return res.status(400).send({ message: 'Missing runId parameter.' });
    }

    const scorePath = path.join(__dirname, '..', 'output', runId, 'Score.json');
    // The C.json file contains the source summary info, including total folders.
    const comparisonSummaryPath = path.join(__dirname, '..', 'output', runId, 'C.json');

    try {
        // Check if all required files exist before reading.
        if (!fs.existsSync(scorePath) || !fs.existsSync(comparisonSummaryPath)) {
            throw new Error(`Result files (Score.json, C.json) not found for runId ${runId}. The scoring script may have failed.`);
        }

        const scoreData = JSON.parse(fs.readFileSync(scorePath, 'utf8'));
        const comparisonSummaryData = JSON.parse(fs.readFileSync(comparisonSummaryPath, 'utf8'));

        // Extract the necessary data from the JSON files.
        const totalFolders = comparisonSummaryData?.SourceInfo?.TotalFolders || 0;
        const issuesCount = scoreData?.TotalIssues || 0;

        res.json({ scoreData, totalFolders, issuesCount });
    } catch (error) {
        console.error("Error reading result files:", error);
        res.status(500).send({ message: 'Could not read result files.' });
    }
});

// Endpoint to get a list of past runs
app.get('/get-runs', (req, res) => {
    const outputDir = path.join(__dirname, '..', 'output');
    try {
        if (!fs.existsSync(outputDir)) {
            return res.json([]);
        }
        const runDirs = fs.readdirSync(outputDir, { withFileTypes: true })
            .filter(dirent => dirent.isDirectory() && /^\d+$/.test(dirent.name))
            .map(dirent => dirent.name)
            .sort((a, b) => b - a); // Sort descending (newest first)
        res.json(runDirs);
    } catch (error) {
        console.error("Error reading output directory for runs:", error);
        res.status(500).send({ message: 'Could not list past assessment runs.' });
    }
});

// Endpoint to delete a past run
app.delete('/delete-run', (req, res) => {
    const { runId } = req.body;

    // Basic validation to prevent path traversal
    if (!runId || !/^\d+$/.test(runId)) {
        return res.status(400).json({ message: 'Invalid runId provided.' });
    }

    const runPath = path.join(__dirname, '..', 'output', runId);

    try {
        if (fs.existsSync(runPath)) {
            fs.rmSync(runPath, { recursive: true, force: true });
            console.log(`Deleted run directory: ${runPath}`);
            res.status(200).json({ message: `Run ${runId} deleted successfully.` });
        } else {
            res.status(404).json({ message: `Run ${runId} not found.` });
        }
    } catch (error) {
        console.error(`Failed to delete run directory ${runPath}:`, error);
        res.status(500).json({ message: `Failed to delete run ${runId}.` });
    }
});

// Endpoint to get a list of available log files
app.get('/get-log-files', (req, res) => {
    const logDir = path.join(__dirname, '..', 'logs');
    try {
        const files = fs.readdirSync(logDir)
            .filter(file => file.endsWith('.log'))
            .sort()
            .reverse(); // Show newest first
        res.json(files);
    } catch (error) {
        console.error("Error reading log directory:", error);
        res.status(500).send({ message: 'Could not read log directory.' });
    }
});

// Endpoint to get the content of a specific log file
app.get('/get-log-content', (req, res) => {
    const fileName = req.query.file;
    if (!fileName || !/^[a-zA-Z0-9_.-]+$/.test(fileName)) {
        return res.status(400).send({ message: 'Invalid or missing file name.' });
    }
    const logPath = path.join(__dirname, '..', 'logs', fileName);
    try {
        const content = fs.readFileSync(logPath, 'utf8');
        res.setHeader('Content-Type', 'text/plain');
        res.send(content);
    } catch (error) {
        console.error(`Error reading log file ${fileName}:`, error);
        res.status(404).send({ message: `Log file '${fileName}' not found.` });
    }
});