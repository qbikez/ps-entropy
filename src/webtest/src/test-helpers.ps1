$Global:errorsDict = @()
$Global:successDict = @()


function Wrap-Response(
[Parameter(Mandatory=$true)] [uri] $uri,
[Parameter(Mandatory=$true)] [scriptblock] $scriptblock,
[Parameter(Mandatory=$false)] [string] $body = ""
)
{

    try {
        $resp = Invoke-Command -ScriptBlock $scriptblock
        $s = New-Object -TypeName PSObject -Property @{ "Url" = $uri; "Response" = $resp; "Body"= $body; "Message" = $null }
        $Global:successDict += $s    
        return $s   
    }
    catch {
        $err = New-Object -TypeName PSObject -Property @{ "Url" = $uri; "Message" = $_.Exception.Message; "Body"= $body; "Response" = $null }
        $Global:errorsDict += $err
        return $err
    }
}


function New-TestResult(
[Parameter(Mandatory=$true)][int] $totalCount,
[Parameter(Mandatory=$true)][int] $errorsCount,
[Parameter(Mandatory=$false)][int] $failureCount = 0,
[Parameter(Mandatory=$false)][int] $inconclusiveCount = 0
) {

    $result = New-Object -TypeName pscustomobject -Property @{
            timestamp = get-date
            all = $totalCount
            errors = $errorsCount
            failures = $failureCount
            inconclusive = $inconclusiveCount
        }

        return $result
}

function Test-RestApi(
[Parameter(Mandatory=$true)] [Microsoft.PowerShell.Commands.WebRequestMethod] $Method,
[Parameter(Mandatory=$true)] [uri] $uri,
[Parameter(Mandatory=$false)] [string] $body = "", 
$proxy = $null,
$timeoutSec = 60,
$retries = 3
) 
{
    while ($retries -gt 0) {
        try {
            $retries--
            write-verbose "invoking rest $method $url $body timeout=$timeoutSec"
            if ($proxy -ne $null) {
                write-verbose "using proxy: $proxy"
            }
            $p = @{
                method = $method
                uri = $uri
                proxy = $proxy
            }
            if ($method -eq [Microsoft.PowerShell.Commands.WebRequestMethod]::Post) {
                $p.Body = $body
            }
            if ($timeoutSec -ne $null) {
                $p.timeoutSec = $timeoutSec
            }

            $resp = Invoke-RestMethod @p
            
        
            $s = New-Object -TypeName PSObject -Property @{ "Url" = $uri; "Response" = $resp; "Body"= $body; "Message" = $null }
            $Global:successDict += $s
            write-verbose "$method $url DONE"

            return $s
            
        } catch [Exception] {
            if ($retries -gt 0) {
                continue
            }
            $err = New-Object -TypeName PSObject -Property @{ "Url" = $uri; "Message" = $_.Exception.Message; "Body"= $body; "Response" = $null }
            $Global:errorsDict += $err
            return $err
        }
    }
}




function Test-Server(
[Parameter(Mandatory=$true)] [string] $hostname,
[Parameter(Mandatory=$true)] [string] $path,
[string] $body,
[Microsoft.PowerShell.Commands.WebRequestMethod] $method = [Microsoft.PowerShell.Commands.WebRequestMethod]::Post,
$proxy = $null
)
{
    if (!$hostname.StartsWith("http")) {
        $baseUri = "http://$hostname"
    }
    $url = "$baseUri/$path"

    $r = Test-RestApi -Method $method -Uri "$url" -Body $body -proxy $proxy
    return $r
}

function Test-Url(
[Parameter(Mandatory=$true)] [string] $url,
[string] $body,
[Microsoft.PowerShell.Commands.WebRequestMethod] $method = [Microsoft.PowerShell.Commands.WebRequestMethod]::Get,
$proxy = $null,
[pscredential] $credentials = $null,
[Alias("SessionVariable")]$SessionOutVariable = $null,
[Alias("WebSession")]$session = $null,
[switch][bool]$autosession = $false,
[switch][bool]$noredirects,
$headers = @{},
$timeoutSec = $null
)
{
    $uri = $url
    try {
        if ($proxy -ne $null) {
            write-verbose "using proxy: $proxy"
        }
        $maxRedirects = $null
        if ($noredirects) {
            $maxRedirects = 0
        }
        if ($credentials -ne $null) {        
            $username = $credentials.UserName
            $password = $credentials.GetNetworkCredential().Password
            $headers += @{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username+":"+$password ))} 
            #$maxRedirects = 0
        }
        $a = @{
            Method = $Method
            Uri = $uri
        }

        if ($proxy -ne $null) { $a += @{ Proxy = $proxy } }
        if ($method -eq [Microsoft.PowerShell.Commands.WebRequestMethod]::Post) { $a += @{ Body = $body } }
        if ($credentials -ne $null) { $a += @{ Credential = $credentials; }  }
        if ($maxRedirects -ne $null) { $a += @{ MaximumRedirection = $maxRedirects } }
        if ($timeoutSec -ne $null) { $a += @{ TimeoutSec = $timeoutSec } }

        if ($autosession) { 
            if (!(test-path "variable:_websession") -or $_websession -eq $null) {
                $a += @{ SessionVariable = "_websession" }
				$SessionOutVariable = "_websession"
            } else {
                $a += @{ WebSession = $_websession }
            }
        }
        else 
        {
            if ($SessionOutVariable -ne $null) {
                $a += @{ SessionVariable = $SessionOutVariable }
            }
            elseif ($session -ne $null) {
                $a += @{ Session = $session }
            }
        }

        if ($headers -ne $null) {
            $a += @{ Headers = $headers }
        }

        write-verbose "invoking web $method $url $body."
        write-verbose "args="
        #$a | format-table | out-string | Write-Verbose
        

        $resp = Invoke-WebRequest @a -ErrorAction SilentlyContinue -UseBasicParsing
        if ($SessionOutVariable -ne $null) { 
               set-variable $SessionOutVariable -Value ((get-variable $SessionOutVariable)).Value -Scope script
        }
        
        $s = New-Object -TypeName PSObject -Property @{ "Url" = $uri; "Response" = $resp; "Body"= $body; "Message" = $null }
        $Global:successDict += $s
        write-verbose "$method $url DONE"

        return $s
        
    } catch [Exception] {
        $err = New-Object -TypeName PSObject -Property @{ "Url" = $uri; "Message" = $_.Exception.Message; "Body"= $body; "Response" = $null }
        
        return $err
    }
}



function start-iisexpress(
    [Parameter(Mandatory=$true, ParameterSetName="path")]$path, 
    [Parameter(Mandatory=$true, ParameterSetName="path")]
    [Parameter(Mandatory=$false, ParameterSetName="config")]
    $port,
    [Parameter(Mandatory=$true, ParameterSetName="config")]$config,
    [Parameter(Mandatory=$true, ParameterSetName="config")]$site,
    [switch][bool]$forcestart,
    $timeout = 180

) {
# TODO: start server on a random port and pass it to tests
# so other concurrent builds don't get in the way
    $start = get-date

    $outfile = "iisexpress-stdout.txt"
    $errfile = "iisexpress-stderr.txt"
    $bound = $PSBoundParameters
    try {
       
            if ($path -ne $null) {
                $path = (get-item $path).FullName
                $bound 
                $a ="/path:$path","/port:$port","/systray:false"
                start-app "C:\Program Files (x86)\IIS Express\iisexpress.exe" -argumentList $a @bound | write-output
            } else { # path -eq $null
                $config = (get-item $config).FullName
                write-warning "starting iis express from config: $config"    
                $app = start-process -FilePath "C:\Program Files (x86)\IIS Express\iisexpress.exe" -ArgumentList "/config:$config","/site:$site" -PassThru
                
                # should return $app even if further testing fails, so we can kill hanging processes
                write-output $app
                
                $tries = 5
                $ports = @($port)
                foreach($port in $ports) {
                    $null = wait-tcp $port -message "iisexpress" -timeout $timeout
                    $null = wait-http "http://localhost:$port" -message 'iisexpress' -timeout $timeout
                }
                $iisstarted = $true
            }
       
        
        $elapsed = (get-date) - $start
        write-host "iisexpress is up at http://localhost:$port after $elapsed"
    } finally {
        Write-Indented "==== iisexpress $path =============" -mark "== "
        if (test-path $outfile) { cat $outfile | Write-Indented -mark "=out= "}
        if (test-path $errfile) { cat $errfile | Write-Indented -mark "=err= " }
        Write-Indented "=== iisexpress $path output END ===" -mark "== "
    }
}



function start-app {
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]$path, 
    [switch][bool]$forcestart,
    $port,
    $argumentList,
    $timeout = 120,
    [switch][bool] $http,
    [switch][bool] $captureOutput = $true
) 
    $auto = $true
    $exec = split-path -leaf $path
    $start = get-date

    $outfile = "$($exec)-stdout.txt"
    $errfile = "$($exec)-stderr.txt"
  
    try {
        if ((test-path $path)) {
            $path = (get-item $path).FullName    
        } else {
            # assume app is on PATH
        }
        
        write-warning "starting app '$path'"    

        Write-Verbose "looking for running processes '$exec'"
        $existing = @(Get-WmiObject win32_process | ? { $_.ProcessName -eq $exec })
        if ($existing.count -gt 0) {
            if ($forcestart) {
                $existing | % { 
                    Write-Warning "stopping process $($_.Handle) $($_.Path)"
                    stop-process -Id $_.Handle 
                }
            }
            $existing = @(Get-WmiObject win32_process | ? { $_.ProcessName -eq $exec })
        } 
        if ($existing.count -gt 0) {
            write-warning "$exec is already running. use -forcestart to force restart"            
        }
        else {
            $a = @{}        
            if ($argumentList -ne $null) { $a += @{ ArgumentList = $argumentList }}
            if ($captureOutput) {
                $a += @{
                    RedirectStandardOutput=$outfile 
                    RedirectStandardError=$errfile
                }
            }

            $app = start-process -WorkingDirectory "." -FilePath "$path" @a -PassThru 
            #$app | format-table | out-string | Write-Warning     

            # should return $app even if further testing fails, so we can kill hanging processes
            write-output $app
        }
        
        if ($port -ne $null) {
            wait-tcp $port -message "$exec" -timeout $timeout
        }

        if ($port -ne $null -and $http) {
            wait-http "http://localhost:$port" -message "$exec" -timeout $tries
            $iisstarted = $true                
        }

        $elapsed = (get-date) - $start
        write-host "$exec is up and running after $elapsed"
    }
    finally {
        Write-Indented "==== $exec =============" -mark "== "
        if (test-path $outfile) { cat $outfile | Write-Indented -mark "=out= "}
        if (test-path $errfile) { cat $errfile | Write-Indented -mark "=err= " }
        Write-Indented "=== $exec output END ===" -mark "== "
    }
}

function test-port {

   [cmdletbinding()]
    Param(
        [parameter(ParameterSetName='ComputerName', Position=0)]
        [string]
        $ComputerName,

        [parameter(ParameterSetName='IP', Position=0)]
        [System.Net.IPAddress]
        $IPAddress,

        [parameter(Mandatory=$true , Position=1)]
        [int]
        $Port,

        [parameter(Mandatory=$false, Position=2)]
        [ValidateSet("TCP", "UDP")]
        [string]
        $Protocol = "TCP",
        $timeoutMs = 2000
        )

    $RemoteServer = If ([string]::IsNullOrEmpty($ComputerName)) {$IPAddress} Else {$ComputerName};

    If ($Protocol -eq 'TCP')
    {
        $test = New-Object System.Net.Sockets.TcpClient;
        Try
        {
            Write-verbose "Connecting to $RemoteServer :$Port (TCP)..";
            $r = $test.BeginConnect($RemoteServer, $Port, $null, $null);
            $s = $r.AsyncWaitHandle.WaitOne([timespan]::FromMilliseconds($timeoutMs));
            if (!$s) {
                throw "connection timed out after $timeoutMs ms."
            }
            Write-verbose "Connection successful"
            return $true
        }
        Catch
        {
            Write-verbose "Connection failed: $($_.Exception.Message)"
            return $false
        }
        Finally
        {
            $test.Dispose()
        }
    }

    If ($Protocol -eq 'UDP')
    {
        Write-warning "UDP port test functionality currently not available."
        <#
        $test = New-Object System.Net.Sockets.UdpClient;
        Try
        {
            Write-Host "Connecting to "$RemoteServer":"$Port" (UDP)..";
            $test.Connect($RemoteServer, $Port);
            Write-Host "Connection successful";
        }
        Catch
        {
            Write-Host "Connection failed";
        }
        Finally
        {
            $test.Dispose();
        }
        #>
    }

}


function wait-tcp ($port, $message, $timeout = 120) {
     # test TCP connection
     $scanstart = get-date
     while(!(test-port localhost $port)) {
         $elapsed = (get-date) - $scanstart
         write-host "waiting for $message to be available at port $port... [$elapsed] timeout=$timeout"

         #if ($app.HasExited) { throw "process $($app.Name) $($app.Id) has exited with code $($app.ExitCode)"}

         start-sleep -Seconds 1
         
         if ($elapsed.TotalSeconds -ge $timeout) {
             write-warning "failed to start process '$message' after $($timeout)s timeout"
             throw "failed to start process '$message' after $($timeout)s timeout"
         }
     }
     $elapsed = (get-date) - $scanstart
     write-host "port $port is available after $elapsed"

}

function wait-http ($url, $message, $timeout = 180, $retries = 5) {
    $tries = $retries
    $timeout = [int]($timeout / [float]$tries)
    while($tries -gt 0) {
        try {
            write-verbose "testing http protocol for $message at $url with timeout $($timeout)s. tries left=$tries"
            $req = Invoke-WebRequest "$url" -UseBasicParsing -TimeoutSec $timeout
            break
        } catch {
            write-verbose "   http request FAILED: $($_.Exception.Message)"
           # if ($app.HasExited) { throw "process $($app.Id) has exited with code $($app.ExitCode)"}
            $tries--
            if ($tries -le 0) { throw }
        }
    }
}