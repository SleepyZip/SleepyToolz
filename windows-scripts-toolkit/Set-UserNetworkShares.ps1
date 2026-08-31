<#
Applies a set of network drive mappings (from Get-UserNetworkShares.ps1's
-ExportPath CSV) to a target user - the "replicate this user's shares onto
that user" half of the pair. Works live for the current session, or offline
for a user profile that isn't logged in.
#>

param(
    [Parameter(Mandatory)]
    [string]$CsvPath,
    [string]$Username = $env:USERNAME
)

try {
    $mappings = Import-Csv $CsvPath
    if (-not $mappings) {
        Write-Output "No mappings found in $CsvPath"
    } elseif ($Username -eq $env:USERNAME) {
        foreach ($m in $mappings) {
            $letter = $m.DriveLetter.TrimEnd(':')
            Write-Output "Mapping $($m.DriveLetter) -> $($m.RemotePath)"
            New-PSDrive -Name $letter -PSProvider FileSystem -Root $m.RemotePath -Persist -Scope Global -ErrorAction SilentlyContinue | Out-Null
        }
        Write-Output "Done. Mapped for current user ($Username)."
    } else {
        $profilePath = "C:\Users\$Username"
        $ntUserDat = Join-Path $profilePath "NTUSER.DAT"
        if (-not (Test-Path $ntUserDat)) {
            throw "Could not find NTUSER.DAT for $Username - check the username, and that the profile exists."
        }

        $hiveName = "TempHive_$(Get-Random)"
        $result = reg load "HKU\$hiveName" $ntUserDat 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Could not load registry hive - $Username may still be logged in. Details: $result"
        }

        try {
            foreach ($m in $mappings) {
                $letter = $m.DriveLetter.TrimEnd(':')
                $keyPath = "Registry::HKEY_USERS\$hiveName\Network\$letter"
                New-Item -Path $keyPath -Force | Out-Null
                Set-ItemProperty -Path $keyPath -Name "RemotePath" -Value $m.RemotePath
                Set-ItemProperty -Path $keyPath -Name "ProviderName" -Value "Microsoft Windows Network"
                Set-ItemProperty -Path $keyPath -Name "ConnectionType" -Value 1
                Write-Output "Mapping $($m.DriveLetter) -> $($m.RemotePath) written to $Username's profile"
            }
            Write-Output "Done. $Username will have these drives mapped at next sign-in."
        } finally {
            [gc]::Collect()
            reg unload "HKU\$hiveName" | Out-Null
        }
    }
} catch {
    Write-Output "Error: $_"
} finally {
    # Keeps the window open if launched by double-click or "Run with PowerShell",
    # both of which close the console the instant the script finishes.
    if ($Host.Name -eq "ConsoleHost") {
        Write-Output "`nPress any key to close..."
        try {
            [Console]::ReadKey($true) | Out-Null
        } catch {
            Start-Sleep -Seconds 15
        }
    }
}