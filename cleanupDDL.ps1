# Define the target directory
$targetDirectory = "C:\DDL_EXPORTER\DDLS"

# Check if the directory exists before proceeding
if (Test-Path -Path $targetDirectory) {
    
    # Get all .sql files in the directory
    $sqlFiles = Get-ChildItem -Path $targetDirectory -Filter "*.sql"

    foreach ($file in $sqlFiles) {
        Write-Host "Processing file: $($file.Name)"

        # Read the content of the file
        $content = Get-Content -Path $file.FullName

        # Process each line
        $newContent = $content | ForEach-Object {
            # Check if the line starts with CREATE ROLE or ALTER DATABASE (ignoring case and leading whitespace)
            if ($_ -match '^\s*(CREATE ROLE|ALTER DATABASE)') {
                # Comment out the line
                "-- " + $_
            } else {
                # Return the line as is
                $_
            }
        }

        # Save the modified content back to the file
        $newContent | Set-Content -Path $file.FullName -Force
    }

    Write-Host "All files processed successfully." -ForegroundColor Green
} else {
    Write-Error "Directory $targetDirectory does not exist."
}