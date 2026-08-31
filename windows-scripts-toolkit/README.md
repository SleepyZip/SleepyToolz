# Windows Scripts Toolkit

A small collection of PowerShell and batch scripts for common Windows IT
triage and maintenance tasks - the kind of thing you reach for on an
unfamiliar workstation or a routine cleanup pass.

## Scripts

| Script | What it does |
|---|---|
| `Get-SystemInfoReport.ps1` | Dumps OS/hardware/disk/network info and recently installed software to console or a file. First-response triage on any machine. |
| `Test-NetworkHealth.ps1` | Pings the gateway, DNS servers, and an external host, then runs a DNS resolution test. Summarizes what's actually broken instead of raw ping output. |
| `Clear-TempFiles.ps1` | Reports (and optionally clears, with `-Execute`) user/system temp folders and browser caches. Dry-run by default. |
| `Reset-NetworkStack.bat` | The classic release/renew/flush DNS/Winsock reset routine. Requires admin. |

## Usage

```powershell
# System report to console
.\Get-SystemInfoReport.ps1

# System report to a file
.\Get-SystemInfoReport.ps1 -OutFile report.txt

# Network health check
.\Test-NetworkHealth.ps1

# See what temp cleanup would remove, without deleting anything
.\Clear-TempFiles.ps1

# Actually clear it
.\Clear-TempFiles.ps1 -Execute
```

`Reset-NetworkStack.bat` just needs to be run as Administrator.

## Requirements

Windows PowerShell 5.1+ (built into Windows 10/11). No external dependencies.
