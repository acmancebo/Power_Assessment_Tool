# ProjectWise Assessment & Readiness Toolkit (Powe)

**Version 1.0**

## 🎯 Overview

The ProjectWise Assessment & Readiness Toolkit is an enterprise-grade PowerShell-based solution designed to analyze, compare, and score ProjectWise datasources. It provides critical insights for migration planning, health checks, and data governance by generating executive-level dashboards and detailed reports.

This tool performs a **read-only assessment** and does **NOT** perform any data migration or modification.

## ✨ Key Features

- **High-Performance Data Collection**: Efficiently gathers statistics from large ProjectWise environments (100GB+) without overloading memory, using a recursive, non-blocking approach.
- **Intelligent Comparison Engine**: Compares two datasources to identify differences in folder structures, document counts, data volume, and metadata (workflows, environments).
- **Risk & Readiness Scoring**: Calculates a quantitative score (0-100) to classify migration readiness as `Ready`, `Moderate Risk`, or `High Risk`.
- **Executive Dashboards**: Generates a professional, interactive HTML dashboard with KPIs, charts (using Chart.js), and filterable data tables for clear visualization of assessment results.
- **Robust Logging & Configuration**: Features a detailed logging system and external JSON configuration for adaptable, transparent execution.

---

## ⚙️ Prerequisites

1.  **Windows PowerShell 5.1** or higher.
2.  **ProjectWise Explorer Client** installed.
3.  **`PWPS_DAB` PowerShell Module**: This is required for interacting with ProjectWise. Install it by running PowerShell as an Administrator:
    ```powershell
    Install-Module -Name PWPS_DAB -Scope CurrentUser -Force
    ```
4.  **Bentley IMS Account**: A user account with sufficient read permissions on the target datasources.

---

## 🚀 Quick Start

1.  **Clone/Download the Toolkit**: Place the `Power_Assessment_Tool` folder in your desired location.

2.  **Configure Settings (Optional)**:
    Open `config/settings.json` to adjust parameters like `batchSize` or `logLevel` if needed. The default settings are optimized for general use.

3.  **Run the Assessment**:
    Open a PowerShell terminal, navigate to the `scripts` directory, and execute the `master.ps1` script.

    ```powershell
    # Navigate to the scripts directory
    cd "C:\Users\Anderson.Mancebo\OneDrive - Bentley Systems, Inc\Documents\ProjectWise Scripts and Apps\Power_Assessment_Tool\scripts"

    # Execute the master script with your parameters
    .\master.ps1 -DatasourceA "PWHOST:DatasourceA" -DatasourceB "PWHOST:DatasourceB" -Paths "Folder 1\Subfolder;Folder 2"
    ```

    **Parameters**:
    - `-DatasourceA` (string): The full name of the source datasource (e.g., `pw.bentley.com:datasource1`).
    - `-DatasourceB` (string): The full name of the target datasource.
    - `-Paths` (string): A semicolon-separated list of root folder paths to analyze.

4.  **Review the Output**:
    - **Dashboard**: Once the script completes, open `dashboard/dashboard.html` in a web browser to view the interactive report.
    - **Raw Data**: Check the `output/` folder for the generated `A.csv`, `B.csv`, `Comparison.csv`, and `Score.json` files.
    - **Logs**: Review detailed execution logs in the `logs/` folder for troubleshooting.

---

© 2024. Designed for enterprise ProjectWise assessment.