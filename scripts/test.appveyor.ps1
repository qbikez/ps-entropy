param ($path = ".")

function ExitWithCode 
{ 
    param 
    ( 
        $exitcode 
    )

    $host.SetShouldExit($exitcode) 
    exit 
}

$artifacts = "$path\artifacts"

try {
    if (!(test-path $artifacts)) { $null = new-item -type directory $artifacts }
    if (test-path "$artifacts\test-result.xml") {
        remove-item "$artifacts\test-result.xml"
    }

write-host "running appveyor test script. artifacts dir = $((gi $artifacts).FullName)"

$testResultCode = & "$PSScriptRoot\test.ps1" (gi $path).FullName -EnableExit

if (!(test-path "$artifacts\test-result.xml")) {
    throw "test results not found at $artifacts\test-result.xml!"
}

if (!(test-path "$artifacts\test-result.xml")) {
        throw "test artifacts not found at '$artifacts\test-result.xml'!"
}
    
$resultpath = (get-item "$artifacts\test-result.xml").FullName
$content = get-content "$artifacts\test-result.xml" | out-string
if ([string]::isnullorwhitespace($content)) {
    throw "$artifacts\test-result.xml is empty!"
}
else {
    $content     
}

$url = "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)"
#$url = https://ci.appveyor.com/api/testresults/nunit/bq558ckwevwb47qb
# upload results to AppVeyor
write-host "uploading test result from $resultpath to $url"
$wc = New-Object 'System.Net.WebClient'

try {
    $r = $wc.UploadFile($url, $resultpath)
    
    write-host "upload done. result = $r"
} 
finally {
    $wc.Dispose()
}
write-host "pester result = '$testResultCode' lastexitcode=$lastexitcode"

#ExitWithCode $testResultCode

} catch {
    ExitWithCode 1  
}
