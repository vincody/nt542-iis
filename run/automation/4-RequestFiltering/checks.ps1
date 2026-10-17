# checks.ps1 - CIS IIS 10 benchmark, part 4: Request Filtering and Other Restriction Modules
# Definitions only (nothing runs here). Dot-sourced by Audit.ps1, Remediate.ps1 and ..\scripts\IIS-CIS.ps1.
# Automated items are in $PartChecks, Manual items (listed in the report, done by hand) in $PartManual.
# File is ASCII only.

if (-not $AllowedExtensions) { $AllowedExtensions = @('.html', '.htm', '.css', '.js', '.png', '.jpg', '.jpeg', '.gif', '.ico', '.svg', '.txt', '.woff', '.woff2', '.aspx', '.asp') }

$PartChecks = @()

$ReqLimits = 'system.webServer/security/requestFiltering/requestLimits'
$ReqFilter = 'system.webServer/security/requestFiltering'

$PartChecks += New-PropCheck -Id '4.2' -Title "Ensure 'maxURL request filter' is configured" -Level 2 -Wave 1 `
  -Filter $ReqLimits -Name 'maxUrl' -Scope 'Iis' -Good { param($v) ([int]$v -gt 0) -and ([int]$v -le 4096) } -Want '1..4096' -SetValue 4096

$PartChecks += New-PropCheck -Id '4.3' -Title "Ensure 'MaxQueryString request filter' is configured" -Level 2 -Wave 1 `
  -Filter $ReqLimits -Name 'maxQueryString' -Scope 'Iis' -Good { param($v) ([int]$v -gt 0) -and ([int]$v -le 2048) } -Want '1..2048' -SetValue 2048

$PartChecks += New-PropCheck -Id '4.4' -Title 'Ensure non-ASCII characters in URLs are not allowed' -Level 2 -Wave 2 `
  -Filter $ReqFilter -Name 'allowHighBitCharacters' -Scope 'Iis' -Good { param($v) "$v" -eq 'False' } -Want 'False' -SetValue $false

$PartChecks += New-PropCheck -Id '4.5' -Title 'Ensure Double-Encoded requests will be rejected' -Level 1 -Wave 2 `
  -Filter $ReqFilter -Name 'allowDoubleEscaping' -Scope 'Iis' -Good { param($v) "$v" -eq 'False' } -Want 'False' -SetValue $false

$PartChecks += New-PropCheck -Id '4.7' -Title 'Ensure Unlisted File Extensions are not allowed' -Level 1 -Wave 3 `
  -Filter 'system.webServer/security/requestFiltering/fileExtensions' -Name 'allowUnlisted' -Scope 'Iis' `
  -Good { param($v) "$v" -eq 'False' } -Want 'False' -SetValue $false `
  -Fix {
    param($c)
    $f = 'system.webServer/security/requestFiltering/fileExtensions'
    foreach ($ext in $AllowedExtensions) {
      $e = Get-WebConfiguration -PSPath $AppHostPath -Filter "$f/add[@fileExtension='$ext']"
      if ($e) { Set-WebConfigurationProperty -PSPath $AppHostPath -Filter "$f/add[@fileExtension='$ext']" -Name allowed -Value $true }
      else { Add-WebConfigurationProperty -PSPath $AppHostPath -Filter $f -Name '.' -Value @{ fileExtension = $ext; allowed = $true } }
    }
    foreach ($p in @(Get-IisPaths)) {
      if ("$(Get-Cfg $c.Filter $c.Name $p.PSPath)" -ne 'False') { Set-Cfg $c.Filter $c.Name $false $p.PSPath }
    }
  }
$PartChecks[-1].FixHint = 'Allow the extensions in -AllowedExtensions, then set allowUnlisted=False (can break the site: test it)'

$PartChecks += New-PropCheck -Id '4.9' -Title "Ensure 'notListedIsapisAllowed' is set to false" -Level 1 -Wave 1 `
  -Filter 'system.webServer/security/isapiCgiRestriction' -Name 'notListedIsapisAllowed' -Scope 'Server' -Good { param($v) "$v" -eq 'False' } -Want 'False' -SetValue $false

$PartChecks += New-PropCheck -Id '4.10' -Title "Ensure 'notListedCgisAllowed' is set to false" -Level 1 -Wave 1 `
  -Filter 'system.webServer/security/isapiCgiRestriction' -Name 'notListedCgisAllowed' -Scope 'Server' -Good { param($v) "$v" -eq 'False' } -Want 'False' -SetValue $false

$PartManual = @(
  @{ Id = '4.1'; Level = 2; Title = "Ensure 'maxAllowedContentLength' is configured" },
  @{ Id = '4.6'; Level = 1; Title = "Ensure 'HTTP Trace Method' is disabled" },
  @{ Id = '4.8'; Level = 1; Title = 'Ensure Handler is not granted Write and Script/Execute' },
  @{ Id = '4.11'; Level = 1; Title = "Ensure 'Dynamic IP Address Restrictions' is enabled" }
)
