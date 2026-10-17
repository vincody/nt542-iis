# checks.ps1 - CIS IIS 10 benchmark, part 2: Authentication and Authorization
# Definitions only (nothing runs here). Dot-sourced by Audit.ps1, Remediate.ps1 and ..\scripts\IIS-CIS.ps1.
# Automated items are in $PartChecks, Manual items (listed in the report, done by hand) in $PartManual.
# File is ASCII only.

$IsForms = { param($p) "$(Get-Cfg 'system.web/authentication' 'mode' $p.PSPath)" -eq 'Forms' }

$PartChecks = @()

$PartChecks += New-PropCheck -Id '2.3' -Title "Ensure 'forms authentication' require SSL" -Level 1 -Wave 2 `
  -Filter 'system.web/authentication/forms' -Name 'requireSSL' -Scope 'Asp' -Applies $IsForms `
  -Good { param($v) "$v" -eq 'True' } -Want 'True' -SetValue $true

$PartChecks += New-PropCheck -Id '2.4' -Title "Ensure 'forms authentication' is set to use cookies" -Level 2 -Wave 1 `
  -Filter 'system.web/authentication/forms' -Name 'cookieless' -Scope 'Asp' -Applies $IsForms `
  -Good { param($v) "$v" -eq 'UseCookies' } -Want 'UseCookies' -SetValue 'UseCookies'

$PartChecks += New-PropCheck -Id '2.5' -Title "Ensure 'cookie protection mode' is configured for forms authentication" -Level 1 -Wave 1 `
  -Filter 'system.web/authentication/forms' -Name 'protection' -Scope 'Asp' -Applies $IsForms `
  -Good { param($v) "$v" -eq 'All' } -Want 'All' -SetValue 'All'

$PartChecks += @{
  Id = '2.6'; Title = "Ensure transport layer security for 'basic authentication' is configured"; Level = 1; Wave = 2; Reboot = $false
  FixHint = 'Set system.webServer/security/access sslFlags = Ssl for sites with Basic auth (site needs an HTTPS binding)'
  Test = {
    param($c)
    foreach ($s in @(Get-HttpSites)) {
      try {
        $basic = Get-Cfg 'system.webServer/security/authentication/basicAuthentication' 'enabled' $AppHostPath $s.Name
        if ("$basic" -ne 'True') { New-Row $s.Name 'N/A' 'Basic authentication not enabled'; continue }
        $flags = "$(Get-Cfg 'system.webServer/security/access' 'sslFlags' $AppHostPath $s.Name)"
        if (($flags -split '[,\s]+') -contains 'Ssl') { New-Row $s.Name 'PASS' "sslFlags=$flags" }
        else { New-Row $s.Name 'FAIL' "Basic enabled, sslFlags='$flags'" }
      } catch { New-Row $s.Name 'ERROR' $_.Exception.Message }
    }
  }
  Fix = {
    param($c)
    $errs = @()
    foreach ($s in @(Get-HttpSites)) {
      if ("$(Get-Cfg 'system.webServer/security/authentication/basicAuthentication' 'enabled' $AppHostPath $s.Name)" -ne 'True') { continue }
      if (-not (Get-WebBinding -Name $s.Name -Protocol https)) { $errs += "$($s.Name): no HTTPS binding, add one first"; continue }
      Set-Cfg 'system.webServer/security/access' 'sslFlags' 'Ssl' $AppHostPath $s.Name
    }
    if ($errs.Count -gt 0) { throw ($errs -join '; ') }
  }
}

$PartChecks += @{
  Id = '2.7'; Title = "Ensure 'passwordFormat' is not set to clear"; Level = 1; Wave = 1; Reboot = $false
  FixHint = 'Set passwordFormat=SHA1 in web.config (backup .bak). Existing clear-text passwords must be re-hashed by hand'
  Test = {
    param($c)
    foreach ($s in @(Get-HttpSites)) {
      $cfg = Get-SiteWebConfig $s
      if (-not (Test-Path $cfg)) { New-Row $s.Name 'N/A' 'no web.config'; continue }
      try {
        [xml]$x = Get-Content -Path $cfg -Raw
        $n = $x.SelectSingleNode('//system.web/authentication/forms/credentials')
        if ($null -eq $n) { New-Row $s.Name 'PASS' 'no credentials element' }
        elseif ($n.GetAttribute('passwordFormat') -eq 'Clear') { New-Row $s.Name 'FAIL' 'passwordFormat=Clear' }
        else { New-Row $s.Name 'PASS' "passwordFormat='$($n.GetAttribute('passwordFormat'))'" }
      } catch { New-Row $s.Name 'ERROR' $_.Exception.Message }
    }
  }
  Fix = {
    param($c)
    foreach ($s in @(Get-HttpSites)) {
      $cfg = Get-SiteWebConfig $s
      if (-not (Test-Path $cfg)) { continue }
      [xml]$x = Get-Content -Path $cfg -Raw
      $n = $x.SelectSingleNode('//system.web/authentication/forms/credentials')
      if ($n -and $n.GetAttribute('passwordFormat') -eq 'Clear') {
        Copy-Item $cfg "$cfg.bak" -Force
        $n.SetAttribute('passwordFormat', 'SHA1')
        $x.Save($cfg)
      }
    }
  }
}

$PartChecks += @{
  Id = '2.8'; Title = "Ensure 'credentials' are not stored in configuration files"; Level = 2; Wave = 2; Reboot = $false
  FixHint = 'Remove the credentials element from web.config (backup .bak)'
  Test = {
    param($c)
    foreach ($s in @(Get-HttpSites)) {
      $cfg = Get-SiteWebConfig $s
      if (-not (Test-Path $cfg)) { New-Row $s.Name 'N/A' 'no web.config'; continue }
      try {
        [xml]$x = Get-Content -Path $cfg -Raw
        if ($x.SelectSingleNode('//system.web/authentication/forms/credentials')) { New-Row $s.Name 'FAIL' 'credentials element present' }
        else { New-Row $s.Name 'PASS' 'no credentials element' }
      } catch { New-Row $s.Name 'ERROR' $_.Exception.Message }
    }
  }
  Fix = {
    param($c)
    foreach ($s in @(Get-HttpSites)) {
      $cfg = Get-SiteWebConfig $s
      if (-not (Test-Path $cfg)) { continue }
      [xml]$x = Get-Content -Path $cfg -Raw
      $n = $x.SelectSingleNode('//system.web/authentication/forms/credentials')
      if ($n) {
        Copy-Item $cfg "$cfg.bak" -Force
        [void]$n.ParentNode.RemoveChild($n)
        $x.Save($cfg)
      }
    }
  }
}

$PartManual = @(
  @{ Id = '2.1'; Level = 1; Title = "Ensure 'global authorization rule' is set to restrict access" },
  @{ Id = '2.2'; Level = 1; Title = 'Ensure access to sensitive site features is restricted to authenticated principals only' }
)
