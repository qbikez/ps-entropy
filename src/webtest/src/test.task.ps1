$urlPattern = "(\[(?<method>[A-Z]+)(\((?<data>.*)\)){0,1}\]){0,1}(?<protocol>http(s){0,1})://(?<creds>\?:\?@){0,1}(?<fullpath>(?<server>[^/]*)(?<path>.*))"
function run-TaskTest(
[parameter(mandatory=$true)]$desc,
[parameter(mandatory=$true)]$profile,
[switch][bool] $full,
$params = @{},
$psparams = $null)
{
    $tests = @()
    if (![string]::IsNullOrEmpty($profile.test)) {
        $tests = @($profile.test)
    }
    if ($full -and ![string]::IsNullOrEmpty($profile.full_test)) {
        $tests += @($profile.full_test)
    }
    if ($tests.Length -eq $null) {
        $profile = get-swapbaseprofile $profile
        if (![string]::IsNullOrEmpty($profile.test)) {
        $tests = @($profile.test)
        }
        if ($full -and ![string]::IsNullOrEmpty($profile.full_test)) {
            $tests += @($profile.full_test)
        }
    }

    if ($tests.Length -gt 0) {    
        $totalResult = New-Object -TypeName pscustomobject -Property @{
            timestamp = get-date
            all = 0
            errors = 0
            failures = 0
            inconclusive = 0
        }

        foreach($test in $tests) {
            if ($desc.test_type -ne $null) {
                $testtype = $desc.test_type
            }
            else {
                $testtype = $null
                if ($desc.test_fixture -ne $null) {
                    if ($desc.test_fixture.StartsWith("ps:") -or ($desc.test_fixture.EndsWith(".ps1"))) {
                        $testtype = "ps"
                        $desc.test_fixture = $desc.test_fixture -replace "ps:", ""
                    }
                    elseif ($desc.test_fixture.StartsWith("nunut:") -or ($desc.test_fixture.EndsWith(".dll")))
                    {
                         $testtype = "nunit"
                    }
                    else {
                        $testtype = $desc.test_fixture
                    }     
                }
                else {
                    if ($test -is [scriptblock]) {
                        $testtype = "script"
                    }     
                    elseif ($test.StartsWith("http") -or $test -match $urlPattern) {
                        $testtype = "webtest"
                    }     
                }       
                if ($testtype -eq $null) {
                    $testtype = "nunit"
                }              
            }
            if ($desc.settings -ne $null -and $desc.settings.siteAuth -ne $null) {
                $secpasswd = ConvertTo-SecureString $desc.settings.siteAuth.password -AsPlainText -Force
                $cred = New-Object System.Management.Automation.PsCredential $desc.settings.siteAuth.username,$secpasswd
            }
            if ($testtype -eq "nunit") {
                $testFixture = (get-item (join-path  ".." $desc.test_fixture)).FullName
                $result = run-nunittest $testFixture $test -Gui:$Gui
            }
            elseif ($testtype -eq "ps") {
                $testFixture = get-fullpath $profile $desc.test_fixture
                $result = run-pstest $testFixture $test -Gui:$Gui
            }
            elseif ($testtype -eq "webtest") {
                $timeout = $profile.test_timeout
                if ($timeout -eq $null) { $timeout = 120 }
                $retries = $profile.test_retries
                if ($retries  -eq $null) { $retries = 2 }
                $result = run-webtest $test -Gui:$Gui -credentials $cred -timeoutsec $timeout -retries $retries
            }
            elseif ($testtype -eq "webtest-rest" -or $testtype -eq "rest") {
                $timeout = $profile.test_timeout
                if ($timeout -eq $null) { $timeout = 120 }
                $result = run-webtest $test -Gui:$Gui -rest -credentials $cred -timeoutsec $timeout
            }        
            elseif ($testtype -eq "script") {
                $result = run-scripttest $profile $test -Gui:$Gui -params @{ profile = $profile }
            }      
            $result | Format-Table -Wrap | out-string | write-host
            
            $totalResult.all += $result.all
            $totalResult.errors += $result.errors
            $totalResult.failures += $result.failures
            $totalResult.inconclusive += $result.inconclusive  
        }
        $result = $totalResult
        #$result | write-output

        # TODO: extract a function for running different types of tests (Nunit, webtests, powershell, etc) with a common result class
        $lastResult = import-cache -dir "lgm-publish" -container "$(split-path -leaf $desc.proj).$($profile.profile).json"
        if ($lastResult -ne $null) {
            $lasterrors = [int]::MaxValue
            if (![string]::IsNullOrWhiteSpace($lastresult.errors)) {
                try {
                    $lastErrors = [int]$lastresult.errors
                }
                catch {
                    write-host $Error
                    $lasterrors = 0    
                }
            }            

            if ($lasterrors -ne $null -and $result.errors -gt $lasterrors) {
                $msg = "error number increased from $($lasterrors) to $($result.errors)"
                if (!$force) {
                    throw [BeamException]$msg
                } else {
                    write-error ("[FORCED]" + $msg)
                }
            }
            elseif ($result.errors -lt $lasterrors) {
                write-host -ForegroundColor Green "error number decreased from $($lasterrors) to $($result.errors)! Gratz!"
            }
            else {
                write-host -ForegroundColor Yellow "errors number hasn't changed. That's gotta count for something, right?"
            }
        }
        if ($result.errors -eq 0) {
            write-host -ForegroundColor Green "No Errors. AVESOME!"
        } 
        else {
            $msg = "$($result.errors) of $($result.all) test FAILED."
            write-host -ForegroundColor Red $msg
            throw [BeamException]$msg
        }
        export-cache -dir "lgm-publish" -container "$(split-path -leaf $desc.proj).$($profile.profile).json" $result
    }
}


function run-pstest($fixture, $test, [switch][bool] $Gui) {
    if ($gui) {
        write-host "starting powershell_ise for fixture $fixture"
        & powershell_ise $fixture
    }
    else {
        write-host "running test fixture from powershell script $fixture"

        $r = & $fixture $test
        $props = [ordered]@{
            timestamp = $r.timestamp
            all = $r.all
            errors = $r.errors
            failures = $r.failures
            inconclusive = $r.inconclusive
        }
        $result = New-Object -TypeName pscustomobject -Property $props
        return $result
    }
}

function run-nunittest($fixture, $test, [switch][bool] $Gui) {
    $run=$($test) -replace "`"", "\\\`""         

    if ($gui) {
        write-host "starting nunit gui for fixture $fixture"
        & nunit $fixture
    }
    else {
        write-host "running test fixture $run from assembly $fixture"
        $result = & nunit-console $fixture "/nologo" "/nodots" "/framework=net-4.5.1" "/run=$run"

        $regex = "Tests run: ([0-9]+), Errors: ([0-9]+), Failures: ([0-9]+), Inconclusive: ([0-9]+)"
        $lines = $result -match $regex 
        $m = $lines[0] -match $regex 
                
        $props =  [ordered]@{
            timestamp = get-date
            all = [int]$Matches[1]
            errors = [int]$Matches[2]
            failures = [int]$Matches[3]
            inconclusive = [int]$Matches[4] 
        }
        $result = New-Object -TypeName pscustomobject -Property $props

        return $result
    }
}

function run-scripttest([Parameter(Mandatory=$true)] $profile, $test, [switch][bool] $Gui, $params) {
    
    $output = run-script $profile $test $params
    $lastline = $output | select -last 1
    if ($lastline -match "Total: ([0-9]+), Errors: ([0-9]+), Failed: ([0-9]+), Skipped: ([0-9]+), Time: (.*)s") {
        $result = New-Object -TypeName pscustomobject -Property @{
            timestamp = get-date
            all = $Matches[1]
            errors = $Matches[3]
            failures = $Matches[2]
            inconclusive = 0
        }
    }
    else {
        $result = New-Object -TypeName pscustomobject -Property @{
            timestamp = get-date
            all = 1
            errors = 0
            failures = 0
            inconclusive = 1
        }
    }
    Write-Host ($output | Out-String)
    return $result
}


function run-webtest($test, [switch][bool] $Gui, [switch][bool]$rest, $credentials = $null, $timeoutsec = 120, $retries = 2)
{
    . "$PSScriptRoot\test-helpers.ps1"

    
    $urls = @($test)

    $ok = @()
    $errors = @()

    foreach($_ in $urls) {
        $url_printable = $_.Replace("?:?@","")
        write-host "testing url $url_printable with timeout=$timeoutsec retries=$retries"

        $hascreds = $false
        $reenter = $false

        # how many times should we ask for credentials when 401 happens
        $credential_tries = 2
        for ($i = $credential_tries; $i -gt 0; $i--) {
            $cred = $credentials
            $url = $_
            $method = "GET"
            $headers = @{}
            if ($_ -match $urlPattern) {
                $hascreds = $matches["creds"] -ne $null
                $server = $matches["server"]
                if ($matches["method"]) { $method = $matches["method"] }
                $body = $matches["data"]
                if ($body) {
                    $headers = @{
                        "Content-Type" = "application/x-www-form-urlencoded"
                    }
                }
                $url = "$($matches['protocol'])://$($matches["fullpath"])"
                $container = $server.Replace("?","_").Replace("=","_") 
                $container = "http_" + $container 
                
                if ($hascreds) {
                    $credmsg = "credentials for HTTP site $server" 
                    if ($reenter) { $credmsg = "reenter " + $credmsg }
                    $cred = get-credentialscached -container $container -message $credmsg -reset:($Global:clearCredentials -or $reenter) -Verbose
                }
            }        
            $proxy = $null
            if ($url.proxy -ne $null) {
                $proxy = $url.proxy
                $url = $url.url
            }
            if ($rest) {
                $r = Test-RestApi -uri $url -Method $method -proxy $proxy -timeoutsec:$timeoutsec -body $body -headers $headers #-noRedirects
            }
            else {
                $r = test-url $url -method $method -proxy $proxy -credentials $cred -timeoutsec:$timeoutsec -retries:$retries -body $body -headers $headers -autosession #-noRedirects
            }
            if ($r.Ok -eq $true) {
                $ok += $r
            }
            else {
                if ($r.Response -ne $null -and $r.Response.StatusCode -eq 401 -and ($i -gt 1))  {
                    write-warning "server responded with 401. Please reenter credentials for container '$container'"
                    $reenter = $true
                    continue
                }
                $r | Format-Table -Wrap | out-string | write-host 
                $errors += $r
            }
            break
        }
    }

    $result = New-Object -TypeName pscustomobject -Property @{
            timestamp = get-date
            all = $urls.Length
            errors = $errors.Length            
            failures = 0
            inconclusive = 0
        }

        return $result
}

