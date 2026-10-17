<#
  Remediate.ps1 - part 6 (FTP Requests): fixes the FAIL items of the Automated checks, then re-checks them.
  Backs up the IIS configuration first. Waves: 1 = low risk, 2 = medium, 3 = high (always asks y/N unless -ForceHighRisk).
  Default is all waves, and waves 1-2 ask y/N per item unless you add -Force.
  Try first without changing anything:  .\Remediate.ps1 -WhatIf
  Run from a PowerShell window started as Administrator.  Always quote ids: -Id '3.10'.
  Part 6 has only Manual items (6.1, 6.2): there is nothing to fix automatically, so this script only says so.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [ValidateSet(1, 2, 3)][int[]]$Wave = @(1, 2, 3),
  [string[]]$Id,
  [switch]$AllL2,
  [switch]$Force,
  [switch]$ForceHighRisk,
  [string]$Label = '',
  [string]$OutDir = (Join-Path $PSScriptRoot '..\out')
)
. (Join-Path $PSScriptRoot '..\scripts\Common.ps1')
. (Join-Path $PSScriptRoot 'checks.ps1')

$lbl = 'part6-remediate'
if ($Label) { $lbl += "-$Label" }
Invoke-CisRun -Checks $PartChecks -Manual $PartManual -Mode Remediate -Wave $Wave -Id $Id -AllL2:$AllL2 -Force:$Force -ForceHighRisk:$ForceHighRisk -Label $lbl -OutDir $OutDir -Heading 'CIS IIS 10 - part 6 - Remediate'
