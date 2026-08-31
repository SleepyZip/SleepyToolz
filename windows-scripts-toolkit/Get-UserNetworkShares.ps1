<#
Reads a user's persistent mapped network drives (drive letter + full UNC path).
Works live for the current session, or offline for a user profile that isn't
logged in (loads their registry hive directly). Export with -ExportPath and
feed the CSV into Set-UserNetworkShares.ps1 to replicate onto another user.
#>

param(
    [string]$Username = $env:USERNAME,
    [string]$ExportPath
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
    if (-not (Test-Path $ntUserDat)) {
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

if ($Username -eq $env:USERNAME) {
    $mappings = Get-MappingsFromKey "HKCU:\Network"
} else {
    $profilePath = "C:\Users\$Username"
    if (-not (Test-Path $profilePath)) {
        throw "No profile found for $Username at $profilePath"
    }
    Write-Output "Reading offline profile for $Username (they must not be currently logged in)..."
    $mappings = Get-OfflineMappings $profilePath
}

Write-Output "User: $Username"
Write-Output ""

if (-not $mappings) {
    Write-Output "No persistent mapped drives found."
    exit 0
}

$mappings | Format-Table -AutoSize

if ($ExportPath) {
    $mappings | Export-Csv -Path $ExportPath -NoTypeInformation
    Write-Output "Exported to $ExportPath"
}
