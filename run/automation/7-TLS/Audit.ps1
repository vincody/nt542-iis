<#
  Audit.ps1 - part 7 (Transport Encryption): READ-ONLY check of the Automated items, Manual items are listed as MANUAL.
  Changes nothing. Results go to ..\out\<time>-part7-audit\ (results.csv, results.json, report.html).
  Run from a PowerShell window started as Administrator:  .\Audit.ps1
  Useful: -Id '1.3' (one item, always quote ids), -AllL2 (include every L2 item), -Label before
#>
[CmdletBinding()]
param(
  [string[]]$Id,
  [switch]$AllL2,
  [string]$Label = '',
  [string]$OutDir = (Join-Path $PSScriptRoot '..\out')
)
. (Join-Path $PSScriptRoot '..\scripts\Common.ps1')
. (Join-Path $PSScriptRoot 'checks.ps1')

$lbl = 'part7-audit'
if ($Label) { $lbl += "-$Label" }
Invoke-CisRun -Checks $PartChecks -Manual $PartManual -Mode Audit -Id $Id -AllL2:$AllL2 -Label $lbl -OutDir $OutDir -Heading 'CIS IIS 10 - part 7 - Audit'
