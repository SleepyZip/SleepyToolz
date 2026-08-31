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
| `Get-UserNetworkShares.ps1` | Reads a user's persistent mapped network drives (drive letter + full UNC path) from the registry. Works live for the current session or offline for a user who isn't logged in. Pass `-RecentUsers <N>` to show the last N users who logged onto the machine instead of one specific user. |
| `Set-UserNetworkShares.ps1` | Applies a set of mappings (from `Get-UserNetworkShares.ps1`'s CSV export) to another user - replicates one person's drive mappings onto a new hire or rebuilt profile. |

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

`Reset-NetworkStack.bat` just needs to be run as Administrator. `Get-/Set-UserNetworkShares.ps1` need admin rights too when targeting another user, since they load that user's registry hive directly.

```powershell
# Show your own username and mapped drives, no arguments needed
.\Get-UserNetworkShares.ps1

# Read another user's mapped drives (they must be logged off) and export them
.\Get-UserNetworkShares.ps1 -Username jsmith -ExportPath jsmith-shares.csv

# Apply that same set of drives to a new user (they must be logged off)
.\Set-UserNetworkShares.ps1 -CsvPath jsmith-shares.csv -Username newhire

# Show shares for the last 4 users who logged onto this machine
.\Get-UserNetworkShares.ps1 -RecentUsers 4
```

## Requirements

Windows PowerShell 5.1+ (built into Windows 10/11). No external dependencies.
