<#
Quick system triage report - pulls the info you'd normally have to click through
five different windows for, and prints it to the console (or a file with -OutFile).
Useful as a first step on any unfamiliar workstation.
#>

param(
    [string]$OutFile
)

function Get-Section($Title) {
    "`n=== $Title ==="
}

try {
    $report = [System.Collections.Generic.List[string]]::new()

    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS

    $report.Add((Get-Section "System"))
    $report.Add("Computer Name : $($cs.Name)")
    $report.Add("Manufacturer  : $($cs.Manufacturer)")
    $report.Add("Model         : $($cs.Model)")
    $report.Add("Serial Number : $($bios.SerialNumber)")
    $report.Add("OS            : $($os.Caption) (Build $($os.BuildNumber))")
    $report.Add("Uptime        : $([math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)) hours")
    $report.Add("Domain/Group  : $($cs.Domain) (PartOfDomain: $($cs.PartOfDomain))")

    $report.Add((Get-Section "Hardware"))
    $report.Add("CPU           : $($cpu.Name)")
    $report.Add("Cores/Threads : $($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors)")
    $report.Add("RAM Installed : $([math]::Round($cs.TotalPhysicalMemory / 1GB, 1)) GB")

    $report.Add((Get-Section "Disks"))
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $freePct = [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
        $report.Add("$($_.DeviceID) $([math]::Round($_.FreeSpace/1GB,1))GB free / $([math]::Round($_.Size/1GB,1))GB total ($freePct% free)")
    }

    $report.Add((Get-Section "Network"))
    Get-NetIPConfiguration | Where-Object { $_.IPv4Address } | ForEach-Object {
        $report.Add("$($_.InterfaceAlias): $($_.IPv4Address.IPAddress) | Gateway: $($_.IPv4DefaultGateway.NextHop) | DNS: $($_.DNSServer.ServerAddresses -join ', ')")
    }

    $report.Add((Get-Section "Recently Installed Software (last 90 days)"))
    $cutoff = (Get-Date).AddDays(-90)
    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    Get-ItemProperty $uninstallPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.InstallDate } |
        ForEach-Object {
            try {
                $installDate = [datetime]::ParseExact($_.InstallDate, "yyyyMMdd", $null)
                if ($installDate -ge $cutoff) {
                    $report.Add("$($_.DisplayName) - installed $($installDate.ToShortDateString())")
                }
            } catch {}
        }

    $output = $report -join "`n"
    Write-Output $output

    if ($OutFile) {
        $output | Out-File -FilePath $OutFile -Encoding utf8
        Write-Output "`nSaved to $OutFile"
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