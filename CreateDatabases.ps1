<#
.SYNOPSIS
Executes all .sql files in a directory against a specified SQL Server database.

.DESCRIPTION
This script iterates through all files with the .sql extension in the 
specified directory (non-recursive by default). For each file, it uses 
the 'sqlcmd.exe' utility to execute the script's contents against the 
target SQL Server and database.

Authentication is flexible:
- If both -SqlUsername and -SqlPassword are provided, SQL Server Authentication is used.
- Otherwise, Windows Integrated Security is used by default.

.PARAMETER SqlDirectory
The path to the directory containing the .sql files to execute.

.PARAMETER ServerName
The name or IP address of the SQL Server instance (e.g., '.\SQLEXPRESS' or 'SERVER01').

.PARAMETER DatabaseName
The name of the database to execute the scripts against.

.PARAMETER SqlUsername
(Optional) The SQL Server login username for SQL Authentication.

.PARAMETER SqlPassword
(Optional) The SQL Server login password for SQL Authentication.

.EXAMPLE
# 1. Execute using Windows Integrated Security (Default)
.\Execute-SqlScripts.ps1 `
    -SqlDirectory 'C:\Deployment\SQL' `
    -ServerName 'DB-SERVER-01' `
    -DatabaseName 'MyDatabase'

.EXAMPLE
# 2. Execute using SQL Server Authentication
.\Execute-SqlScripts.ps1 `
    -SqlDirectory 'C:\Deployment\SQL' `
    -ServerName 'DB-SERVER-01' `
    -DatabaseName 'MyDatabase' `
    -SqlUsername 'SqlUser' `
    -SqlPassword 'P@sswOrd123'

.NOTES
Ensure 'sqlcmd.exe' is available in your system's PATH. This is usually 
installed with SQL Server Management Studio (SSMS) or SQL Server utilities.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$SqlDirectory,

    [Parameter(Mandatory=$true)]
    [string]$ServerName,

    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,

    [string]$SqlUsername,

    [string]$SqlPassword
)

# -------------------------------------------------------------------------------------
# Function to check for sqlcmd.exe availability
# -------------------------------------------------------------------------------------
function Test-SqlCmd
{
    if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
        Write-Error "Error: 'sqlcmd.exe' command not found. Please ensure SQL Server tools are installed and in your system PATH."
        exit 1
    }
}

# -------------------------------------------------------------------------------------
# Execution
# -------------------------------------------------------------------------------------
Test-SqlCmd

if (-not (Test-Path -Path $SqlDirectory -PathType Container)) {
    Write-Error "Error: The specified directory '$SqlDirectory' does not exist."
    exit 1
}

# Determine Authentication Method
$authType = "Windows Integrated Security (-E)"
$authArguments = @("-E")

if ($SqlUsername -and $SqlPassword) {
    # Use SQL Authentication if both username and password are provided
    $authType = "SQL Server Authentication (-U, -P)"
    $authArguments = @(
        "-U", $SqlUsername,
        "-P", $SqlPassword
    )
    Write-Host "WARNING: Providing passwords directly as a parameter is insecure. Consider using SecureString for production environments." -ForegroundColor Yellow
}


Write-Host "Starting execution of SQL scripts..."
Write-Host "Target Server: $ServerName"
Write-Host "Target Database: $DatabaseName"
Write-Host "Authentication Method: $authType"
Write-Host "------------------------------------"

# Retrieve all .sql files in the directory.
# Use '-Recurse' if you need to execute files in subdirectories as well.
$sqlFiles = Get-ChildItem -Path $SqlDirectory -Filter "*.sql" -File | Sort-Object Name

if ($sqlFiles.Count -eq 0) {
    Write-Host "No .sql files found in '$SqlDirectory'. Exiting." -ForegroundColor Yellow
    exit 0
}

foreach ($file in $sqlFiles) {
    $filePath = $file.FullName
    Write-Host "Executing script: $($file.Name)..."

    # Construct the sqlcmd command arguments, combining standard and authentication arguments
    $arguments = @(
        "-S", $ServerName, 
        "-d", $DatabaseName, 
        "-i", $filePath 
    ) + $authArguments # Append the chosen authentication arguments

    # Execute the command and capture the result
    $process = Start-Process -FilePath sqlcmd -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    
    # sqlcmd returns 0 on success.
    if ($process.ExitCode -eq 0) {
        Write-Host "SUCCESS: $($file.Name) executed successfully." -ForegroundColor Green
    } else {
        # Note: sqlcmd errors are typically printed directly to the console by the utility itself.
        Write-Error "FAILURE: $($file.Name) execution failed (Exit Code $($process.ExitCode)). Check console output for SQL errors."
    }
    Write-Host "------------------------------------"
}

Write-Host "All scripts processed. Execution complete."