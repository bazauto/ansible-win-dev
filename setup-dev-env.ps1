# ==============================
# setup-dev-env.ps1
# Idempotent bootstrap Windows for Ansible + Podman + Devcontainer
# ==============================

# Accept a -WhatIf switch so users can preview what the script would change without making changes.
param(
    [switch]$WhatIf,
    [switch]$AdminPhase,
    [switch]$NoWait,
    [string]$SentinelPath
)

$wslDistro = "Debian"  # Name of the WSL distro to install/use

function Test-IsElevated {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-StringMatch {
    param (
        [string]$string,
        [string]$pattern
    )
    $clean = ($string.ToCharArray() | Where-Object { [int]$_ -ne 0 }) -join ''
    return $clean -match $pattern
}

function Test-StringNotMatch {
    param (
        [string]$string,
        [string]$pattern
    )
    $clean = ($string.ToCharArray() | Where-Object { [int]$_ -ne 0 }) -join ''
    return $clean -notmatch $pattern
}

function Invoke-AdminPhase {
    param([switch]$WhatIf, [string]$SentinelPath)

    # 1. Enable WSL and Virtual Machine Platform (skip if already enabled)
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    if ($wslFeature.State -ne "Enabled") {
        Write-Host "Enabling WSL..."
        if ($WhatIf) { Write-Host "WhatIf: would run dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart" } else { dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart }
    }
    else { Write-Host "WSL already enabled." }

    $vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
    if ($vmFeature.State -ne "Enabled") {
        Write-Host "Enabling Virtual Machine Platform..."
        if ($WhatIf) { Write-Host "WhatIf: would run dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart" } else { dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart }
    }
    else { Write-Host "Virtual Machine Platform already enabled." }

    # 2. Set WSL2 as default (no need to check, running this multiple times is safe)
    if ($WhatIf) { Write-Host "WhatIf: would run 'wsl --set-default-version 2'" } else { wsl --set-default-version 2 }

    # Write sentinel to signal completion (0 = success). If SentinelPath not provided, skip.
    Write-Host "Admin phase completed. Writing sentinel file if specified. (Path: $SentinelPath)"
    if (-not [string]::IsNullOrWhiteSpace($SentinelPath)) {
        try {
            Set-Content -Path $SentinelPath -Value "0" -Force -ErrorAction Stop
        }
        catch {
            # Give the user a chance to see the error if we fail to write the sentinel
            Write-Host "Failed to write sentinel file: $($_.Exception.Message)"
            Pause
        }
    }
}

function Invoke-PostAdminUserPhase {
    param([switch]$WhatIf)

    # Install components that can run as a normal user (per-user VS Code install)
    $vsCodePath = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"
    if (-Not (Test-Path $vsCodePath)) {
        Write-Host "Installing VS Code (per-user)..."
        $vsixUrl = "https://update.code.visualstudio.com/latest/win32-x64/stable"
        $vsixInstaller = "$env:TEMP\VSCodeSetup.exe"
        if ($WhatIf) {
            Write-Host "WhatIf: would download VS Code installer from $vsixUrl to $vsixInstaller and run installer silently"
        }
        else {
            Invoke-WebRequest -Uri $vsixUrl -OutFile $vsixInstaller
            Start-Process -FilePath $vsixInstaller -ArgumentList "/silent" -Wait
            Remove-Item $vsixInstaller
        }
    }
    else { Write-Host "VS Code already installed." }

    # Install Dev Containers extension if not present
    # Try the modern and legacy extension IDs to be safe
    $devContainerIds = @('ms-vscode-remote.remote-containers')
    # Locate the 'code' CLI: prefer the installed VS Code bin path, fall back to PATH
    $codeCli = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'
    if (-not (Test-Path $codeCli)) { $codeCli = 'code' }
    $installedExts = $null
    try {
        $installedExts = & $codeCli --list-extensions 2>$null
    } catch {
        Write-Host "Could not run 'code --list-extensions' to check installed extensions. Ensure the VS Code CLI is available on PATH or installed with the desktop app."
    }
    $needInstall = $false
    foreach ($id in $devContainerIds) {
        if (-not [string]::IsNullOrWhiteSpace($installedExts) -and $installedExts -match [regex]::Escape($id)) {
            Write-Host "Dev Containers extension ($id) already installed."
            $needInstall = $false
            break
        } else {
            $needInstall = $true
        }
    }
    if ($needInstall) {
        Write-Host "Installing VS Code Dev Containers extension..."
        $chosenId = $devContainerIds[0]
        if ($WhatIf) { Write-Host "WhatIf: would run '$codeCli --install-extension $chosenId'" } else { & $codeCli --install-extension $chosenId }
    }

    # Configure Dev Containers extension to use Podman in user settings
    $settingsPath = Join-Path $env:APPDATA 'Code\User\settings.json'
    $backupPath = "$settingsPath.bak"
    $settingsObj = @{}
    if (Test-Path $settingsPath) {
        try {
            $raw = Get-Content -Raw -Path $settingsPath -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $settingsObj = $raw | ConvertFrom-Json -ErrorAction Stop -AsHashtable
            } else { $settingsObj = @{} }
        } catch {
            Write-Host "Warning: could not parse existing settings.json. Will overwrite. Error: $($_.Exception.Message)"
            $settingsObj = @{ }
        }
    }

    # Set sensible keys to point the Dev Containers extension at Podman
    $settingsObj.'dev.containers.dockerPath' = 'podman'
    $settingsObj.'remote.containers.dockerPath' = 'podman'
    # Use typical Podman socket path inside WSL user (adjust if different)
    $settingsObj.'docker.host' = 'unix:///run/user/1000/podman/podman.sock'

    if ($WhatIf) {
        Write-Host "WhatIf: would update VS Code user settings at $settingsPath to prefer Podman for Dev Containers (backup $backupPath)"
    } else {
        try {
            if (Test-Path $settingsPath) { Copy-Item -Path $settingsPath -Destination $backupPath -Force }
            $settingsObj | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8
            Write-Host "Updated VS Code user settings to prefer Podman for Dev Containers (backup at $backupPath)"
        } catch {
            Write-Host "Failed to update VS Code settings: $($_.Exception.Message)"
        }
    }

    # 3. Install Debian 13 WSL if not already installed
    $installedDistros = wsl --list --quiet 2>$null
    $installedDistros = ($installedDistros -split "`n" | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($installedDistros) -or (Test-StringNotMatch -string $installedDistros -pattern "$wslDistro")) {
        Write-Host "Installing Debian 13 WSL..."
        if ($WhatIf) { Write-Host "WhatIf: would run 'wsl --install -d $wslDistro'" } else { wsl --install -d $wslDistro }
    }
    else { Write-Host "$wslDistro WSL already installed." }

    # 4. Launch WSL once to initialize
    Write-Host "Initializing WSL (user phase)"
    if ($WhatIf) { Write-Host "WhatIf: would run 'wsl -d $wslDistro -- echo \"Initializing WSL\"'" } else { wsl -d $wslDistro -- echo "Initializing WSL" }

    # 5. Install Podman inside WSL if not installed
    $podmanCheck = wsl -d $wslDistro -- bash -c "command -v podman || echo 'missing'"
    if ([string]::IsNullOrWhiteSpace($podmanCheck) -or (Test-StringMatch -string $podmanCheck -pattern "missing")) {
        Write-Host "Installing Podman..."
        if ($WhatIf) { Write-Host "WhatIf: would run apt update and install podman/curl/git inside WSL" } else { wsl -d $wslDistro -- bash -c "sudo apt update && sudo apt install -y podman curl git sudo lsb-release dos2unix" }
    }
    else { Write-Host "Podman already installed." }

    # 6. Create init script if not exists
    $scriptPath = "/usr/local/bin/start-podman.sh"
    $scriptExists = wsl -d $wslDistro -- bash -lc "if test -f '$scriptPath'; then echo exists; else echo missing; fi"
    if ([string]::IsNullOrWhiteSpace($scriptExists) -or $scriptExists -eq "missing") {
        Write-Host "Creating Podman init script..."
        $scriptContent = @"
#!/usr/bin/bash
PODMAN_SOCK="/run/user/1000/podman/podman.sock"
mkdir -p /run/user/1000/podman
if [ ! -S "\`$PODMAN_SOCK" ]; then
    echo "Starting Podman system service..."
    nohup podman system service -t 0 &>/dev/null &
else
    echo "Podman system service already running."
fi
"@
        if ($WhatIf) {
            Write-Host "WhatIf: would create $scriptPath inside WSL with provided script content and chmod +x"
        }
        else {
            wsl -d $wslDistro -- bash -c "echo '$scriptContent' | dos2unix | sudo tee $scriptPath"
            wsl -d $wslDistro -- sudo chmod +x $scriptPath
        }
    }
    else { Write-Host "Podman init script already exists." }

    # 7. Add to .bashrc if not already present
    $bashrcCheck = wsl -d $wslDistro -- bash -lc "if grep -Fxq '$scriptPath' ~/.bashrc; then echo exists; else echo missing; fi"
    if ([string]::IsNullOrWhiteSpace($bashrcCheck) -or $bashrcCheck -eq "missing") {
        Write-Host "Adding Podman auto-start to .bashrc..."
        if ($WhatIf) { Write-Host "WhatIf: would append $scriptPath to ~/.bashrc inside WSL" } else { wsl -d $wslDistro -- bash -c "echo '$scriptPath' >> ~/.bashrc" }
    }
    else { Write-Host ".bashrc already configured for Podman auto-start." }


}


# Dispatch phases: run user pre-admin tasks, then admin phase (elevated) if requested, then user post-admin tasks.
# Default behaviour: run user pre-admin, then prompt/auto-elevate to run admin phase, then run post-admin.
if (-not $AdminPhase) {

    # Now run admin phase by auto-elevating so the system changes can be applied.
    if (Test-IsElevated) {
        Invoke-AdminPhase -WhatIf:$WhatIf
    }
    else {
        if ($WhatIf) {
            Write-Host "WhatIf: would need elevation to run system-level changes (WSL feature enable, set default, install distro)."
        }
        else {
            Write-Host "Requesting elevation to run admin phase..."
            $script = $MyInvocation.MyCommand.Definition

            # Create a sentinel path in the temp folder if not provided
            if (-not $SentinelPath) { $SentinelPath = Join-Path -Path $env:TEMP -ChildPath "ansible-win-dev-admin-sentinel.txt" }
            $sentinelArg = "-SentinelPath `"$SentinelPath`""

            if ($WhatIf) { $whatIfArg = '-WhatIf' } else { $whatIfArg = '' }
            $adminArg = '-AdminPhase'

            try {
                $pwshPath = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
                if ($pwshPath) {
                    $pwshArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" $whatIfArg $adminArg $sentinelArg"
                    if ($NoWait) { $pwshArgs += " -NoWait" }
                    $proc = Start-Process -FilePath $pwshPath -ArgumentList $pwshArgs -Verb RunAs -PassThru -ErrorAction Stop
                }
                else {
                    Write-Host "Unable to find the 'pwsh' executable for elevation. Please ensure PowerShell 7+ is installed and in your PATH."
                    Exit 1
                }
            }
            catch {
                Write-Host "Elevation was cancelled or failed: $($_.Exception.Message)"
                Exit 1
            }

            if ($null -ne $proc) {
                if ($NoWait) {
                    Write-Host "Launched elevated admin phase (PID $($proc.Id)). Not waiting due to -NoWait. Run in watch mode using -RunPostAdmin -SentinelPath $SentinelPath to run post-admin steps when complete."
                    Exit 0
                }
                Write-Host "Waiting for elevated admin phase (PID $($proc.Id)) to complete..."
                # Instead of waiting on process (which may not be possible across sessions), poll for sentinel
                Write-Host "Waiting for sentinel file $SentinelPath to appear..."
                $timeoutSeconds = 300  # 5 minutes timeout
                $elapsed = 0
                while (-not (Test-Path $SentinelPath) -and $elapsed -lt $timeoutSeconds) {
                    if ($proc.HasExited) {
                        Write-Host "Admin phase process exited before sentinel file appeared. Exit code: $($proc.ExitCode)"
                        Exit $proc.ExitCode
                    }
                    Start-Sleep -Seconds 2
                    $elapsed += 2
                }
                if (-not (Test-Path $SentinelPath)) {
                    Write-Host "Timed out waiting for sentinel file ($SentinelPath) after $timeoutSeconds seconds. Admin phase may have failed."
                    if ($proc -and -not $proc.HasExited) {
                        try { $proc.Kill() } catch {}
                    }
                    Exit 1
                }
                $content = Get-Content -Path $SentinelPath -ErrorAction SilentlyContinue
                $exitCode = 0
                if ($content -and ([int]::TryParse($content, [ref]$null))) { $exitCode = [int]$content }
                if ($exitCode -ne 0) {
                    Write-Host "Admin phase finished with exit code $exitCode. Aborting post-admin steps."
                    Exit $exitCode
                }
                else {
                    Write-Host "Admin phase completed successfully. Continuing with user post-admin tasks."
                }
            }
            else {
                Write-Host "Failed to start elevated admin process. Aborting."
                Exit 1
            }
        }
    }

    # After admin phase, run post-admin user tasks
    Invoke-PostAdminUserPhase -WhatIf:$WhatIf

    # Ensure the sentinel file is removed after use
    if (Test-Path $SentinelPath) {
        try {
            Remove-Item -Path $SentinelPath -Force -ErrorAction Stop
        }
        catch {
            Write-Host "Failed to remove sentinel file: $($_.Exception.Message)"
        }
    }
}
else {
    # AdminPhase invoked (either by auto-elevate or user explicitly) - ensure we're elevated
    if (-not (Test-IsElevated)) {
        Write-Host "AdminPhase requires elevation. Please run PowerShell as Administrator or allow the elevation prompt."
        Exit 1
    }
    Invoke-AdminPhase -WhatIf:$WhatIf -SentinelPath:$SentinelPath
}
