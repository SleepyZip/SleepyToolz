<#
Quick network health check: gateway, DNS servers, and external connectivity,
plus a DNS resolution test. Flags anything that looks broken instead of just
dumping raw output.
#>

$issues = [System.Collections.Generic.List[string]]::new()

$config = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1
if (-not $config) {
    Write-Output "No active network adapter with a default gateway found."
    exit 1
}

Write-Output "Interface : $($config.InterfaceAlias)"
Write-Output "IP        : $($config.IPv4Address.IPAddress)"
Write-Output "Gateway   : $($config.IPv4DefaultGateway.NextHop)"
Write-Output "DNS       : $($config.DNSServer.ServerAddresses -join ', ')"
Write-Output ""

function Test-Target($Name, $Target) {
    $result = Test-Connection -ComputerName $Target -Count 2 -Quiet -ErrorAction SilentlyContinue
    $status = if ($result) { "OK" } else { "FAIL" }
    Write-Output "$Name ($Target): $status"
    if (-not $result) { $script:issues.Add("$Name ($Target) unreachable") }
}

Test-Target "Default Gateway" $config.IPv4DefaultGateway.NextHop
foreach ($dns in $config.DNSServer.ServerAddresses) {
    Test-Target "DNS Server" $dns
}
Test-Target "External (Cloudflare)" "1.1.1.1"

Write-Output ""
try {
    $resolved = Resolve-DnsName "www.google.com" -ErrorAction Stop
    Write-Output "DNS resolution test: OK (www.google.com -> $($resolved[0].IPAddress))"
} catch {
    Write-Output "DNS resolution test: FAIL"
    $issues.Add("DNS resolution failed for www.google.com")
}

Write-Output "`n=== Summary ==="
if ($issues.Count -eq 0) {
    Write-Output "No issues detected."
} else {
    Write-Output "$($issues.Count) issue(s) found:"
    $issues | ForEach-Object { Write-Output " - $_" }
}
