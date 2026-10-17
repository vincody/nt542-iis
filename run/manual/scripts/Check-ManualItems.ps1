#Requires -RunAsAdministrator
<#
  Check-ManualItems.ps1 - READ-ONLY helper for the 14 Manual items of the CIS IIS 10 benchmark.
  It never changes anything. For each Manual item it shows the current state and a verdict:
    DONE    already matches the CIS recommendation
    TODO    does not match yet - do the manual steps in HuongDan_CIS_IIS10.md
    REVIEW  needs your judgement (value depends on the application)
    N/A     nothing to check on this server (for example FTP not installed)
    ERROR   the check itself failed
  Run it before and after you do the manual steps, and keep both outputs as evidence.
  File is ASCII only.
#>
[CmdletBinding()]
param([string]$OutDir = '.\out')

$ErrorActionPreference = 'Stop'
Import-Module WebAdministration
$AppHost = 'MACHINE/WEBROOT/APPHOST'
$results = New-Object System.Collections.Generic.List[object]

function Add-Check {
  param([string]$Id, [string]$Title, [ValidateSet('DONE', 'TODO', 'REVIEW', 'N/A', 'ERROR')][string]$Verdict, [string]$Detail = '')
  $results.Add([pscustomobject]@{ Id = $Id; Title = $Title; Verdict = $Verdict; Detail = $Detail })
  $color = 'Gray'
  switch ($Verdict) { 'DONE' { $color = 'Green' } 'TODO' { $color = 'Red' } 'REVIEW' { $color = 'Cyan' } 'ERROR' { $color = 'Yellow' } }
  Write-Host ('[{0,-6}] {1,-5} {2}' -f $Verdict, $Id, $Title) -ForegroundColor $color
  if ($Detail) { Write-Host ('           ' + $Detail) -ForegroundColor DarkGray }
}

function Get-Cfg {
  param([string]$Filter, [string]$Name, [string]$PSPath = $AppHost, [string]$Location)
  $p = @{ Filter = $Filter; Name = $Name; PSPath = $PSPath }
  if ($Location) { $p.Location = $Location }
  $v = Get-WebConfigurationProperty @p
  if ($null -ne $v -and $v.PSObject.Properties['Value']) { $v.Value } else { $v }
}

function Get-Collection {
  param([string]$Filter, [string]$PSPath = $AppHost)
  $e = Get-WebConfigurationProperty -PSPath $PSPath -Filter $Filter -Name '.'
  @($e.Collection)
}

$hasFeatureCmd = [bool](Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)

# 1.1 web content not on the system drive
try {
  $sys = $env:SystemDrive
  $bad = @(Get-Website | Where-Object { [Environment]::ExpandEnvironmentVariables($_.physicalPath).StartsWith($sys, [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { "$($_.Name)=$($_.physicalPath)" })
  if ($bad.Count -eq 0) { Add-Check '1.1' 'Web content is on non-system partition' 'DONE' 'no site is mapped to the system drive' }
  else { Add-Check '1.1' 'Web content is on non-system partition' 'TODO' ('on system drive: ' + ($bad -join '; ')) }
} catch { Add-Check '1.1' 'Web content is on non-system partition' 'ERROR' $_.Exception.Message }

# 2.1 global authorization rule
try {
  $col = Get-Collection 'system.webServer/security/authorization'
  $allowAll = @($col | Where-Object { "$($_.accessType)" -eq 'Allow' -and "$($_.users)" -eq '*' })
  $rules = ($col | ForEach-Object { "$($_.accessType) users='$($_.users)' roles='$($_.roles)'" }) -join ' | '
  if ($allowAll.Count -eq 0) { Add-Check '2.1' 'Global authorization rule restricts access' 'DONE' $rules }
  else { Add-Check '2.1' 'Global authorization rule restricts access' 'TODO' "'Allow all users' still present. Rules: $rules" }
} catch { Add-Check '2.1' 'Global authorization rule restricts access' 'ERROR' $_.Exception.Message }

# 2.2 authentication modules per site (judgement)
try {
  $lines = @()
  foreach ($s in @(Get-Website | Where-Object { @($_.bindings.Collection | Where-Object { $_.protocol -like 'http*' }).Count -gt 0 })) {
    $on = @()
    foreach ($m in 'anonymousAuthentication', 'basicAuthentication', 'windowsAuthentication', 'digestAuthentication') {
      if ("$(Get-Cfg "system.webServer/security/authentication/$m" 'enabled' $AppHost $s.Name)" -eq 'True') { $on += $m.Replace('Authentication', '') }
    }
    $lines += "$($s.Name): $($on -join ', ')"
  }
  Add-Check '2.2' 'Sensitive features require authenticated users' 'REVIEW' ($lines -join ' | ')
} catch { Add-Check '2.2' 'Sensitive features require authenticated users' 'ERROR' $_.Exception.Message }

# 3.1 deployment retail in machine.config (32 and 64 bit)
try {
  $files = @("$env:windir\Microsoft.NET\Framework64\v4.0.30319\Config\machine.config", "$env:windir\Microsoft.NET\Framework\v4.0.30319\Config\machine.config")
  $notes = @(); $allOk = $true
  foreach ($f in $files) {
    if (-not (Test-Path $f)) { $notes += "missing: $f"; continue }
    [xml]$x = Get-Content -Path $f -Raw
    $d = $x.SelectSingleNode('//system.web/deployment')
    $r = '(not set)'
    if ($d) { $r = $d.GetAttribute('retail') }
    if ($r -ne 'true') { $allOk = $false }
    $bits = '32-bit'
    if ($f -like '*Framework64*') { $bits = '64-bit' }
    $notes += "$bits machine.config retail=$r"
  }
  if ($allOk) { Add-Check '3.1' "deployment retail is set" 'DONE' ($notes -join ' | ') } else { Add-Check '3.1' "deployment retail is set" 'TODO' ($notes -join ' | ') }
} catch { Add-Check '3.1' "deployment retail is set" 'ERROR' $_.Exception.Message }

# 3.11 X-Powered-By header
try {
  $h = @(Get-Collection 'system.webServer/httpProtocol/customHeaders' | Where-Object { $_.name -eq 'X-Powered-By' })
  if ($h.Count -eq 0) { Add-Check '3.11' 'X-Powered-By header removed (L2)' 'DONE' 'no X-Powered-By custom header' }
  else { Add-Check '3.11' 'X-Powered-By header removed (L2)' 'TODO' "present: $($h[0].value)" }
} catch { Add-Check '3.11' 'X-Powered-By header removed (L2)' 'ERROR' $_.Exception.Message }

# 3.12 Server header
try {
  $v = Get-Cfg 'system.webServer/security/requestFiltering' 'removeServerHeader'
  if ("$v" -eq 'True') { Add-Check '3.12' 'Server header removed (L2)' 'DONE' 'removeServerHeader=True' }
  else { Add-Check '3.12' 'Server header removed (L2)' 'TODO' "removeServerHeader=$v" }
} catch { Add-Check '3.12' 'Server header removed (L2)' 'ERROR' $_.Exception.Message }

# 4.1 maxAllowedContentLength (judgement)
try {
  $v = Get-Cfg 'system.webServer/security/requestFiltering/requestLimits' 'maxAllowedContentLength'
  Add-Check '4.1' 'maxAllowedContentLength is configured (L2)' 'REVIEW' "maxAllowedContentLength=$v bytes (default 30000000). Choose a value that fits the application"
} catch { Add-Check '4.1' 'maxAllowedContentLength is configured (L2)' 'ERROR' $_.Exception.Message }

# 4.6 TRACE verb denied
try {
  $t = @(Get-Collection 'system.webServer/security/requestFiltering/verbs' | Where-Object { $_.verb -eq 'TRACE' })
  if ($t.Count -gt 0 -and "$($t[0].allowed)" -eq 'False') { Add-Check '4.6' 'HTTP TRACE method is disabled' 'DONE' 'TRACE is denied in requestFiltering/verbs' }
  else { Add-Check '4.6' 'HTTP TRACE method is disabled' 'TODO' 'no deny rule for TRACE' }
} catch { Add-Check '4.6' 'HTTP TRACE method is disabled' 'ERROR' $_.Exception.Message }

# 4.8 handlers accessPolicy: not Write together with Script/Execute
try {
  $bad = @()
  $paths = @([pscustomobject]@{ Name = 'SERVER'; PSPath = $AppHost })
  foreach ($s in @(Get-Website)) { $paths += [pscustomobject]@{ Name = $s.Name; PSPath = "$AppHost/$($s.Name)" } }
  foreach ($p in $paths) {
    $v = "$(Get-Cfg 'system.webServer/handlers' 'accessPolicy' $p.PSPath)"
    if (($v -match 'Write') -and ($v -match 'Script|Execute')) { $bad += "$($p.Name): $v" }
  }
  if ($bad.Count -eq 0) { Add-Check '4.8' 'Handler is not granted Write and Script/Execute' 'DONE' 'accessPolicy has no Write together with Script/Execute' }
  else { Add-Check '4.8' 'Handler is not granted Write and Script/Execute' 'TODO' ($bad -join '; ') }
} catch { Add-Check '4.8' 'Handler is not granted Write and Script/Execute' 'ERROR' $_.Exception.Message }

# 4.11 Dynamic IP Address Restrictions
try {
  if ($hasFeatureCmd -and -not (Get-WindowsFeature -Name Web-IP-Security).Installed) {
    Add-Check '4.11' 'Dynamic IP Address Restrictions enabled' 'TODO' 'IP and Domain Restrictions role service (Web-IP-Security) is not installed'
  } else {
    $f = 'system.webServer/security/dynamicIpSecurity/denyByConcurrentRequests'
    $en = Get-Cfg $f 'enabled'
    $mx = Get-Cfg $f 'maxConcurrentRequests'
    if ("$en" -eq 'True') { Add-Check '4.11' 'Dynamic IP Address Restrictions enabled' 'DONE' "denyByConcurrentRequests enabled, max=$mx. Also prove it by triggering a block" }
    else { Add-Check '4.11' 'Dynamic IP Address Restrictions enabled' 'TODO' "denyByConcurrentRequests enabled=$en" }
  }
} catch { Add-Check '4.11' 'Dynamic IP Address Restrictions enabled' 'ERROR' $_.Exception.Message }

# 5.3 ETW logging
try {
  $fmt = "$(Get-Cfg 'system.applicationHost/sites/siteDefaults/logFile' 'logFormat')"
  $tgt = "$(Get-Cfg 'system.applicationHost/sites/siteDefaults/logFile' 'logTargetW3C')"
  if ($fmt -eq 'W3C' -and $tgt -match 'ETW' -and $tgt -match 'File') { Add-Check '5.3' 'ETW logging is enabled' 'DONE' "logFormat=$fmt logTargetW3C=$tgt" }
  else { Add-Check '5.3' 'ETW logging is enabled' 'TODO' "logFormat=$fmt logTargetW3C=$tgt (want W3C and File,ETW)" }
} catch { Add-Check '5.3' 'ETW logging is enabled' 'ERROR' $_.Exception.Message }

# 6.1 FTP requests encrypted
try {
  if ($hasFeatureCmd -and -not (Get-WindowsFeature -Name Web-Ftp-Server).Installed) { Add-Check '6.1' 'FTP requests are encrypted' 'N/A' 'FTP Server role service not installed' }
  else {
    $f = 'system.applicationHost/sites/siteDefaults/ftpServer/security/ssl'
    $c = "$(Get-Cfg $f 'controlChannelPolicy')"; $d = "$(Get-Cfg $f 'dataChannelPolicy')"
    if ($c -eq 'SslRequire' -and $d -eq 'SslRequire') { Add-Check '6.1' 'FTP requests are encrypted' 'DONE' "control=$c data=$d" }
    else { Add-Check '6.1' 'FTP requests are encrypted' 'TODO' "control=$c data=$d (want SslRequire for both)" }
  }
} catch { Add-Check '6.1' 'FTP requests are encrypted' 'ERROR' $_.Exception.Message }

# 6.2 FTP logon attempt restrictions
try {
  if ($hasFeatureCmd -and -not (Get-WindowsFeature -Name Web-Ftp-Server).Installed) { Add-Check '6.2' 'FTP logon attempt restrictions enabled' 'N/A' 'FTP Server role service not installed' }
  else {
    $v = Get-Cfg 'system.ftpServer/security/authentication/denyByFailure' 'enabled'
    if ("$v" -eq 'True') { Add-Check '6.2' 'FTP logon attempt restrictions enabled' 'DONE' 'denyByFailure enabled=True' }
    else { Add-Check '6.2' 'FTP logon attempt restrictions enabled' 'TODO' "denyByFailure enabled=$v" }
  }
} catch { Add-Check '6.2' 'FTP logon attempt restrictions enabled' 'ERROR' $_.Exception.Message }

# 7.1 HSTS header
try {
  $h = @(Get-Collection 'system.webServer/httpProtocol/customHeaders' | Where-Object { $_.name -eq 'Strict-Transport-Security' })
  if ($h.Count -gt 0 -and "$($h[0].value)" -match 'max-age=([1-9]\d*)') { Add-Check '7.1' 'HSTS header is set (L2)' 'DONE' "Strict-Transport-Security: $($h[0].value)" }
  else { Add-Check '7.1' 'HSTS header is set (L2)' 'TODO' 'Strict-Transport-Security header missing or max-age is 0' }
} catch { Add-Check '7.1' 'HSTS header is set (L2)' 'ERROR' $_.Exception.Message }

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$csv = Join-Path $OutDir ('manual-check-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.csv')
$results | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Host ''
$results | Group-Object Verdict | Sort-Object Name | ForEach-Object { Write-Host ('{0,-7} {1}' -f $_.Name, $_.Count) }
Write-Host "Saved: $csv" -ForegroundColor Cyan
