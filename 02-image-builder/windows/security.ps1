# Ensure the script stops on all errors
$ErrorActionPreference = "Stop"

try {
    Write-Host "Starting local user creation and group assignment..." -ForegroundColor Cyan

    # Read the password from the BUILDER_PASSWORD environment variable
    $envPassword = [Environment]::GetEnvironmentVariable("BUILDER_PASSWORD")

    # Exit with error if BUILDER_PASSWORD is not set or empty
    if ([string]::IsNullOrWhiteSpace($envPassword)) {
        Write-Error "Environment variable 'BUILDER_PASSWORD' is not set or empty."
        exit 1
    }

    # Convert plain text password to secure string
    $securePassword = ConvertTo-SecureString $envPassword -AsPlainText -Force

    # Create the local user 'builder' with the password, if it doesn't already exist
    if (-Not (Get-LocalUser -Name "builder" -ErrorAction SilentlyContinue)) {
        New-LocalUser -Name "builder" `
                      -Password $securePassword `
                      -FullName "Builder User" `
                      -Description "Local user created by Image Builder" `
                      -PasswordNeverExpires
        Write-Host "User 'builder' created successfully."
    } else {
        Write-Host "User 'builder' already exists. Skipping creation."
    }

    # Add the user to the Administrators group
    Add-LocalGroupMember -Group "Administrators" -Member "builder"
    Write-Host "User 'builder' added to Administrators group."

    # Add the user to the Remote Desktop Users group
    Add-LocalGroupMember -Group "Remote Desktop Users" -Member "builder"
    Write-Host "User 'builder' added to Remote Desktop Users group."

    Write-Host "User setup completed successfully." -ForegroundColor Green
}
catch {
    Write-Error "An error occurred while setting up the 'builder' user: $_"
    exit 1
}
