#Requires -RunAsAdministrator
<#
  01-Seed-Baseline.ps1 - OPTIONAL. Deliberately weaken the lab so the "before" audit has plenty of FAIL results.
  Run it once after 00-Setup-Lab.ps1 and BEFORE the first audit. Never run it on a real server.
  It changes the sample sites only (SiteA, SiteB). File is ASCII only.
#>
[CmdletBinding()]
param(
  [string]$Drive = 'D:',
  [switch]$InstallWebDav     # also installs WebDAV so item 1.7 shows FAIL
)
$ErrorActionPreference = 'Stop'
Import-Module WebAdministration

foreach ($s in 'SiteA', 'SiteB') {
  if (-not (Get-Website -Name $s -ErrorAction SilentlyContinue)) { throw "Site $s not found. Run 00-Setup-Lab.ps1 first." }
}

Write-Host '== 1.3 directory browsing ON for SiteB' -ForegroundColor Cyan
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST/SiteB' -Filter 'system.webServer/directoryBrowse' -Name enabled -Value $true

Write-Host '== groups 2-3: weak web.config for SiteA (Forms auth, clear passwords, debug, trace, customErrors off)' -ForegroundColor Cyan
$webConfig = @'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.web>
    <authentication mode="Forms">
      <forms loginUrl="login.aspx">
        <credentials passwordFormat="Clear">
          <user name="demo" password="demo123" />
        </credentials>
      </forms>
    </authentication>
    <compilation debug="true" />
    <customErrors mode="Off" />
    <trace enabled="true" />
  </system.web>
</configuration>
'@
Set-Content -Path "$Drive\wwwroot\SiteA\web.config" -Value $webConfig -Encoding UTF8

Write-Host '== 2.6 Basic authentication ON for SiteB (no SSL required)' -ForegroundColor Cyan
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location 'SiteB' -Filter 'system.webServer/security/authentication/basicAuthentication' -Name enabled -Value $true

if ($InstallWebDav) {
  Write-Host '== 1.7 installing WebDAV Publishing' -ForegroundColor Cyan
  Install-WindowsFeature -Name Web-DAV-Publishing | Out-Null
}

Write-Host ''
Write-Host 'Baseline seeded. Snapshot the VM, then run: .\IIS-CIS.ps1 -Mode Audit -Label before' -ForegroundColor Green
