<#
  IIS-CIS.ps1 - ONE-SHOT runner for the whole CIS Microsoft IIS 10 Benchmark v1.2.1 (all 7 parts).
  Modes:
    Audit      read-only check of every in-scope Automated item, writes CSV/JSON/HTML
    Remediate  fix FAIL items of the chosen waves (-Wave 1,2,3), backup first, re-check after
    Report     build a before/after HTML report from two CSV files (no IIS needed)
  The check definitions are NOT in this file: they are in <part>\checks.ps1 (same ones the per-part
  Audit.ps1 / Remediate.ps1 use). Run from a PowerShell window started as Administrator.
  Always quote ids on the command line: -Id '3.10','7.10'  (unquoted 3.10 becomes 3.1).
  File is ASCII only.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [ValidateSet('Audit', 'Remediate', 'Report')][string]$Mode = 'Audit',
  [ValidateSet(1, 2, 3)][int[]]$Wave,
  [string[]]$Id,
  [switch]$AllL2,
  [switch]$Force,
  [switch]$ForceHighRisk,
  [string]$Label = '',
  [string]$OutDir = (Join-Path $PSScriptRoot '..\out'),
  [hashtable]$HostMap = @{},
  [string]$HostSuffix = 'lab.local',
  [string]$LogDir = 'D:\IISLogs',
  [string[]]$AllowedExtensions = @('.html', '.htm', '.css', '.js', '.png', '.jpg', '.jpeg', '.gif', '.ico', '.svg', '.txt', '.woff', '.woff2', '.aspx', '.asp'),
  [string]$BeforeCsv,
  [string]$AfterCsv
)
. (Join-Path $PSScriptRoot 'Common.ps1')

if ($Mode -eq 'Report') {
  Invoke-CisReport -BeforeCsv $BeforeCsv -AfterCsv $AfterCsv -OutDir $OutDir
  return
}

$root = Split-Path -Path $PSScriptRoot -Parent
$allChecks = @()
$allManual = @()
foreach ($part in '1-Basic', '2-AuthN-AuthZ', '3-ASPNET', '4-RequestFiltering', '5-Logging', '6-FTP', '7-TLS') {
  . (Join-Path $root "$part\checks.ps1")
  $allChecks += $PartChecks
  $allManual += $PartManual
}

Invoke-CisRun -Checks $allChecks -Manual $allManual -Mode $Mode -Wave $Wave -Id $Id -AllL2:$AllL2 -Force:$Force -ForceHighRisk:$ForceHighRisk -Label $Label -OutDir $OutDir -Heading "CIS IIS 10 - $Mode"
