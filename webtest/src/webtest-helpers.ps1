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


function Test-RestApi(
[Parameter(Mandatory=$true)] [Microsoft.PowerShell.Commands.WebRequestMethod] $Method,
[Parameter(Mandatory=$true)] [uri] $uri,
[Parameter(Mandatory=$false)] [string] $body = "", 
$proxy = $null,
$timeoutSec = 60,
$retries = 3
) 
{
    
    while($retries -gt 0) {
        try {        
            write-verbose "invoking rest $method $url $body"
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
            $retries--
            if ($retries -gt 0) { continue }
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

function Test-Url
{
    [CmdletBinding()]
    param(
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
        $timeoutSec = $null,
        $retries = 2,
        [switch][bool] $dispose = $true
    )
    $uri = $url
    try {
        if ($proxy -ne $null) {
            write-verbose "using proxy: $proxy"
        }
        $maxRedirects = $null
        if ($noredirects) {
            $maxRedirects = 0
        }
      
        $a = @{
            Method = $Method
            Uri = $uri
        }

        if ($proxy -ne $null) { $a += @{ Proxy = $proxy } }
        if ($method -eq [Microsoft.PowerShell.Commands.WebRequestMethod]::Post) { $a += @{ Body = $body } }
        if ($credentials -ne $null) { 
            $a += @{ Credential = $credentials; } 
            #$username = $credentials.UserName
            #$password = $credentials.GetNetworkCredential().Password
            #$headers += @{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username+":"+$password ))} 
            $maxRedirects = 0
        }
        if ($maxRedirects -ne $null) { $a += @{ MaximumRedirection = $maxRedirects } }

        if ($timeoutSec -eq $null) { $timeoutSec = 60 }
        $a += @{ TimeoutSec = $timeoutSec }

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
        
        
        # how many times should we retry in case of timeout?
        $tries = $retries
        while($tries -gt 0) {
            try {
                # when session is needed, use invoke-webrequest
                # otherwise, use .Net WebRequest
                if ($a.Session -eq $null -and $a.WebSession -eq $null -and $a.SessionVariable -eq $null){ 
                    write-verbose "sending WebRequest: $method $url $body. Timeout=$timeoutSec"
                    #$webclient = new-object System.Net.WebClient
                    #$webclient.Credentials = $a.Credential.GetNetworkCredential()                
                    #$webpage = $webclient.DownloadString($url)

                    $request = [System.Net.WebRequest]::Create($url)
                    $request.Timeout = $timeoutSec * 1000
                    $request.ReadWriteTimeout = $timeoutSec * 1000
                    if ($a.credential -ne $unll) {
                        $request.Credentials = $a.Credential.GetNetworkCredential()                
                    }
                    if ($a.headers -ne $null) {
                        foreach($h in $a.headers.GetEnumerator()) {
                            if ($h.key -eq "Content-Type") {
                                $request.ContentType = $h.value
                            }
                            else {
                                $request.Headers.Add($h.key, $h.value)
                            }
                        }
                    }
                    if ($a.MaximumRedirection -ne $null) {
                        if ($a.MaximumRedirection -eq 0) { $request.AllowAutoRedirect = $false }
                        else { $request.MaximumAutomaticRedirections = $a.MaximumRedirection }
                    }
                    if ($a.proxy -ne $null) {
                        $webproxy = new-object System.Net.WebProxy $a.proxy
                        $a.proxy = $webproxy
                    }
                    if ($a.method -ne $null -and $a.method -ne "GET") {
                        $request.Method = $a.method
                    }
                    if ($a.body -ne $null) {                                                
                        $s = $request.GetRequestStream()
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                        $s.Write($bytes, 0, $bytes.length)                        
                    }

                    $resp = $request.GetResponse()

                    $bytes = new-object "byte[]" $resp.ContentLength
                    $total = 0
                    $s = $resp.GetResponseStream()
                    do {
                        $read = $s.Read($bytes, $total, $bytes.Length - $total)
                        if ($read -le 0) { break }
                        $total += $read
                    } while ($total -lt $bytes.Length)
                    $respContent =  [System.Text.Encoding]::UTF8.GetString($bytes)
                }
                else {
                    write-verbose "invoking web: $method $url $body. Timeout=$timeoutSec"
                    write-verbose "args="
                    $a | format-table | out-string | Write-Verbose

                    $resp = Invoke-WebRequest @a -ErrorAction SilentlyContinue -UseBasicParsing 
                }
                if ($resp.StatusCode -eq 301 -or $resp.StatusCode -eq 302) {
                    # is that ok or not?
                }
                if ($resp.StatusCode -ne 200) {
                    throw "Invalid response statuscode: $($resp.StatusCode)"
                }
                return $resp
            } catch [Exception] {
                $msg = $_.Exception.Message
                $tries--
                if ($tries -gt 0) { 
                    if ($msg.Contains("timed out")) {
                        write-host "request timed out, retries left: $tries"
                        continue
                    } else {
                        write-warning "caught exception that does not cause retry: $_"
                        throw
                    }
                }
                else { 
                    write-warning "request failed. no retries left"
                    throw 
                }
            }
            finally {
                if ($webclient -ne $null) { try { $webclient.Dispose()} catch {} }
                if ($resp -ne $null) { 
                    if ($dispose) {
                        try  { $resp.dispose() } catch {} 
                    }
                    else {
                        try  { $resp.close() } catch {} 
                    }
                }
            }
        }

        if ($SessionOutVariable -ne $null) { 
               set-variable $SessionOutVariable -Value ((get-variable $SessionOutVariable)).Value -Scope script
        }
        
        $s = New-Object -TypeName PSObject -Property @{ "Url" = $uri; "Response" = $resp; "Body"= $body; "Message" = $null; "Ok" = $true }
        $Global:successDict += $s
        write-verbose "$method $url DONE"

        return $s
        
    } catch [Exception] {
        $msg = $_.Exception.Message
        if ($msg.Contains("timed out")) { $msg += " After $timeoutSec seconds" }
        $err = New-Object -TypeName PSObject -Property @{ "Url" = $uri; "Message" = $msg; "Body"= $body; "Response" = $_.Exception.Response; "Ok" = $false }
        
        return $err
    }
}

function Invoke-Url {
    [CmdletBinding()]
    param($url)

    $r = test-url $url -dispose:$false
    return $r
}