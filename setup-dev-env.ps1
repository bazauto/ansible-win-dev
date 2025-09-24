# ==============================
# setup-dev-env.ps1
# Idempotent bootstrap Windows for Ansible + Podman + Devcontainer
# ==============================

# 1. Enable WSL and Virtual Machine Platform (skip if already enabled)
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
if ($wslFeature.State -ne "Enabled") {
    Write-Host "Enabling WSL..."
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
} else { Write-Host "WSL already enabled." }

$vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
if ($vmFeature.State -ne "Enabled") {
    Write-Host "Enabling Virtual Machine Platform..."
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
} else { Write-Host "Virtual Machine Platform already enabled." }

# 2. Set WSL2 as default (idempotent)
$wslVer = wsl --list --verbose | Select-String "Default Version"
if ($wslVer -notmatch "2") {
    Write-Host "Setting WSL2 as default..."
    wsl --set-default-version 2
} else { Write-Host "WSL2 is already default." }

# 3. Install Debian 13 WSL if not already installed
$installedDistros = wsl --list --quiet
if ($installedDistros -notmatch "Debian-Testing") {
    Write-Host "Installing Debian 13 WSL..."
    wsl --install -d Debian-Testing
} else { Write-Host "Debian-Testing WSL already installed." }

# 4. Launch WSL once to initialize
wsl -d Debian-Testing -- echo "Initializing WSL"

# 5. Install Podman inside WSL if not installed
$podmanCheck = wsl -d Debian-Testing -- bash -c "command -v podman || echo 'missing'"
if ($podmanCheck -match "missing") {
    Write-Host "Installing Podman..."
    wsl -d Debian-Testing -- bash -c "sudo apt update && sudo apt install -y podman curl git sudo lsb-release"
} else { Write-Host "Podman already installed." }

# 6. Create init script if not exists
$scriptPath = "/usr/local/bin/start-podman.sh"
$scriptExists = wsl -d Debian-Testing -- test -f $scriptPath && echo "exists" || echo "missing"
if ($scriptExists -eq "missing") {
    Write-Host "Creating Podman init script..."
    $scriptContent = @"
#!/bin/bash
PODMAN_SOCK="/run/user/1000/podman/podman.sock"
if [ ! -S "\$PODMAN_SOCK" ]; then
    echo "Starting Podman system service..."
    nohup podman system service -t 0 &>/dev/null &
else
    echo "Podman system service already running."
fi
"@
    wsl -d Debian-Testing -- bash -c "echo '$scriptContent' | sudo tee $scriptPath"
    wsl -d Debian-Testing -- sudo chmod +x $scriptPath
} else { Write-Host "Podman init script already exists." }

# 7. Add to .bashrc if not already present
$bashrcCheck = wsl -d Debian-Testing -- grep -Fxq $scriptPath ~/.bashrc && echo "exists" || echo "missing"
if ($bashrcCheck -eq "missing") {
    Write-Host "Adding Podman auto-start to .bashrc..."
    wsl -d Debian-Testing -- bash -c "echo '$scriptPath' >> ~/.bashrc"
} else { Write-Host ".bashrc already configured for Podman auto-start." }

# 8. Install VS Code if not installed
$vsCodePath = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"
if (-Not (Test-Path $vsCodePath)) {
    Write-Host "Installing VS Code..."
    $vsixUrl = "https://update.code.visualstudio.com/latest/win32-x64/stable"
    $vsixInstaller = "$env:TEMP\VSCodeSetup.exe"
    Invoke-WebRequest -Uri $vsixUrl -OutFile $vsixInstaller
    Start-Process -FilePath $vsixInstaller -ArgumentList "/silent" -Wait
    Remove-Item $vsixInstaller
} else { Write-Host "VS Code already installed." }

Write-Host "Bootstrap complete! Restart WSL or open a new terminal to activate Podman service."
