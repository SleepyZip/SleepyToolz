<#
Clears user/system temp folders and browser caches, reporting space freed.
Read-only by default (-WhatIf-style dry run); pass -Confirm:$false to actually delete.
#>

param(
    [switch]$Execute
)

$targets = @(
    "$env:TEMP",
    "$env:WINDIR\Temp",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2"
)

$totalBytes = 0
$fileCount = 0

foreach ($target in $targets) {
    $paths = Get-Item $target -ErrorAction SilentlyContinue
    if (-not $paths) { $paths = Get-ChildItem (Split-Path $target) -Directory -Filter (Split-Path $target -Leaf) -ErrorAction SilentlyContinue }
    foreach ($path in $paths) {
        $files = Get-ChildItem $path -Recurse -File -Force -ErrorAction SilentlyContinue
        $bytes = ($files | Measure-Object -Property Length -Sum).Sum
        if ($bytes) {
            $totalBytes += $bytes
            $fileCount += $files.Count
            Write-Output "$($path.FullName): $([math]::Round($bytes/1MB,1)) MB across $($files.Count) files"
            if ($Execute) {
                $files | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Write-Output "`nTotal: $([math]::Round($totalBytes/1MB,1)) MB across $fileCount files"

if (-not $Execute) {
    Write-Output "Dry run only - nothing was deleted. Re-run with -Execute to actually clear these files."
} else {
    Write-Output "Cleared."
}
