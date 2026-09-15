const express = require('express');
const path = require('path');
const open = require('open');

const app = express();
const port = 8080;

// Define o diretório base do projeto
const baseDir = __dirname;

// Serve os arquivos estáticos da pasta 'dashboard'
app.use(express.static(path.join(baseDir, 'dashboard')));

// Serve os arquivos da pasta 'output' para que o dashboard possa acessá-los
app.use('/output', express.static(path.join(baseDir, 'output')));

app.listen(port, () => {
    const url = `http://localhost:${port}/dashboard.html`;
    console.log(`\n✅ Server started successfully!`);
    console.log(`   Dashboard is accessible at: ${url}`);
    console.log(`   Press Ctrl+C to stop the server.`);
    // Abre o dashboard no navegador padrão
    open(url);
});