param ($path = ".", [switch][bool]$EnableExit = $false, [switch][bool]$coverage=$true)

#$env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", [System.EnvironmentVariableTarget]::User)

import-module pester -MinimumVersion 6.0

$artifacts = "$path\artifacts"

if (!(test-path $artifacts)) { $null = new-item -type directory $artifacts }

write-host "running tests. artifacts dir = $((gi $artifacts).FullName)"

$config = New-PesterConfiguration
$config.Run.Path = "$path"
$config.Run.PassThru = $true
$config.Run.Exit = [bool]$EnableExit
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = "NUnitXml"
$config.TestResult.OutputPath = "$artifacts\test-result.xml"
$config.Output.Verbosity = "Detailed"

if ($coverage) {
    $codeCoverage = @(Get-ChildItem "$path" -Filter "*.ps1" -Exclude "*.tests.ps1" -Recurse) | % { $_.FullName }

    Write-Host "testing code coverage of files:"
    $codeCoverage | % { write-host $_ }

    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = $codeCoverage
    $config.CodeCoverage.OutputPath = "$artifacts\coverage.xml"
}

$r = Invoke-Pester -Configuration $config

return $r