#Requires -RunAsAdministrator
<#
  00-Setup-Lab.ps1 - build the lab on a fresh Windows Server 2022 VM.
  Installs the IIS parts the CIS benchmark needs, then creates two sample sites, an HTTPS binding and an FTP site.
  Safe to run more than once (it skips what already exists). It does NOT install WebDAV on purpose
  (item 1.7 wants WebDAV absent). Run 01-Seed-Baseline.ps1 next if you want deliberately weak settings.
  File is ASCII only.
#>
[CmdletBinding()]
param(
  [string]$Drive = 'D:',                 # second virtual disk; used for site content and (later) logs
  [string]$CertDns = 'sitea.lab.local'   # name on the self-signed certificate
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path "$Drive\")) {
  throw "Drive $Drive not found. Add a second virtual disk to the VM, or pass -Drive C: (then items 1.1 and 5.1 cannot be demonstrated)."
}

Write-Host '== Installing IIS features' -ForegroundColor Cyan
Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-Net-Ext45, Web-ISAPI-Ext, Web-ISAPI-Filter, `
  Web-Basic-Auth, Web-Windows-Auth, Web-Url-Auth, Web-IP-Security, Web-Http-Logging, Web-Custom-Logging, `
  Web-Ftp-Server, Web-Mgmt-Console, Web-Scripting-Tools -IncludeManagementTools | Out-Null

Import-Module WebAdministration

Write-Host '== Creating sample sites (no host header on purpose)' -ForegroundColor Cyan
$sites = @{ 'SiteA' = 8081; 'SiteB' = 8082 }
foreach ($name in $sites.Keys) {
  $path = "$Drive\wwwroot\$name"
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  Set-Content -Path "$path\index.html" -Value "<h1>$name</h1>"
  if (-not (Get-Website -Name $name -ErrorAction SilentlyContinue)) {
    New-Website -Name $name -PhysicalPath $path -Port $sites[$name] -ApplicationPool 'DefaultAppPool' | Out-Null
    Write-Host "created site $name on port $($sites[$name])"
  } else { Write-Host "site $name already exists" }
}

Write-Host '== HTTPS binding with a self-signed certificate on SiteA' -ForegroundColor Cyan
if (-not (Get-WebBinding -Name 'SiteA' -Protocol https -ErrorAction SilentlyContinue)) {
  $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq "CN=$CertDns" } | Select-Object -First 1
  if (-not $cert) { $cert = New-SelfSignedCertificate -DnsName $CertDns -CertStoreLocation Cert:\LocalMachine\My }
  New-WebBinding -Name 'SiteA' -Protocol https -Port 443 -SslFlags 0
  (Get-WebBinding -Name 'SiteA' -Protocol https).AddSslCertificate($cert.Thumbprint, 'My')
  Write-Host "HTTPS binding added (thumbprint $($cert.Thumbprint))"
} else { Write-Host 'HTTPS binding already exists' }

Write-Host '== FTP site (not encrypted yet, for group 6)' -ForegroundColor Cyan
New-Item -ItemType Directory -Path "$Drive\ftproot" -Force | Out-Null
if (-not (Get-Website -Name 'FtpLab' -ErrorAction SilentlyContinue)) {
  New-WebFtpSite -Name 'FtpLab' -Port 21 -PhysicalPath "$Drive\ftproot" -Force | Out-Null
  Write-Host 'created FTP site FtpLab'
} else { Write-Host 'FTP site FtpLab already exists' }

Write-Host ''
Write-Host 'Lab is ready. Take a VM snapshot now. Next: 01-Seed-Baseline.ps1 (optional), then IIS-CIS.ps1 -Mode Audit -Label before' -ForegroundColor Green
