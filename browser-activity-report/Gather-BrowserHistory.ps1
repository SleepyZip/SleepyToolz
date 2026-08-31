<#
    Gather-BrowserHistory.ps1
    Run from YOUR admin workstation, as YOU. Not a Datto component.

    Pulls what Collect-BrowserHistory.ps1 left in the local LocalCollector profile on
    each endpoint into one folder, ready for chrome_activity_report.py.

    The push direction failed under SYSTEM because SYSTEM authenticates to SMB
    as the machine account. This direction runs under your domain credentials
    over the admin share, so it just works.

    Examples
        .\Gather-BrowserHistory.ps1 -Computers PC01,PC02,PC03
        .\Gather-BrowserHistory.ps1 -Computers (Get-Content .\targets.txt) -Cleanup
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Computers,

    [string]$Destination = 'C:\Reports\Captures',

    [string]$Account = 'LocalCollector',

    [string]$Subfolder = 'Documents\BrowserData',

    # Delete the endpoint copy after a verified pull. These are browsing
    # databases; leaving them on the workstation is its own exposure.
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Destination)) {
    New-Item -Path $Destination -ItemType Directory -Force | Out-Null
}

$grabbed = 0
$misses  = @()

foreach ($c in $Computers) {

    Write-Host "--- $c"

    if (-not (Test-Connection -ComputerName $c -Count 1 -Quiet)) {
        Write-Host "    offline"
        $misses += "$c (offline)"
        continue
    }

    # Profile folder may be LocalCollector or LocalCollector.<COMPUTERNAME>.
    $userRoot = "\\$c\C$\Users"
    try {
        $prof = Get-ChildItem -LiteralPath $userRoot -Directory -ErrorAction Stop |
                Where-Object { $_.Name -eq $Account -or $_.Name -like "$Account.*" } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
    }
    catch {
        Write-Host "    cannot reach $userRoot -- $($_.Exception.Message)"
        $misses += "$c (admin share)"
        continue
    }

    if (-not $prof) {
        Write-Host "    no '$Account' profile"
        $misses += "$c (no profile)"
        continue
    }

    $src = Join-Path $prof.FullName $Subfolder
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host "    nothing collected yet"
        $misses += "$c (no captures)"
        continue
    }

    $files = @(Get-ChildItem -LiteralPath $src -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -like '*History_*' })

    if ($files.Count -eq 0) {
        Write-Host "    nothing collected yet"
        $misses += "$c (no captures)"
        continue
    }

    foreach ($f in $files) {
        # Filenames already carry COMPUTERNAME, so no collisions across machines.
        $target = Join-Path $Destination $f.Name
        Copy-Item -LiteralPath $f.FullName -Destination $target -Force

        $ok = (Get-Item -LiteralPath $target).Length -eq $f.Length
        if ($ok) {
            Write-Host ("    ok    {0}  ({1:N1} MB)" -f $f.Name, ($f.Length / 1MB))
            $grabbed++
            if ($Cleanup) { Remove-Item -LiteralPath $f.FullName -Force }
        }
        else {
            Write-Host "    SIZE MISMATCH  $($f.Name)  -- left in place"
            $misses += "$c/$($f.Name) (size mismatch)"
        }
    }

    $mf = Join-Path $src '_collection_manifest.csv'
    if (Test-Path -LiteralPath $mf) {
        Copy-Item -LiteralPath $mf `
            -Destination (Join-Path $Destination "_manifest_$c.csv") -Force
    }
}

Write-Host ""
Write-Host "Pulled $grabbed file(s) to $Destination"
if ($misses.Count -gt 0) {
    Write-Host "Incomplete:"
    $misses | ForEach-Object { Write-Host "  $_" }
}
Write-Host ""
Write-Host "Next:"
Write-Host "  python chrome_activity_report.py -i `"$Destination`" --outdir `"C:\Reports\Out`""
