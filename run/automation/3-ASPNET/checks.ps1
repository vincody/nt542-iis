# checks.ps1 - CIS IIS 10 benchmark, part 3: ASP.NET Configuration
# Definitions only (nothing runs here). Dot-sourced by Audit.ps1, Remediate.ps1 and ..\scripts\IIS-CIS.ps1.
# Automated items are in $PartChecks, Manual items (listed in the report, done by hand) in $PartManual.
# File is ASCII only.

$PartChecks = @()

$PartChecks += New-PropCheck -Id '3.2' -Title "Ensure 'debug' is turned off" -Level 2 -Wave 1 `
  -Filter 'system.web/compilation' -Name 'debug' -Scope 'Asp' -Good { param($v) "$v" -eq 'False' } -Want 'False' -SetValue $false

$PartChecks += New-PropCheck -Id '3.3' -Title 'Ensure custom error messages are not off' -Level 2 -Wave 1 `
  -Filter 'system.web/customErrors' -Name 'mode' -Scope 'Asp' -Good { param($v) "$v" -in 'On', 'RemoteOnly' } -Want 'On or RemoteOnly' -SetValue 'RemoteOnly'

$PartChecks += New-PropCheck -Id '3.4' -Title 'Ensure IIS HTTP detailed errors are hidden from displaying remotely' -Level 1 -Wave 1 `
  -Filter 'system.webServer/httpErrors' -Name 'errorMode' -Scope 'Iis' -Good { param($v) "$v" -in 'DetailedLocalOnly', 'Custom' } -Want 'DetailedLocalOnly or Custom' -SetValue 'DetailedLocalOnly'

$PartChecks += New-PropCheck -Id '3.5' -Title 'Ensure ASP.NET stack tracing is not enabled' -Level 2 -Wave 1 `
  -Filter 'system.web/trace' -Name 'enabled' -Scope 'Asp' -Good { param($v) "$v" -eq 'False' } -Want 'False' -SetValue $false

$PartChecks += New-PropCheck -Id '3.6' -Title "Ensure 'httpcookie' mode is configured for session state" -Level 2 -Wave 1 `
  -Filter 'system.web/sessionState' -Name 'cookieless' -Scope 'Asp' -Good { param($v) "$v" -in 'UseCookies', 'False' } -Want 'UseCookies' -SetValue 'UseCookies'

$PartChecks += New-PropCheck -Id '3.7' -Title "Ensure 'cookies' are set with HttpOnly attribute" -Level 1 -Wave 1 `
  -Filter 'system.web/httpCookies' -Name 'httpOnlyCookies' -Scope 'Asp' -Good { param($v) "$v" -eq 'True' } -Want 'True' -SetValue $true

$PartChecks += @{
  Id = '3.8'; Title = "Ensure 'MachineKey validation method - .Net 3.5' is configured"; Level = 2; Wave = 1; Reboot = $false
  FixHint = 'Set machineKey validation=SHA1 in the CLR 2.0 web.config (backup .bak)'
  Test = {
    param($c)
    $f = "$env:windir\Microsoft.NET\Framework64\v2.0.50727\CONFIG\web.config"
    if (-not (Test-Path $f)) { New-Row 'CLR2.0' 'N/A' '.NET 3.5 (CLR 2.0) config not found'; return }
    [xml]$x = Get-Content -Path $f -Raw
    $mk = $x.SelectSingleNode('//system.web/machineKey')
    $val = 'SHA1'
    if ($mk -and $mk.GetAttribute('validation')) { $val = $mk.GetAttribute('validation') }
    if ($val -in 'SHA1', 'AES') { New-Row 'CLR2.0' 'PASS' "validation=$val" } else { New-Row 'CLR2.0' 'FAIL' "validation=$val" }
  }
  Fix = {
    param($c)
    $f = "$env:windir\Microsoft.NET\Framework64\v2.0.50727\CONFIG\web.config"
    Copy-Item $f "$f.bak" -Force
    [xml]$x = Get-Content -Path $f -Raw
    $sw = $x.SelectSingleNode('//system.web')
    $mk = $x.SelectSingleNode('//system.web/machineKey')
    if (-not $mk) { $mk = $sw.AppendChild($x.CreateElement('machineKey')) }
    $mk.SetAttribute('validation', 'SHA1')
    $x.Save($f)
  }
}

$PartChecks += New-PropCheck -Id '3.9' -Title "Ensure 'MachineKey validation method - .Net 4.5' is configured" -Level 1 -Wave 1 `
  -Filter 'system.web/machineKey' -Name 'validation' -Scope 'Root' -Good { param($v) "$v" -in 'HMACSHA256', 'HMACSHA384', 'HMACSHA512' } -Want 'HMACSHA256 or stronger' -SetValue 'HMACSHA256'

$PartChecks += New-PropCheck -Id '3.10' -Title 'Ensure global .NET trust level is configured' -Level 1 -Wave 3 `
  -Filter 'system.web/trust' -Name 'level' -Scope 'Root' -Good { param($v) "$v" -in 'Medium', 'Low', 'Minimal' } -Want 'Medium or lower' -SetValue 'Medium'

$PartManual = @(
  @{ Id = '3.1'; Level = 1; Title = "Ensure 'deployment method retail' is set" },
  @{ Id = '3.11'; Level = 2; Title = 'Ensure X-Powered-By Header is removed' },
  @{ Id = '3.12'; Level = 2; Title = 'Ensure Server Header is removed' }
)
