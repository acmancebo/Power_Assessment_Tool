# Power Assessment Tool

Uma ferramenta para avaliação, comparação e classificação de ambientes ProjectWise com foco em readiness, riscos e dashboards executivos.

## Visão geral

Este projeto combina:

- coleta de dados via PowerShell
- comparação entre dois datasources
- cálculo de score de readiness
- geração de relatórios em CSV/JSON
- dashboard interativo em HTML
- interface web para execução e acompanhamento

A ferramenta é orientada para leitura e análise, não realiza migração de dados nem alterações no ambiente alvo.

## Funcionalidades principais

- coleta estruturada de informações de datasources
- comparação de pastas, documentos e métricas
- cálculo de score de risco e prontidão
- geração de saída em JSON e CSV
- dashboard web para visualização
- logs detalhados para diagnóstico
- execução por interface web ou script PowerShell

## Requisitos

### Obrigatórios

- Windows 10/11
- PowerShell 5.1 ou superior
- Node.js 18+
- npm
- ProjectWise Explorer instalado
- módulo PowerShell `PWPS_DAB` instalado

### Instalação do módulo ProjectWise

Abra o PowerShell como administrador e rode:

```powershell
Install-Module -Name PWPS_DAB -Scope CurrentUser -Force
```

## Clonagem e instalação

```bash
git clone https://github.com/acmancebo/Power_Assessment_Tool.git
cd Power_Assessment_Tool
npm install
```

## Execução

### Iniciar a interface web

```bash
npm start
```

A aplicação abre o dashboard em:

```text
http://localhost:3000
```

Se a porta 3000 estiver ocupada, o app tenta automaticamente a próxima porta disponível. Também é possível forçar outra porta:

```bash
PORT=3001 npm start
```

### Executar em modo desenvolvimento

```bash
npm run dev
```

## Estrutura do projeto

```text
Power_Assessment_Tool/
├── config/
├── dashboard/
├── gui/
├── logs/
├── output/
├── scripts/
├── src/
├── app.js
├── server.js
├── package.json
├── README.md
├── LICENSE
└── .gitignore
```

## Como usar

1. Configure os dados de entrada em `config/settings.json` quando necessário.
2. Execute a interface web com `npm start`.
3. Informe os datasources A e B e os caminhos a analisar.
4. Aguarde a execução do script PowerShell.
5. Visualize os resultados em `dashboard/` e em `output/`.

## Saídas

A execução gera arquivos em `output/`, como:

- `A.json`
- `B.json`
- `C.json`
- `Score.json`
- `Comparison.csv`

Também ficam logs em `logs/` para investigação detalhada.

## Compatibilidade com versões do ProjectWise

A ferramenta detecta automaticamente o modo de autenticação correto:

- **Auto** (padrão): tenta login via Bentley IMS (ProjectWise CONNECT Edition) e, se falhar, tenta login nativo/Windows (versões clássicas do ProjectWise).
- **BentleyIMS**: força autenticação via Bentley IMS.
- **Native**: força autenticação nativa/Windows, sem IMS.

O modo pode ser escolhido na interface web (campo "ProjectWise Authentication") ou fixado em `config/settings.json` através da chave `authMode`.

Os cmdlets do módulo `PWPS_DAB` que variam entre versões (ex: hidratação em lote de pastas, colunas de ambiente, estados de workflow) já possuem fallback automático, então o toolkit continua funcionando mesmo que algum cmdlet específico não exista na versão instalada.

## Observações importantes

- O projeto depende de acesso ao ambiente ProjectWise e dos módulos corretamente instalados.
- A execução precisa de permissões de leitura adequadas no datasource alvo.
- O código foi pensado para análise e diagnóstico, não para alteração do ambiente.

## Licença

Este projeto está licenciado sob a licença MIT. Consulte o arquivo [LICENSE](LICENSE).

## Repositório

- GitHub: https://github.com/acmancebo/Power_Assessment_Tool

## Autor

Anderson Mancebo