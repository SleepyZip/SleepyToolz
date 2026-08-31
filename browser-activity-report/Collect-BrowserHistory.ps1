<#
    Collect-BrowserHistory.ps1
    Datto RMM component -- Category: Scripts -- Engine: PowerShell -- Run as: Local System

    Copies each local user's Chrome (and optionally Edge) History database into
    the LOCAL admin account's profile:

        C:\Users\LocalCollector\Documents\BrowserData\

    Files are named for the downstream report parser:

        ChromeHistory_<username><COMPUTERNAME>
        EdgeHistory_<username><COMPUTERNAME>
        ChromeHistory_<username><COMPUTERNAME>P1     (Chrome "Profile 1")

    The destination folder is created if missing (the full path, including
    Documents\BrowserData, and Users\<account> if the profile does not yet
    exist). Because the target is local, SYSTEM always has write access -- no
    share permissions, no machine-account ACLs, no stored credentials.

    Collect the results afterwards with Gather-BrowserHistory.ps1, which runs
    from your workstation under YOUR credentials over the admin share.

    Component input variables (Datto RMM -> Variables). All optional.
        usrTargetUsers    Only collect these users. Blank = every profile.
                          Comma/semicolon list. "DOMAIN\first.last" or
                          "first.last"; mix freely.
        usrLocalAccount   Local account to write into.  Default: LocalCollector
        usrSubfolder      Path under that profile.      Default: Documents\BrowserData
        usrDestination    Explicit path; overrides the two above. Default: (unset)
        usrIncludeEdge    "true" to also collect Edge.  Default: false
        usrMaxAgeDays     Skip profiles unused in N days. 0 = no limit. Default: 0
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------------------------------------------------------- settings --
function Get-Var {
    param([string]$Name, [string]$Fallback)
    $v = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($v)) { return $Fallback }
    return $v.Trim()
}

$Account     = Get-Var 'usrLocalAccount' 'LocalCollector'
$Subfolder   = Get-Var 'usrSubfolder'    'Documents\BrowserData'
$Override    = Get-Var 'usrDestination'  ''
$IncludeEdge = (Get-Var 'usrIncludeEdge' 'false') -match '^(true|1|yes)$'
$MaxAgeDays  = [int](Get-Var 'usrMaxAgeDays' '0')

# Comma/semicolon separated list of users to collect. Blank = every profile.
# Accepts "DOMAIN\first.last", "first.last", or a mix.
$TargetRaw   = Get-Var 'usrTargetUsers' ''
$Targets     = @($TargetRaw -split '[;,]' | ForEach-Object { $_.Trim() } |
                 Where-Object { $_ })

$Computer    = $env:COMPUTERNAME

Write-Host "=== Browser history collection ==="
Write-Host "Device       : $Computer"
Write-Host "Local account: .\$Account"
Write-Host "Include Edge : $IncludeEdge"
if ($MaxAgeDays -gt 0) { Write-Host "Max age      : $MaxAgeDays days" }
if ($Targets.Count -gt 0) {
    Write-Host "Target users : $($Targets -join ', ')"
} else {
    Write-Host "Target users : (all profiles on this device)"
}

function Fail {
    param([string]$Message, [string]$Result)
    Write-Host ""
    Write-Host "FATAL: $Message"
    Write-Host "<-Start Result->"
    Write-Host "Result=$Result"
    Write-Host "<-End Result->"
    exit 1
}

# ------------------------------------------------ resolve the local profile --
function Get-LocalProfilePath {
    <# Resolve via SID rather than assuming C:\Users\<name>. Windows renames
       profile folders on collision (LocalCollector.PC01), so the literal path
       is not reliable. #>
    param([string]$Name)
    try {
        $nt  = New-Object System.Security.Principal.NTAccount($env:COMPUTERNAME, $Name)
        $sid = $nt.Translate([System.Security.Principal.SecurityIdentifier]).Value
    }
    catch { return $null }

    $key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
    if (Test-Path $key) {
        $p = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).ProfileImagePath
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

if ($Override) {
    $Dest = $Override
    Write-Host "Destination  : $Dest  (explicit override)"
}
else {
    # Confirm the account actually exists locally before going further.
    $exists = $false
    try { $exists = [bool](Get-LocalUser -Name $Account -ErrorAction Stop) } catch { }
    if (-not $exists) {
        Fail "local account '.\$Account' does not exist on $Computer." `
             "NO LOCAL ACCOUNT '$Account'"
    }

    # Prefer the real profile path from the registry. This matters when a prior
    # collision left the profile at LocalCollector.<COMPUTER> -- we want the actual
    # one, not a second wrong folder.
    $profilePath = Get-LocalProfilePath -Name $Account
    if (-not $profilePath) {
        # Account exists but has no profile yet (never signed in). Use the
        # conventional location; New-Item below creates the full path.
        $profilePath = Join-Path $env:SystemDrive "Users\$Account"
        Write-Host "NOTE: .\$Account has no profile yet; creating $profilePath\$Subfolder."
    }
    $Dest = Join-Path $profilePath $Subfolder
    Write-Host "Destination  : $Dest"
}
Write-Host ""

# ------------------------------------------------------------- destination --
try {
    if (-not (Test-Path -LiteralPath $Dest)) {
        New-Item -Path $Dest -ItemType Directory -Force | Out-Null
    }
    $probe = Join-Path $Dest ".write_test"
    Set-Content -LiteralPath $probe -Value 'ok' -Force
    Remove-Item -LiteralPath $probe -Force
}
catch {
    Fail "cannot write to $Dest`n$($_.Exception.Message)" "DEST NOT WRITABLE"
}

# Make sure the LocalCollector account can read what SYSTEM just wrote.
if (-not $Override) {
    try {
        $acl  = Get-Acl -LiteralPath $Dest
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "$Computer\$Account", 'Modify',
            'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.SetAccessRule($rule)
        Set-Acl -LiteralPath $Dest -AclObject $acl
    }
    catch { Write-Host "  (ACL grant skipped: $($_.Exception.Message))" }
}

# ------------------------------------------------------------------ helpers --
function Copy-OpenFile {
    <# Chrome keeps History open. FileShare::ReadWrite reads it anyway,
       which Copy-Item cannot do. #>
    param([string]$Source, [string]$Target)

    $in = [System.IO.File]::Open(
        $Source,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    try {
        $out = [System.IO.File]::Create($Target)
        try { $in.CopyTo($out) } finally { $out.Dispose() }
    }
    finally { $in.Dispose() }
}

$Browsers = @(
    [pscustomobject]@{ Tag = 'ChromeHistory'; Root = 'AppData\Local\Google\Chrome\User Data' }
)
if ($IncludeEdge) {
    $Browsers += [pscustomobject]@{ Tag = 'EdgeHistory'; Root = 'AppData\Local\Microsoft\Edge\User Data' }
}

$Skip = @('Public', 'Default', 'Default User', 'All Users', 'defaultuser0',
          'WDAGUtilityAccount', $Account)

function Resolve-TargetProfiles {
    <#
        Turn a list like "DOMAIN\first.last","Jane.Doe" into the actual
        profile directories on this device.

        SID-first: translate the account, then read ProfileImagePath from
        ProfileList. That is authoritative and survives folder-name quirks
        (first.last vs first.last.DOMAIN). Falls back to matching the
        folder name if the account can't be translated (e.g. no DC reachable).

        Returns [pscustomobject]@{ Label; Dir } and prints any misses.
    #>
    param([string[]]$Wanted)

    $found = @()
    foreach ($w in $Wanted) {
        $domain, $name = if ($w -match '\\') { $w -split '\\', 2 } else { $null, $w }

        $dir = $null
        # 1. SID -> ProfileList (authoritative)
        try {
            $nt = if ($domain) {
                New-Object System.Security.Principal.NTAccount($domain, $name)
            } else {
                New-Object System.Security.Principal.NTAccount($name)
            }
            $sid = $nt.Translate([System.Security.Principal.SecurityIdentifier]).Value
            $key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid"
            if (Test-Path $key) {
                $p = (Get-ItemProperty -Path $key -EA SilentlyContinue).ProfileImagePath
                if ($p -and (Test-Path -LiteralPath $p)) {
                    $dir = Get-Item -LiteralPath $p
                }
            }
        }
        catch { }

        # 2. Fall back to folder-name match: exact, or name.<something>
        if (-not $dir) {
            $dir = Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue |
                   Where-Object { $_.Name -eq $name -or $_.Name -like "$name.*" } |
                   Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }

        if ($dir) {
            Write-Host "  target  $w  ->  $($dir.FullName)"
            $found += [pscustomobject]@{ Label = $w; Dir = $dir }
        }
        else {
            Write-Host "  target  $w  ->  NOT FOUND on this device"
            $script:missTargets += $w
        }
    }
    return $found
}

$missTargets = @()

$copied  = 0
$skipped = 0
$failed  = 0
$rows    = @()

# -------------------------------------------------------------------- work --
if ($Targets.Count -gt 0) {
    Write-Host "Resolving target users:"
    $profileList = @(Resolve-TargetProfiles -Wanted $Targets | ForEach-Object { $_.Dir })
    Write-Host ""
}
else {
    $profileList = @(Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue |
                     Where-Object { $Skip -notcontains $_.Name })
}

foreach ($profileDir in $profileList) {

    # Windows may name a domain profile "first.last.DOMAIN" after a collision.
    # The report parser wants first.last, so drop a trailing .<DOMAIN> segment --
    # but ONLY when that segment is a real domain (the machine's, or one named
    # in the targets). This avoids mangling a genuine three-part name like
    # jo.ann.smith.
    $user = $profileDir.Name
    $knownDomains = @()
    if ($env:USERDOMAIN)   { $knownDomains += $env:USERDOMAIN }
    if ($env:USERDNSDOMAIN){ $knownDomains += ($env:USERDNSDOMAIN -split '\.')[0] }
    foreach ($t in $Targets) {
        if ($t -match '\\') { $knownDomains += ($t -split '\\', 2)[0] }
    }
    $knownDomains = $knownDomains | Where-Object { $_ } | Sort-Object -Unique
    foreach ($d in $knownDomains) {
        if ($user -match "^(.+)\.$([regex]::Escape($d))$") {
            $user = $Matches[1]
            break
        }
    }

    foreach ($b in $Browsers) {
        $userData = Join-Path $profileDir.FullName $b.Root
        if (-not (Test-Path -LiteralPath $userData)) { continue }

        $chromeProfiles = @(Get-ChildItem $userData -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })

        foreach ($cp in $chromeProfiles) {
            $hist = Join-Path $cp.FullName 'History'
            if (-not (Test-Path -LiteralPath $hist)) { continue }

            $info = Get-Item -LiteralPath $hist
            if ($info.Length -eq 0) { continue }

            if ($MaxAgeDays -gt 0 -and
                $info.LastWriteTime -lt (Get-Date).AddDays(-$MaxAgeDays)) {
                Write-Host "  skip  $user / $($b.Tag) / $($cp.Name)  (stale: $($info.LastWriteTime.ToString('MM-dd-yyyy')))"
                $skipped++
                continue
            }

            $suffix = ''
            if ($cp.Name -match '^Profile\s+(\d+)$') { $suffix = "P$($Matches[1])" }

            $name   = "$($b.Tag)_$user$Computer$suffix"
            $target = Join-Path $Dest $name

            try {
                Copy-OpenFile -Source $hist -Target $target

                foreach ($side in @('History-wal', 'History-shm')) {
                    $sp = Join-Path $cp.FullName $side
                    if (Test-Path -LiteralPath $sp) {
                        $ext = $side.Substring(7)   # "-wal" / "-shm"
                        Copy-OpenFile -Source $sp -Target ($target + $ext)
                    }
                }

                $mb = [math]::Round($info.Length / 1MB, 1)
                Write-Host "  ok    $name  ($mb MB)"
                $copied++
                $rows += [pscustomobject]@{
                    Collected = (Get-Date).ToString('s')
                    Device    = $Computer
                    User      = $user
                    Browser   = $b.Tag.Replace('History', '')
                    Profile   = $cp.Name
                    File      = $name
                    SizeMB    = $mb
                    LastUsed  = $info.LastWriteTime.ToString('s')
                }
            }
            catch {
                Write-Host "  FAIL  $name  -- $($_.Exception.Message)"
                $failed++
            }
        }
    }
}

# ---------------------------------------------------------------- manifest --
if ($rows.Count -gt 0) {
    try {
        $mf = Join-Path $Dest '_collection_manifest.csv'
        $rows | Export-Csv -LiteralPath $mf -NoTypeInformation -Append -Force
    }
    catch { Write-Host "  (manifest append failed: $($_.Exception.Message))" }
}

# ------------------------------------------------------------------ result --
Write-Host ""
Write-Host "Copied $copied, skipped $skipped, failed $failed"
Write-Host "Location: $Dest"

try {
    $csKey = 'HKLM:\SOFTWARE\CentraStage'
    if (-not (Test-Path $csKey)) { New-Item -Path $csKey -Force | Out-Null }
    $udf = "Hist: $copied copied $(Get-Date -Format 'MM-dd-yyyy HH:mm')"
    New-ItemProperty -Path $csKey -Name 'Custom1' -Value $udf `
        -PropertyType String -Force -ErrorAction Stop | Out-Null
}
catch { Write-Host "  (UDF write skipped: $($_.Exception.Message))" }

Write-Host "<-Start Result->"
if ($missTargets.Count -gt 0) {
    Write-Host "Result=Copied $copied, failed $failed. NOT FOUND: $($missTargets -join ', ')"
} else {
    Write-Host "Result=Copied $copied, skipped $skipped, failed $failed"
}
Write-Host "<-End Result->"

if ($copied -eq 0 -and $failed -gt 0) { exit 1 }
exit 0
