param ($path = ".")

function ExitWithCode {
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

    write-host "running azure-pipelines test script. artifacts dir = $((gi $artifacts).FullName)"

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

    write-host "pester result = '$testResultCode' lastexitcode=$lastexitcode"

    ExitWithCode 0

}
catch {
    ExitWithCode 1
}
