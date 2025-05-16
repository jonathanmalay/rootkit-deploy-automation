<#
.SYNOPSIS
    Prepares the debugee machine to accept remote driver deployment via WinRM.

.DESCRIPTION
    Enables PowerShell Remoting, opens required firewall ports,
    and sets WSMan settings for Basic auth and unencrypted transport,
    using registry edits to bypass Public network restrictions.
    Automatically elevates if not running as Administrator.

.NOTES
    For lab/test environments only. Do not use in production as-is.
#>

# Auto-elevate if not running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
    Write-Host "[!] Elevating script to run as Administrator..." -ForegroundColor Yellow
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "`n======== PREPARING DEBUGEE FOR REMOTE DEPLOYMENT ========" -ForegroundColor White


# Step 0: Set all networks to Private
try {
    Write-Host "[+] Changing all 'Public' networks to 'Private'..." -ForegroundColor Cyan
    $profiles = Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' }
    foreach ($profile in $profiles) {
        Set-NetConnectionProfile -InterfaceIndex $profile.InterfaceIndex -NetworkCategory Private
        Write-Host "    → '$($profile.Name)' set to Private." -ForegroundColor Green
    }
}
catch {
    Write-Warning "[-] Failed to change network category: $_"
}


# Step 1: Enable PS Remoting (skipping network profile checks)
try {
    Write-Host "[+] Enabling PowerShell Remoting..." -ForegroundColor Cyan
    Enable-PSRemoting -SkipNetworkProfileCheck -Force
    Write-Host "[+] PowerShell Remoting enabled." -ForegroundColor Green
}
catch {
    Write-Error "[-] Failed to enable PowerShell Remoting: $_"
    exit 1
}

# Step 2: Add firewall rule for port 5985 (WinRM over HTTP)
try {
    Write-Host "[+] Creating firewall rule for WinRM (Public profile)..." -ForegroundColor Cyan
    New-NetFirewallRule -Name "WinRM_Public" `
        -DisplayName "WinRM Public Access" `
        -Enabled True `
        -Direction Inbound `
        -Profile Public `
        -Action Allow `
        -Protocol TCP `
        -LocalPort 5985 -ErrorAction Stop
    Write-Host "[+] Firewall rule created." -ForegroundColor Green
}
catch {
    Write-Warning "[!] Firewall rule may already exist or failed: $_"
}

# Step 3: Configure WSMan via registry to avoid firewall exceptions
try {
    Write-Host "[+] Configuring WSMan to allow Basic Auth + unencrypted traffic for the winrm server..." -ForegroundColor Cyan

    # Set-Item -Path WSMan:\localhost\Client\AllowUnencrypted -Value $true
    # Set-Item -Path WSMan:\localhost\Client\Auth\Basic -Value $true

    winrm set winrm/config/service '@{AllowUnencrypted="true"}';
    winrm set winrm/config/service/auth '@{Basic="true"}';

    # NOT WORKING   Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Service" -Name "AllowUnencrypted" -Value 1


    Write-Host "[+] WSMan configuration applied via registry." -ForegroundColor Green
}
catch {
    Write-Error "[-] Failed to configure WSMan via registry: $_"
}

# Step 4: Restart WinRM
try {
    Write-Host "[+] Restarting WinRM service..." -ForegroundColor Cyan
    Restart-Service WinRM
    Write-Host "[+] WinRM restarted." -ForegroundColor Green
}
catch {
    Write-Error "[-] Failed to restart WinRM: $_"
    exit 1
}

Write-Host "======== DEBUGEE IS READY FOR REMOTE DEPLOYMENT ========" -ForegroundColor White

