param ($path = ".", [switch][bool]$EnableExit = $false, [switch][bool]$coverage=$true)

#$env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", [System.EnvironmentVariableTarget]::User)

import-module pester -MinimumVersion 4.4 -MaximumVersion 4.99

$artifacts = "$path\artifacts"

if (!(test-path $artifacts)) { $null = new-item -type directory $artifacts }

write-host "running tests. artifacts dir = $((gi $artifacts).FullName)"

if (!(Test-Path $artifacts)) {
    $null = new-item $artifacts -ItemType directory
}
if ($coverage) {
    $codeCoverage = @(Get-ChildItem "$path" -Filter "*.ps1" -Exclude "*.tests.ps1" -Recurse) | % { $_.FullName }

    Write-Host "testing code coverage of files:"
    $codeCoverage | % { write-host $_ }
} else {
    $codeCoverage = $null
}

$r = Invoke-Pester "$path" -OutputFile "$artifacts\test-result.xml" -OutputFormat NUnitXml -EnableExit:$EnableExit -CodeCoverage $codeCoverage

return $r
