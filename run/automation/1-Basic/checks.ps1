# checks.ps1 - CIS IIS 10 benchmark, part 1: Basic Configurations
# Definitions only (nothing runs here). Dot-sourced by Audit.ps1, Remediate.ps1 and ..\scripts\IIS-CIS.ps1.
# Automated items are in $PartChecks, Manual items (listed in the report, done by hand) in $PartManual.
# File is ASCII only.

if ($null -eq $HostMap) { $HostMap = @{} }
if (-not $HostSuffix) { $HostSuffix = 'lab.local' }

$PartChecks = @()

$PartChecks += @{
  Id = '1.2'; Title = "Ensure 'Host headers' are on all sites"; Level = 1; Wave = 2; Reboot = $false
  FixHint = 'Set-WebBinding HostHeader on http bindings without host (use -HostMap, else <site>.<HostSuffix>)'
  Test = {
    param($c)
    foreach ($s in @(Get-HttpSites)) {
      $bad = @($s.bindings.Collection | Where-Object { $_.protocol -eq 'http' -and $_.bindingInformation.EndsWith(':') })
      if ($bad.Count -eq 0) { New-Row $s.Name 'PASS' 'all http bindings have a host header' }
      else { New-Row $s.Name 'FAIL' ('no host header: ' + (($bad | ForEach-Object { $_.bindingInformation }) -join ', ')) }
    }
  }
  Fix = {
    param($c)
    foreach ($s in @(Get-HttpSites)) {
      $bad = @($s.bindings.Collection | Where-Object { $_.protocol -eq 'http' -and $_.bindingInformation.EndsWith(':') })
      foreach ($b in $bad) {
        $h = $HostMap[$s.Name]
        if (-not $h) { $h = (($s.Name -replace '\s', '').ToLower()) + '.' + $HostSuffix }
        Set-WebBinding -Name $s.Name -BindingInformation $b.bindingInformation -PropertyName HostHeader -Value $h
      }
    }
  }
}

$PartChecks += New-PropCheck -Id '1.3' -Title "Ensure 'Directory browsing' is set to Disabled" -Level 1 -Wave 1 `
  -Filter 'system.webServer/directoryBrowse' -Name 'enabled' -Scope 'Iis' -Good { param($v) "$v" -eq 'False' } -Want 'False' -SetValue $false

$PartChecks += @{
  Id = '1.4'; Title = "Ensure 'application pool identity' is configured for all application pools"; Level = 1; Wave = 2; Reboot = $false
  FixHint = 'Set processModel.identityType = ApplicationPoolIdentity on every pool'
  Test = {
    param($c)
    foreach ($pool in @(Get-ChildItem IIS:\AppPools)) {
      $t = "$($pool.processModel.identityType)"
      if ($t -eq 'ApplicationPoolIdentity') { New-Row $pool.Name 'PASS' $t } else { New-Row $pool.Name 'FAIL' "identityType=$t" }
    }
  }
  Fix = {
    param($c)
    foreach ($pool in @(Get-ChildItem IIS:\AppPools)) {
      if ("$($pool.processModel.identityType)" -ne 'ApplicationPoolIdentity') {
        Set-ItemProperty "IIS:\AppPools\$($pool.Name)" -Name processModel.identityType -Value ApplicationPoolIdentity
      }
    }
  }
}

$PartChecks += @{
  Id = '1.5'; Title = "Ensure 'unique application pools' is set for sites"; Level = 1; Wave = 2; Reboot = $false
  FixHint = 'Create one app pool per site for sites that share a pool (first site keeps the old pool)'
  Test = {
    param($c)
    foreach ($s in @(Get-Website)) {
      $pl = "$($s.applicationPool)"
      $mates = @(Get-Website | Where-Object { "$($_.applicationPool)" -eq $pl })
      if ($mates.Count -gt 1) { New-Row $s.Name 'FAIL' "pool '$pl' shared by $($mates.Count) sites" } else { New-Row $s.Name 'PASS' "own pool '$pl'" }
    }
  }
  Fix = {
    param($c)
    $groups = @(Get-Website | Group-Object { "$($_.applicationPool)" } | Where-Object { $_.Count -gt 1 })
    foreach ($g in $groups) {
      foreach ($s in @($g.Group | Select-Object -Skip 1)) {
        if (-not (Test-Path "IIS:\AppPools\$($s.Name)")) { New-WebAppPool -Name $s.Name | Out-Null }
        Set-ItemProperty "IIS:\Sites\$($s.Name)" -Name applicationPool -Value $s.Name
      }
    }
  }
}

$PartChecks += New-PropCheck -Id '1.6' -Title "Ensure 'application pool identity' is configured for anonymous user identity" -Level 1 -Wave 2 `
  -Filter 'system.webServer/security/authentication/anonymousAuthentication' -Name 'userName' -Scope 'Iis' `
  -Good { param($v) "$v" -eq '' } -Want 'empty' -SetValue ''

$PartChecks += @{
  Id = '1.7'; Title = "Ensure 'WebDav' feature is disabled"; Level = 1; Wave = 1; Reboot = $false
  FixHint = 'Uninstall-WindowsFeature Web-DAV-Publishing'
  Test = {
    param($c)
    if (-not (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)) { New-Row 'Web-DAV-Publishing' 'ERROR' 'Get-WindowsFeature not available (Windows Server only)'; return }
    $f = Get-WindowsFeature -Name Web-DAV-Publishing
    if ($f.Installed) { New-Row 'Web-DAV-Publishing' 'FAIL' 'feature is installed' } else { New-Row 'Web-DAV-Publishing' 'PASS' 'feature not installed' }
  }
  Fix = { param($c) Uninstall-WindowsFeature -Name Web-DAV-Publishing | Out-Null }
}

$PartManual = @(
  @{ Id = '1.1'; Level = 1; Title = "Ensure 'Web content' is on non-system partition" }
)
