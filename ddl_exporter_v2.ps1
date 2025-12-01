<#
.SYNOPSIS
    Connects to one or more SQL Server instances and exports the complete DDL schema
    for every user database using either command-line parameters or a CSV input file.

.DESCRIPTION
    This script accepts a list of SQL Server instances either directly via -SqlServerInstance 
    or from a CSV file specified by -InputFile. It supports Windows or SQL Authentication,
    and explicitly bypasses strict certificate/encryption requirements.

    It generates a detailed log file and an HTML summary report of the export process.

.PARAMETER SqlServerInstance
    [Optional] One or more SQL Server instance names (e.g., "localhost", "SERVER\SQLEXPRESS"). 
    Must be provided if -InputFile is not used.

.PARAMETER InputFile
    [Optional] Path to a CSV file containing a list of server names. The CSV MUST contain
    a column named 'ServerName'. If provided, this overrides -SqlServerInstance.

.PARAMETER OutputDirectory
    The path to the folder where the .sql DDL files, log file, and HTML summary will be saved.

.PARAMETER SqlUser
    [Optional] Username for SQL Server Authentication.

.PARAMETER SqlPassword
    [Optional] Password for SQL Server Authentication.
#>
param(
    [Parameter(Mandatory = $false)]
    [string[]]$SqlServerInstance, # Accepts multiple server names (Optional)

    [Parameter(Mandatory = $false)]
    [string]$InputFile = $null, # New CSV input parameter (Optional)

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$SqlUser = $null,
    [string]$SqlPassword = $null
)

# Define variables for logging and summary
$TimeStampFormat = "yyyy-MM-dd HH:mm:ss"
$FileTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFileName = "DDL_Export_Log_$($FileTimestamp).log"
$LogPath = Join-Path -Path $OutputDirectory -ChildPath $LogFileName
$SummaryData = @()

# --- HELPER FUNCTIONS ---

function Add-SummaryEntry {
<#
.SYNOPSIS
    Adds a structured entry to the SummaryData array and writes a colored message to the console.
#>
    param(
        [Parameter(Mandatory = $true)]$Message,
        [Parameter(Mandatory = $true)]
        [ValidateSet("SUCCESS", "FAILURE", "SKIP", "INFO")]
        [string]$Status,
        [string]$Server = "N/A",
        [string]$Database = "N/A",
        [string]$FilePath = "N/A"
    )

    $Entry = [PSCustomObject]@{
        Timestamp = Get-Date -Format $TimeStampFormat
        Server    = $Server
        Database  = $Database
        Status    = $Status
        Message   = $Message
        FilePath  = $FilePath
    }
    
    $script:SummaryData += $Entry

    # Write to console with appropriate color
    $color = switch ($Status) {
        "FAILURE" { "Red" }
        "SKIP"    { "Yellow" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }
    Write-Host "[$Status] Server: $($Server) / DB: $($Database) - $Message" -ForegroundColor $color
}

function Generate-HtmlSummary {
<#
.SYNOPSIS
    Generates a color-coded HTML report from the SummaryData array.
#>
    param(
        [Parameter(Mandatory = $true)]$SummaryData,
        [string]$OutputDirectory,
        [string]$LogPath
    )

    $HtmlPath = Join-Path -Path $OutputDirectory -ChildPath "DDL_Export_Summary_$($FileTimestamp).html"

    # CSS for the HTML report
    $htmlStyles = @"
<style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f4f4f9; color: #333; margin: 20px; }
    h1 { color: #0078d4; border-bottom: 2px solid #0078d4; padding-bottom: 10px; }
    table { width: 100%; border-collapse: collapse; margin-top: 20px; box-shadow: 0 4px 8px rgba(0,0,0,0.1); background-color: white; }
    th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #ddd; word-break: break-word; }
    th { background-color: #0078d4; color: white; font-weight: 600; }
    tr.FAILURE { background-color: #f8d7da; }
    tr.SUCCESS { background-color: #d4edda; }
    tr.SKIP { background-color: #fff3cd; }
    tr.INFO { background-color: #e0f7fa; }
    tr:hover { background-color: #f1ff; }
    .log-link { margin-top: 15px; padding: 10px; background-color: #e0f7fa; border: 1px dashed #00bcd4; display: inline-block; }
</style>
"@
    
    # Convert data to HTML table fragment
    $htmlTableFragment = $SummaryData | Select-Object Timestamp, Server, Database, Status, Message, FilePath | ConvertTo-Html -Fragment

    # Add status class to rows for coloring
    $htmlTable = $htmlTableFragment -replace "<tr>", { 
        param($match) 
        # Safely extract the status from the table cell content to apply the class
        $rowContent = $match.Substring(4) 
        $statusMatch = $rowContent -match '<td>(SUCCESS|FAILURE|SKIP|INFO)</td>'
        $status = if ($statusMatch) { $Matches[1] } else { 'INFO' }

        "<tr class='$status'>$rowContent"
    }

    # Full HTML document assembly
    $htmlOutput = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>SQL DDL Export Summary</title>
    $htmlStyles
</head>
<body>
    <h1>SQL DDL Export Summary Report</h1>
    <p>Report Generated: $(Get-Date -Format 'F')</p>
    <div class="log-link">
        Detailed Log File Path: $LogPath
    </div>
    
    <h2>Export Details</h2>
    <table>
        <thead>
            <tr>
                <th>Timestamp</th>
                <th>Server</th>
                <th>Database</th>
                <th>Status</th>
                <th>Message</th>
                <th>DDL File Path</th>
            </tr>
        </thead>
        <tbody>
            $htmlTable
        </tbody>
    </table>
</body>
</html>
"@

    $htmlOutput | Out-File -FilePath $HtmlPath -Encoding UTF8
    Add-SummaryEntry -Message "HTML Summary generated successfully." -Status "INFO"
}

# --- 1. PRE-REQUISITE CHECK AND SETUP ---
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Warning "The 'SqlServer' PowerShell module is not installed."
    Write-Host "Please install it by running: Install-Module -Name SqlServer -Scope CurrentUser"
    exit 1
}

Import-Module SqlServer
# Load necessary assemblies for ServerConnection and SqlConnection
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.Common") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
# Explicitly load System.Data to ensure System.Data.SqlClient.SqlConnection is available
[System.Reflection.Assembly]::LoadWithPartialName("System.Data") | Out-Null 


# Create the output directory if it doesn't exist
if (-not (Test-Path -Path $OutputDirectory)) {
    Add-SummaryEntry -Message "Output directory not found. Creating it at: $OutputDirectory" -Status "INFO"
    New-Item -Path $OutputDirectory -ItemType Directory | Out-Null
}

# Define the list of system databases to exclude
$systemDatabases = @("master", "model", "msdb", "tempdb")

# --- 2. MAIN SERVER LOOP PREPARATION ---
$serversToProcess = @()

if ($InputFile) {
    # Process CSV input
    if (-not (Test-Path -Path $InputFile)) {
        Add-SummaryEntry -Message "Input file not found at: $InputFile" -Status "FAILURE"
        exit 1
    }
    
    Add-SummaryEntry -Message "Reading server list from CSV file: $InputFile" -Status "INFO"

    try {
        $csvData = Import-Csv -Path $InputFile
        
        # Check for the expected column
        if ($csvData | Get-Member -Name 'ServerName' -MemberType NoteProperty -ErrorAction SilentlyContinue) {
            # Extract and filter out any empty or null entries
            $serversToProcess = $csvData.ServerName | Where-Object { $_ -ne "" }
        } else {
            Add-SummaryEntry -Message "CSV file must contain a column named 'ServerName'. Please verify the file structure." -Status "FAILURE"
            exit 1
        }
    }
    catch {
        Add-SummaryEntry -Message "Error reading or parsing CSV file: $($_.Exception.Message)" -Status "FAILURE"
        exit 1
    }

} elseif ($SqlServerInstance) {
    # Process direct parameter input
    $serversToProcess = $SqlServerInstance
    Add-SummaryEntry -Message "Processing server list from command line parameters." -Status "INFO"

} else {
    # Neither input provided
    Write-Error "Error: You must provide either the -SqlServerInstance parameter or the -InputFile parameter."
    Add-SummaryEntry -Message "No server instances or input file provided." -Status "FAILURE"
    exit 1
}

if ($serversToProcess.Count -eq 0) {
    Add-SummaryEntry -Message "No valid server names found in the input source. Exiting." -Status "FAILURE"
    exit 1
}

# --- 3. MAIN SERVER LOOP ---
foreach ($serverName in $serversToProcess) {
    # Trim server name in case of whitespace from CSV import
    $serverName = $serverName.Trim()
    
    # Skip if server name is empty after trimming
    if (-not $serverName) {
        Add-SummaryEntry -Message "Skipping empty server name entry." -Status "SKIP" -Server "BLANK"
        continue
    }

    Add-SummaryEntry -Message "Starting connection and DDL export." -Status "INFO" -Server $serverName
    
    $server = $null
    $conn = $null # Initialize $conn to handle cases where try block fails early
    
    try {
        # --- A. CONFIGURE CONNECTION STRING ---
        
        $connString = "Server=$serverName;"
        $AuthMessage = "Unknown Authentication"

        if ($SqlUser -and $SqlPassword) {
            # SQL Authentication
            $connString += "User ID=$SqlUser;Password=$SqlPassword;"
            $AuthMessage = "SQL Login: $SqlUser"
        } else {
            # Integrated Windows Authentication
            $connString += "Integrated Security=SSPI;"
            $AuthMessage = "Integrated Windows Authentication"
        }
        
        # CRITICAL: Set TrustServerCertificate=True directly in the connection string
        # This is UNCOMMENTED to handle certificate/encryption issues, which sometimes prevent connections.
        #$connString += "TrustServerCertificate=True;"

        # 1. Create the raw SqlConnection object with the full connection string
        $conn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection

        # 2. Pass the SqlConnection to the SMO ServerConnection constructor
        $conn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection($sqlConnection)
        
        # Connect and create the SMO Server object
        $conn.Connect()
        $server = New-Object Microsoft.SqlServer.Management.Smo.Server($conn)
        
        Add-SummaryEntry -Message "Successfully connected using $AuthMessage. Version: $($server.Information.Version)" -Status "SUCCESS" -Server $serverName
        
    }
    catch {
        # --- FIX: Drill down to find the most specific InnerException message ---
        $errorMessage = $_.Exception.Message
        $innerEx = $_.Exception.InnerException
        while ($innerEx) {
            # Capture the innermost, most descriptive message (e.g., firewall, login failure)
            $errorMessage = $innerEx.Message
            $innerEx = $innerEx.InnerException
        }
        
        Add-SummaryEntry -Message "Connection failed: $errorMessage" -Status "FAILURE" -Server $serverName
        
        # Attempt to disconnect if the $conn object was successfully created before the error
        if ($conn -ne $null -and $conn.State -eq 'Open') {
            $conn.Disconnect()
        }
        continue # Skip to the next server in the list
    }

    # --- B. SCRIPTING PROCESS ---
    
    # Get all user databases
    $databases = $server.Databases | Where-Object { 
        ($_.Name -notin $systemDatabases) -and ($_.Status -eq 'Normal') 
    }

    if ($databases.Count -eq 0) {
        Add-SummaryEntry -Message "No user databases found to export." -Status "SKIP" -Server $serverName
        $conn.Disconnect()
        continue
    }
    
    foreach ($db in $databases) {
        $dbName = $db.Name
        # File name includes server and database name to prevent conflicts
        $safeServerName = $serverName.Replace('\','_').Replace(':','_')
        $filePath = Join-Path -Path $OutputDirectory -ChildPath "$($safeServerName)_$($dbName)_DDL.sql"

        # Create a new Scripter object
        $scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter($server)

        # --- Configure Scripter Options for a Complete DDL Export ---
        $options = $scripter.Options
        $options.AllowSystemObjects = $false
        $options.AppendToFile = $false
        $options.Encoding = [System.Text.Encoding]::UTF8
        $options.ClusteredIndexes = $true
        $options.DriAll = $true
        $options.ExtendedProperties = $true
        $options.FullTextIndexes = $true
        $options.IncludeHeaders = $true
        $options.Indexes = $true
        $options.Permissions = $true
        $options.ScriptData = $false
        $options.ScriptDrops = $false
        $options.ScriptSchema = $true
        $options.Triggers = $true
        $options.ToFileOnly = $true
        $options.FileName = $filePath
        $options.IncludeDatabaseContext = $true
        
        # --- Collect all objects to be scripted from the database ---
        $urns = @()
        $urns += $db.Urn
        $urns += $db.Schemas | ForEach-Object { $_.Urn }
        $urns += $db.Roles | ForEach-Object { $_.Urn }
        $urns += $db.Users | ForEach-Object { $_.Urn }
        $urns += $db.UserDefinedFunctions | ForEach-Object { $_.Urn }
        $urns += $db.StoredProcedures | Where-Object { !$_.IsSystemObject } | ForEach-Object { $_.Urn }
        $urns += $db.Tables | Where-Object { !$_.IsSystemObject } | ForEach-Object { $_.Urn }
        $urns += $db.Views | Where-Object { !$_.IsSystemObject } | ForEach-Object { $_.Urn }
        $urns += $db.Triggers | Where-Object { !$_.IsSystemObject } | ForEach-Object { $_.Urn }
        $urns += $db.Synonyms | ForEach-Object { $_.Urn }
        
        # --- Execute Scripting ---
        try {
            $scripter.EnumScript($urns)
            Add-SummaryEntry -Message "DDL successfully exported." -Status "SUCCESS" -Server $serverName -Database $dbName -FilePath $filePath
        }
        catch {
            Add-SummaryEntry -Message "DDL scripting failed: $($_.Exception.Message)" -Status "FAILURE" -Server $serverName -Database $dbName -FilePath $filePath
        }
    }
    
    # Close the connection
    $conn.Disconnect()
    Add-SummaryEntry -Message "Server connection disconnected." -Status "INFO" -Server $serverName
}

# --- 4. POST-PROCESSING AND REPORT GENERATION ---

# 1. Write structured log data to simple text log file
$SummaryData | ForEach-Object {
    "[$($_.Timestamp)] [$($_.Status)] Server: $($_.Server) | Database: $($_.Database) | FilePath: $($_.FilePath) | Message: $($_.Message)"
} | Out-File -FilePath $LogPath -Encoding UTF8

# 2. Generate HTML Summary
Generate-HtmlSummary -SummaryData $SummaryData -OutputDirectory $OutputDirectory -LogPath $LogPath

Add-SummaryEntry -Message "Process complete." -Status "INFO"

Write-Host "`nAll DDL files, the detailed log file, and the summary report have been saved to: $OutputDirectory" -ForegroundColor Cyan