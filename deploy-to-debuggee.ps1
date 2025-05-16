<#
.SYNOPSIS
    Post-build script to deploy a Windows driver to a remote host, install it as a service, and start it.

.DESCRIPTION
    This script sets up WinRM on the client, copies build artifacts to a remote machine using PowerShell Remoting,
    and installs a driver service with `sc.exe`. It is intended to be used from Visual Studio's post-build step.

.PARAMETER remoteHost
    IP or hostname of the remote Windows machine (the debugee).

.PARAMETER serviceName
    Name of the kernel-mode service to create and start (the rootkit name).

.PARAMETER remoteDir
    Full path on the remote machine to copy the driver to.

    
.PARAMETER buildDir
    Full path on the dev machine of the folder contains the .sys and pdb files.

.PARAMETER username
    Username to authenticate with the remote debugee machine.

.PARAMETER password
    Plain-text password for the remote user (pass securely in CI or dev scripts).

.EXAMPLE
   powershell -ExecutionPolicy Bypass -File "D:\Tyrootkit\deployment\shared\deploy-to-debuggee.ps1" -username "yonathan_malay" -password "1" -remoteHost "192.168.232.129" -serviceName "Tyrootkit" -remoteDir "C:\Users\yonathan_malay\Desktop\run" -buildDir D:\Tyrootkit\x64\Debug\
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$remoteHost,

    [Parameter(Mandatory = $true)]
    [string]$serviceName,

    [Parameter(Mandatory = $true)]
    [string]$remoteDir,
    
    [Parameter(Mandatory = $true)]
    [string]$buildDir, 

    [Parameter(Mandatory = $true)]
    [string]$username,

    [Parameter(Mandatory = $true)]
    [string]$password
)

# Convert plaintext password into SecureString
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($username, $securePassword)

function Configure-WinRMClient {
    Write-Host "[+] Configuring WinRM on client..." -ForegroundColor Cyan
    try {
        New-NetFirewallRule -Name "WinRM_Public" `
            -DisplayName "Allow WinRM on Public" `
            -Profile Public `
            -Enabled True `
            -Direction Inbound `
            -Action Allow `
            -Protocol TCP `
            -LocalPort 5985 -ErrorAction SilentlyContinue

        # Step 2: Enable and start WinRM
        Write-Host "`nConfiguring WinRM..." -ForegroundColor Cyan
        Set-Service -Name WinRM -StartupType Automatic
        Start-Service -Name WinRM
        # winrm quickconfig -q

        Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force ; 

        try {
            # $currentValue = Get-WSManInstance -ResourceURI winrm/config/service | Select-Object AllowUnencrypted
            
            # # if ( $currentValue.AllowUnencrypted -ne $true) {
            # #     Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true -Force
            # # }         

            
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Client" -Name "AllowUnencrypted" -Value 1
            Set-Item -Path WSMan:\localhost\Client\Auth\Basic -Value $true
            # Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Client\Auth" -Name "Basic" -Value 1
            Restart-Service WinRM ;
        }
        catch {
            Write-Warning  "[-] bypassing error of Allow Unencrypted" ;
        }

        Write-Host "WinRM unencrypted + Basic Auth enabled." -ForegroundColor Green ; 
        Write-Host "[+] WinRM configured successfully." -ForegroundColor Green ; 
    }
    catch {
        Write-Error "[-] Failed to configure WinRM: $_"
        exit 1
    }
}

function Copy-Artifacts {
    <#
    
        .SYNOPSIS
            Copy artifacts to target

        .OUTPUTS
        System.Management.Automation.Runspaces.PSSession
    #>
    param (
        [string]$localPath,
        [string]$remoteHost,
        [string]$remoteTempPath
    )

    Write-Host "[+] Creating remote session to $remoteHost..." -ForegroundColor Cyan
    $session = New-PSSession -ComputerName $remoteHost -Credential $cred -Authentication Basic -ErrorAction Stop
    $sourcePath = "$localPath*";

    try {
        Write-Host "[+] Copying files from '$sourcePath' to ${remoteHost}:$remoteTempPath..." -ForegroundColor Cyan
        Copy-Item -Path "$sourcePath" -Destination "$remoteTempPath" -ToSession $session -Recurse -Force
        Write-Host "[+] Files copied successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "[-] Failed to copy artifacts: $_"
        Remove-PSSession $session
        exit 1
    }

    return $session
}

function Install-DriverService {
    param (
        [string]$remoteHost,
        [string]$remoteTempPath,
        [string]$remoteDir,
        [string]$serviceName
 
    )

    try {
        Invoke-Command -ComputerName $remoteHost -Credential $cred -Authentication Basic -ScriptBlock {
            param($svc, $remoteDir, $remoteTempPath, $session)

            $binPath = "$remoteDir\$svc.sys"
            sc.exe stop $svc > $null 2>&1
            sc.exe delete $svc > $null 2>&1
            Write-Host "[+] Stopped and deleted any existing '$svc'" -ForegroundColor Green
            
            Copy-Item -Path "$remoteTempPath\$svc.*" -Destination $remoteDir  -Recurse -Force
            Write-Host "[+] Copied all artifacts from $remoteTempPath" -ForegroundColor Green


            Write-Host "[...] Creating service $svc..." -ForegroundColor Cyan
            sc.exe create $svc type=kernel binPath=$binPath
            Write-Host "[+] Service '$svc' created at '$binPath'" -ForegroundColor Green

            # Write-Host "[...] Starting service $svc..." -ForegroundColor Cyan
            # sc.exe start $svc
            # Write-Host "[+] Service started successfully." -ForegroundColor Green
        } -ArgumentList $serviceName, $remoteDir, $remoteTempPath
    }
    catch {
        Write-Error "[-] Failed to install/start service on remote host: $_"
        exit 1
    }
}

function Main {
    Write-Host "`n======== DRIVER DEPLOYMENT START ========" -ForegroundColor White

    # ─────────────────────────────────────────────────────────────────────
    # Auto-elevate if not running as Administrator
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
        Write-Host "[!] Elevating script to run as Administrator..." -ForegroundColor Yellow
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }


    # Step 1: Configure local WinRM
    Configure-WinRMClient

    # Step 2: Ping the target to ensure connectivity
    if (-not (Test-Connection -ComputerName $remoteHost -Count 1 -Quiet)) {
        Write-Error "[-] Remote host $remoteHost is unreachable... aborting..."
        exit 1
    }

    # Step 3: Copy files to the debugee
    $remoteTempPath = "C:\Temp"
    $session = Copy-Artifacts -localPath $buildDir -remoteHost $remoteHost -remoteTempPath $remoteTempPath

    # Step 4: Create/start the driver service
    Install-DriverService -remoteHost $remoteHost -remoteTempPath $remoteTempPath -remoteDir $remoteDir -serviceName $serviceName

    # Step 5: Cleanup
    Remove-PSSession $session
    Write-Host "======== DRIVER DEPLOYMENT COMPLETE ========" -ForegroundColor White
}

# Entry Point
Main
