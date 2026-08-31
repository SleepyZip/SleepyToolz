<#
Reads a user's persistent mapped network drives (drive letter + full UNC path).
Works live for the current session, or offline for a user profile that isn't
logged in (loads their registry hive directly). Export with -ExportPath and
feed the CSV into Set-UserNetworkShares.ps1 to replicate onto another user.

Use -RecentUsers <N> instead of -Username to show shares for the last N users
who logged onto this machine, most recent first.
#>

param(
    [string]$Username = $env:USERNAME,
    [string]$ExportPath,
    [int]$RecentUsers
)

function Get-MappingsFromKey($KeyPath) {
    Get-ChildItem $KeyPath -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{
            DriveLetter = "$($_.PSChildName):"
            RemotePath  = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).RemotePath
        }
    }
}

function Get-OfflineMappings($ProfilePath) {
    $ntUserDat = Join-Path $ProfilePath "NTUSER.DAT"
    if (-not (Test-Path $ntUserDat -ErrorAction SilentlyContinue)) {
        throw "Could not find NTUSER.DAT at $ntUserDat - check the username, and that the profile exists."
    }

    $hiveName = "TempHive_$(Get-Random)"
    $result = reg load "HKU\$hiveName" $ntUserDat 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not load registry hive - the user may still be logged in. Details: $result"
    }

    try {
        Get-MappingsFromKey "Registry::HKEY_USERS\$hiveName\Network"
    } finally {
        [gc]::Collect()
        reg unload "HKU\$hiveName" | Out-Null
    }
}

function Show-UserShares($TargetUsername, $TargetExportPath) {
    if ($TargetUsername -eq $env:USERNAME) {
        $mappings = Get-MappingsFromKey "HKCU:\Network"
    } else {
        $profilePath = "C:\Users\$TargetUsername"
        if (-not (Test-Path $profilePath)) {
            Write-Output "  (no profile folder found for $TargetUsername)"
            return
        }
        try {
            $mappings = Get-OfflineMappings $profilePath
        } catch {
            Write-Output "  (skipped - $($_.Exception.Message))"
            return
        }
    }

    if (-not $mappings) {
        Write-Output "  No persistent mapped drives found."
    } else {
        $mappings | Format-Table -AutoSize | Out-String | Write-Output
        if ($TargetExportPath) {
            $mappings | Export-Csv -Path $TargetExportPath -NoTypeInformation
            Write-Output "  Exported to $TargetExportPath"
        }
    }
}

function Get-RecentUsernames($Count) {
    Get-CimInstance Win32_UserProfile |
        Where-Object { -not $_.Special -and $_.LocalPath -like "C:\Users\*" } |
        Sort-Object LastUseTime -Descending |
        Select-Object -First $Count |
        ForEach-Object {
            $name = $null
            try {
                $name = ([System.Security.Principal.SecurityIdentifier]$_.SID).Translate([System.Security.Principal.NTAccount]).Value -replace '^.*\\', ''
            } catch {
                $name = Split-Path $_.LocalPath -Leaf
            }
            [PSCustomObject]@{ Username = $name; LastUseTime = $_.LastUseTime }
        }
}

try {
    if ($RecentUsers -gt 0) {
        $recent = Get-RecentUsernames $RecentUsers
        if (-not $recent) {
            Write-Output "No recent user profiles found."
        }
        foreach ($u in $recent) {
            Write-Output "=== User: $($u.Username) (last used $($u.LastUseTime)) ==="
            Show-UserShares $u.Username $null
            Write-Output ""
        }
    } else {
        Write-Output "User: $Username"
        Write-Output ""
        if ($Username -ne $env:USERNAME) {
            Write-Output "Reading offline profile for $Username (they must not be currently logged in)..."
        }
        Show-UserShares $Username $ExportPath
    }
} catch {
    Write-Output "Error: $_"
} finally {
    # Keeps the window open if launched by double-click or "Run with PowerShell",
    # both of which close the console the instant the script finishes.
    # [Console]::ReadKey is used instead of Read-Host because "Run with PowerShell"
    # launches with -NonInteractive, which makes Read-Host throw instead of prompt.
    if ($Host.Name -eq "ConsoleHost") {
        Write-Output "`nPress any key to close..."
        try {
            [Console]::ReadKey($true) | Out-Null
        } catch {
            Start-Sleep -Seconds 15
        }
    }
}