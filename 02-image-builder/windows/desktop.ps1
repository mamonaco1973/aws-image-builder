try {
    # Customize Desktop Icons

    # Remove EC2 Tools - End Users don't need them on the desktop.
    # Server 2022 ships them as .website files on Administrator's desktop;
    # Server 2025 ships .url files and also puts them in the Default
    # profile, which every new user (builder included) is copied from.

    Remove-Item -Path "C:\Users\Administrator\Desktop\EC2*.website",
                      "C:\Users\Administrator\Desktop\EC2*.url",
                      "C:\Users\Default\Desktop\EC2*.website",
                      "C:\Users\Default\Desktop\EC2*.url" `
                -Force -ErrorAction SilentlyContinue

    # Turn off the EC2Launch v2 instance-info wallpaper (hostname, instance
    # ID, IP addresses). It is a setWallpaper task in agent-config.yml that
    # the EC2Launch service runs on every boot, so remove the task, then
    # delete the image it already rendered on the build instance.

    $ec2launch = "C:\Program Files\Amazon\EC2Launch\EC2Launch.exe"
    $config = "C:\ProgramData\Amazon\EC2Launch\config\agent-config.yml"

    $text = [IO.File]::ReadAllText($config)

    # The task block ends at the next task at its own indent or the next
    # stage, whichever comes first.
    $pattern = '(?ms)^([ \t]*)- task: setWallpaper\r?\n' +
               '.*?(?=^\1- task:|^[ \t]*- stage:|\z)'
    $updated = [regex]::Replace($text, $pattern, '')

    if ($updated -match 'setWallpaper') {
        throw "setWallpaper is still in $config."
    }

    # WriteAllText writes UTF-8 without a byte order mark.
    [IO.File]::WriteAllText($config, $updated)

    & $ec2launch validate
    if ($LASTEXITCODE -ne 0) {
        throw "EC2Launch rejected the edited $config."
    }

    Remove-Item -Path "C:\ProgramData\Amazon\EC2Launch\wallpaper\*.jpg" `
                -Force -ErrorAction SilentlyContinue

    Write-Host "EC2Launch wallpaper task removed."
}
catch {
    Write-Error "An error occurred configuring the desktop: $_"
    exit 1
}
