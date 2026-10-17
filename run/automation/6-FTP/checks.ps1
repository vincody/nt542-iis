# checks.ps1 - CIS IIS 10 benchmark, part 6: FTP Requests
# Definitions only (nothing runs here). Dot-sourced by Audit.ps1, Remediate.ps1 and ..\scripts\IIS-CIS.ps1.
# Automated items are in $PartChecks, Manual items (listed in the report, done by hand) in $PartManual.
# File is ASCII only.

$PartChecks = @()


$PartManual = @(
  @{ Id = '6.1'; Level = 1; Title = 'Ensure FTP requests are encrypted' },
  @{ Id = '6.2'; Level = 1; Title = 'Ensure FTP Logon attempt restrictions is enabled' }
)
