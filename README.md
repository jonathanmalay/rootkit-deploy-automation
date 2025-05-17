# 🔧 Windows Driver Remote Deployment & Debugging Scripts

This repository contains two PowerShell scripts designed to streamline the deployment and setup of a Windows kernel-mode driver across two machines: the **debugger** (your development machine) and the **debugee** (the test machine running the driver). These scripts support kernel driver testing workflows typically used in virtualized environments (e.g., VMware).

### 👨‍💼 Author

Created by Yonathan Malay
Intended for kernel driver testing, red team R\&D, and lab automation.

---

![Demo](demo.gif)


## 👥 System Roles

| Role     | Description                                                  |
| -------- | ------------------------------------------------------------ |
| Debugger | Your development machine (running Visual Studio)             |
| Debugee  | Remote test machine where the driver is deployed and started |

---

## 📜 Script Overview

### ✅ 1. `deploy-to-debugge.ps1` (👥 Debugger-side)

This script is triggered **post-build** from Visual Studio on the debugger machine.

**What it does:**

* Ensures **WinRM** is enabled and reachable
* Copies built driver files to the remote debugee
* Stops and deletes the existing driver service (if it exists)
* Recreates and starts the driver as a service

**Arguments:**

| Parameter      | Description                                       |
| -------------- | ------------------------------------------------- |
| `-remoteHost`  | IP/hostname of the debugee                        |
| `-serviceName` | Name of the driver service                        |
| `-remoteDir`   | Target folder path on the debugee for placing the |
|                  driver .sys and .pdb (must be valid path)         |
|                                                                    |
| `-username`    | Username to authenticate to the remote machine    |
| `-password`    | Password for the remote account (plain text)      |

**Example usage (post-build in Visual Studio):**

```cmd
powershell.exe -ExecutionPolicy Bypass -File "D:\Path\To\deploy-to-debugge.ps1" -remoteHost 192.168.232.129 -serviceName Tyrootkit -remoteDir "C:\Users\test\Desktop\run\" -username "testuser" -password "testpass"
```

---

### ✅ 2. `prepare-debugee.ps1` (👥 Debugee-side)
Firstly, you need to run the prepare-debugee.ps1 script on the debuggee machine.
This script should be run **once on the debugee machine** to prepare it for receiving the driver over WinRM.

**What it does:**

* Enables **PowerShell Remoting** even if the network is `Public`
* Opens **TCP port 5985** in Windows Firewall
* Enables **Basic authentication** and allows **unencrypted** traffic (for lab use)
* Restarts **WinRM** service
* Automatically **elevates to Administrator** if needed

**Usage:**

```powershell
.\prepare-debugee.ps1
```

**Run it as Administrator (the script now auto-elevates if not).**

---

## 📁 Folder Structure

```text
ProjectRoot/
│
├── Build/                      # Driver output folder from Visual Studio
├── deploy-to-debugge.ps1       # Run on debugger (Visual Studio post-build)
├── prepare-debugee.ps1         # Run on debugee once to enable remote access
├── README.md                   # This file
```


---

## Integrating as a Git Submodule

If you'd like to reuse these scripts across multiple projects, you can include them via Git submodules.

### 📦 Add as Submodule

From your existing project root, run:

```bash
git submodule add https://github.com/jonathanmalay/rootkit-deploy-automation.git deployment/shared
```

This will clone the deployment scripts into the `deployment/shared` directory of your current repository.

### 🔄 Keep Submodule Updated

To fetch the latest version of the submodule later:

from the root dir of your git repo:
```bash
git submodule update --remote --merge --recursive
```

Alternatively, you can run this from the root of your main repo:

```cmd
cd deployment/shared
git fetch origin main
git reset --hard origin/main
cd ../..
git add deployment/shared
git commit -m "Update deployment scripts"
```

### ⚙ Visual Studio Post-Build Integration

After adding the submodule, you can use the following post-build event in Visual Studio:

1. Go to your project properties
2. add the following post build event command:
```cmd
powershell -ExecutionPolicy Bypass -File "$(SolutionDir)deployment\shared\deploy-to-debuggee.ps1" -username "youruser" -password "yourpass" -remoteHost "192.168.0.10" -serviceName "$(ProjectName)" -remoteDir "C:\RemotePath" -buildDir $(TargetDir)
```

---


## Security Notice

These scripts:

* Enable WinRM over HTTP (port 5985)
* Allow basic authentication
* Trust any remote host (`TrustedHosts = *`)
* May modify firewall and network profile

⚠ These settings are **insecure** in production environments.
Use only in **isolated labs or VM-based test networks**.

---

