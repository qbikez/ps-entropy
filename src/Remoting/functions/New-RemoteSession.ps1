function New-RemoteSession { 
[CmdletBinding()]
param(
    [parameter(Mandatory=$true)] $ComputerName,
    [switch][bool] $NoSsl,
    [switch][bool] $Ssl,
    [switch][bool] $Reuse = $true,
    $ServerInfo = $null,
    [switch][bool] $ClearCredentials,
    $port,
    [switch][bool] $cim,
    [parameter(Mandatory=$false)] 
    [pscredential]
    #[System.Management.Automation.Credential()]
    $credential = [pscredential]::Empty,
    [System.Management.Automation.Runspaces.AuthenticationMechanism] $Authentication = [System.Management.Automation.Runspaces.AuthenticationMechanism]::negotiate,
    [switch][bool] $reloadSessionMap = $false
)  
    $map = find-sessionmap -reload:$reloadSessionMap
    $bound = $PSBoundParameters
    if ($bound.reloadSessionMap -ne $null) { $null = $bound.Remove("reloadSessionMap")  }
    if ($bound.ErrorAction -ne $null) { $null = $bound.Remove("ErrorAction")  }
    try {
        $Error.Clear()
        write-verbose "===> connecting with '$Authentication' auth method"
        $s = $null
	    $s = _new-remotesession @bound -ErrorAction:SilentlyContinue
    } 
    catch {
        # this was the first try, ignore erorrs
        write-verbose $_
    }

    
    if ($s -ne $null) {
        write-verbose "I have some session:"
        $s | format-table | out-string | write-verbose
    }
    else {
        if ($Error.Count -eq 0) {
        } 
    }
    if ($Error.Count -gt 0 -or $s -eq $null) {
        write-verbose "===> fallback: connecting with manual credentials"
        #$bound["Authentication"] = [System.Management.Automation.Runspaces.AuthenticationMechanism]::Basic
        try {
            $s = _new-remotesession @bound -ErrorAction:Continue 
        } catch {
            if ($_.Exception.Message.Contains(" Basic,")) {
                write-warning "have you enabled basic authentication method, like this:"
                write-warning 'set-item WSMan:\localhost\Client\Auth\Basic -Value true -Confirm:$false'
            }
            throw 
        }
    }

    return $s
}

function _New-RemoteSession {

param(
[parameter(Mandatory=$true)] $ComputerName,
[switch][bool] $NoSsl,
[switch][bool] $Ssl,
[switch][bool] $Reuse = $true,
$ServerInfo = $null,
[switch][bool] $ClearCredentials,
[System.Management.Automation.Runspaces.AuthenticationMechanism] $Authentication = [System.Management.Automation.Runspaces.AuthenticationMechanism]::Negotiate,
$port,
[switch][bool] $cim,
[Parameter(Mandatory=$false)]
[pscredential]
$credential = [pscredential]::Empty
) 
    # ssl is the default
    $use_ssl_by_default = $true
    if ($Ssl.IsPresent) {
        $NoSsl = !$Ssl
    }
    elseif (!$NoSsl.IsPresent) {
        $NoSsl = !$use_ssl_by_default
        if ($port -eq 5985) { $NoSsl = $true }
        if ($port -eq 5986) { $NoSsl = $false }
    }    

    $sessionVar = $ComputerName
    if ($cim) { $sessionVar = "$($ComputerName)_cim" }
    if ($ClearCredentials) { $Reuse = $false }
    if ($Reuse -and (Test-Path variable:global:$sessionVar)) {
        $currentSession = (Get-Variable -Name "$sessionVar").Value
        if ($currentSession -ne $null -and ($cim -or ($currentSession.State -eq "Opened" -and $currentSession.Availability -eq "Available"))) {
            write-verbose "retrieving exisitng session for '$computername'"
            return $currentSession
        }
    }

    
        $hash = @{ 
            "-UseSSL" = !$NoSsl
            "-ComputerName" = $ComputerName
        }
        $found = $false
        if ($global:psSessionsMap -ne $null) {
            $null = ipmo publishmap -Verbose:$false
            $ServerInfo = get-entry $ComputerName -map $global:psSessionsMap 
            $found = $ServerInfo -ne $null
        }
   
        if ($found) {
            write-verbose "found '$ComputerName' in session map at '$Global:psSessionsMapPath'"
            
        } elseif ($ServerInfo -ne $null) {
            if ($global:psSessionsMap -eq $null) {
                $global:psSessionsMap = @{}
            }
            $global:psSessionsMap[$ComputerName] = $ServerInfo
        }
        else {
            write-verbose "'$ComputerName' not found in session map"
        }

        if ($ServerInfo -ne $null) {
            $ServerInfo.Keys | % { 
                if ($hash.ContainsKey("-$_")) {
                    write-verbose "   -$_ = $($ServerInfo[$_]) [from sessionmap]"
                    $hash["-$_"] = $ServerInfo[$_]
                } elseif (!$_.StartsWith("_") -and $_ -ne "vars") {
                    write-verbose "   -$_ = $($ServerInfo[$_]) [from sessionmap]"
                    $hash["-$_"] = $ServerInfo[$_]
                }
            }

            
            if ($ServerInfo.UseSSL -ne $null) { $NoSsl = !$ServerInfo.UseSSL  }
            if ($ServerInfo.Port -ne $null) { $port = $ServerInfo.Port }

            if ($port -eq $null) {
                if ($nossl) {
                    $port = 5985
                } else {
                    $port = 5986
                }
            }
        } else {             

            if ($port -eq $null) {
                $hasSsl = test-port $ComputerName 5986
                if($hasSsl -and !$NoSsl) {
                    $hash["-UseSSL"] = $true
                    write-verbose "   -UseSSL = $true [port 5986 is available and nossl=false]"                    
                    $port = 5986
                } else {
                    $hasPlain = test-port $ComputerName 5985
                    if ($hasPlain) {
                        $hash["-UseSSL"] = $false
                        write-verbose "   -UseSSL = $false [port 5985 is available and/or nossl=false]"                    
                        $port = 5985
                    } else {
                        throw "no entry in sessionmap for '$computername'. some Default ports are not available (5986[ssl]=$hasSsl and 5985[nossl]=$NoSsl)"
                    }
                }                    
            } else {
                write-verbose "   -UseSSL = !$NoSsl [from -nossl:$nossl]"                    
                $hash["-UseSSL"] = !$NoSsl
            }        
            
             
        }

        if ($ClearCredentials) {
            Cache\Remove-CredentialsCached -container "$ComputerName.cred" 
        }

        $bound = $PSBoundParameters
                
        $useCredentials = $ServerInfo -ne $null `
            -or ($Authentication -eq [System.Management.Automation.Runspaces.AuthenticationMechanism]::Basic) `
            -or $ComputerName.endswith("cloudapp.net") `
            -or ($credential -ne [pscredential]::Empty) `
            -or ($bound.credential -eq $null)
        #$useCredentials = $credential -ne [pscredential]::Empty

        if ($useCredentials) {
            write-verbose "will use credentials"
            <#
            if ($username -ne $null -and $password -ne $null) {
                $secpass = ConvertTo-SecureString $password -AsPlainText -force
                $cred = new-object System.Management.Automation.pscredential -ArgumentList @($username,$secpass)
                $hash["-Credential"] = $cred
            }
            #>
            if ($bound.credential -eq $null) {
                write-verbose "trying cached credentials"
                # auto credentials
                $cred = Cache\Get-CredentialsCached -Message "Enter credentials for $ComputerName" -container "$ComputerName.cred" -verbose
                if ($cred -eq $null) {
                    throw "credentials are required for remote connection to '$ComputerName', but there are no cached credentials in container '$ComputerName.cred'!"
                }
            } 
            else {
                # use provided credentials
                write-verbose "using provided credentials"
                $cred = $credential  
            }

            if ($cred -eq $null) {
                throw "credentials are required for remote connection to '$ComputerName', but none given!"
            }
            write-verbose "passing credentials for user $($cred.username)"
            $hash["-Credential"] = $cred
        } else {
            write-verbose "not using credentials"
        }

        if ($port -ne $null) {
            $hash["-Port"] = $port
        }

        if ($PSBoundParameters["Authentication"] -ne $null) {
            $hash["-Auth"] = $Authentication
        }
        
        $Error.Clear()
        write-verbose "connecting with parameters:"
        $hash | format-table -AutoSize | out-string -Stream | write-verbose

        $session = $null
        if ($cim) {

            if ($hash.ContainsKey("-UseSSL")) { 
                $hash.Remove("-UseSSL") 
            }
            $opts = New-CimSessionOption -SkipRevocationCheck -SkipCACheck -SkipCNCheck -UseSsl:$(!$nossl)
            
            $session = New-CimSession @hash -SessionOption $opts 
            if ($session -eq $null) { throw "failed to create remote CIM sesssion" }
        } else {
            $opts = New-PSSessionOption -SkipRevocationCheck -SkipCACheck -SkipCNCheck
            $session = New-PSSession @hash -ErrorAction:$ErrorActionPreference -SessionOption $opts
            if ($Error.Count -ne 0) {
                if ($Error[0] -match "SSL certificate is signed by an unknown certificate authority" -or $Error[0].Exception.ErrorCode -eq 12175) {
                    write-host "getting remote cert"
                    $p = $port 
                    if ($p -eq $null) { $p = "rps" }
                    $crt = Get-RemoteCert -computername $ComputerName -port $p
                    write-host "found certificate for $($crt.Subject) issuer=$($crt.issuer). Installing to Cert:\CurrentUser\Root"
                    $crt | Export-Certificate -FilePath "$ComputerName.cer"
                    Import-Certificate -FilePath "$ComputerName.cer" -CertStoreLocation Cert:\CurrentUser\Root -Confirm:$false
                    $Error.Clear()
                    $session = New-PSSession @hash -SessionOption $opts 
                }
                if ($Error.Count -ne 0) {  
                    $err = @()
                    $error | % { $err += $_ }
                    throw $error[0]
                }
            }
        }

        if ($session -eq $null) { throw "failed to create remote powershell sesssion" }        

        Write-Verbose "storing session to '$ComputerName' in 'global:$sessionVar'"
        Set-Variable -Name "global:$sessionVar" -Value $session
        
        if ($session -eq $null) { throw "Cannot enter remote session, because it has not been initialized" }
        if ($ServerInfo -ne $null -and ![string]::IsNullOrEmpty($ServerInfo._defaultdir) -and !$cim) {
            $r = icm -Session $session -ScriptBlock { param($dir) cd $dir } -ArgumentList @($ServerInfo._defaultdir)
        }

       return $session
    
}

function Test-Port 
{
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
        $timeout = 1000
        )

    $RemoteServer = If ([string]::IsNullOrEmpty($ComputerName)) {$IPAddress} Else {$ComputerName};

    If ($Protocol -eq 'TCP')
    {
        $test = New-Object System.Net.Sockets.TcpClient;
        Try
        {            
            Write-verbose "Connecting to $RemoteServer :$Port (TCP)..";
            $r = $test.BeginConnect($RemoteServer, $Port, $null, $null);
            $s = $r.AsyncWaitHandle.WaitOne([timespan]::FromMilliseconds($timeout));
            if (!$s) {
                throw "connection timed out after $timeout"
            }
            Write-verbose "Connection successful";
            return $true
        }
        Catch
        {
            Write-verbose "Connection failed: $_";
            return $false
        }
        Finally
        {
            $test.Dispose();
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


function Enter-RemoteSession {
param(
[parameter(Mandatory=$true)] $ComputerName,
[switch][bool] $NoSsl,
[switch][bool] $Ssl,
[switch][bool] $ClearCredentials,
$port,
[switch][bool] $Reuse = $true,
[switch][bool] $reloadSessionMap = $true,
[switch][bool] $NoEnter = $false,
[switch][bool] $cim,
[pscredential]
[System.Management.Automation.Credential()]
$credential = [PSCredential]::Empty
) 
    $bound = $PSBoundParameters
    $null = $bound.Remove("NoEnter") 
    $s = new-remotesession @bound
    if ($s -eq $null) {
        throw "failed to connect to '$computername'"
    }
    if (!$NoEnter -and !$cim) {
        $s | Enter-PSSession
    } else {
        return $s
    }
}

set-alias rps Enter-RemoteSession 


function _get-syncdir() {
    if (test-path "HKCU:\Software\Microsoft\OneDrive") 
    {
        $prop = get-itemproperty "HKCU:\Software\Microsoft\OneDrive\" "UserFolder"
        if ($prop -ne $null) {
            $dir = $prop.userfolder
        }        
    }

    return $dir
}





function enter-rdp ($name, [switch][bool]$wait) {
    $file = find-rdp $name
    $p = $null
    if ($file -eq $null -and $name.contains("."))  {
        write-host "running mstsc /v:$name"
        $p = Start-Process mstsc /v:$name -PassThru
    }
    else {
    
        if ($file -eq $null) { throw "rdp profile '$name' not found" }

        write-host "running mstsc '$file'..."
        $p = Start-Process mstsc $file -PassThru
    }

    if($wait) {
        $p.WaitForExit()
    }
}

function copy-sshid { 
    [CmdletBinding()]
    param($host,$port = 22, $alias, $id)

    $ssh_home = "$env:USERPROFILE\.ssh"
    if (!(test-path $ssh_home)) { $null = mkdir $ssh_home }
    if ($id -ne $null) { 
        $idfile = "$id.pub"
        $id = "$ssh_home\$idfile"
    }
    else {
        $id = "$ssh_home\id_rsa.pub"
    }
    if (!(Test-Path $id)) {
        & ssh-keygen
    }

    $cmd = "umask 077; test -d .ssh || mkdir .ssh ; cat >> .ssh/authorized_keys"
    write-verbose "executing: cmd /c `"ssh $host -p $port `"$cmd`" < $id`""
    cmd /c "ssh $host -p $port `"$cmd`" < $id"

    $hostname = $host
    $username = $null
    if ($hostname -match "(.*)@(.*)") {
        $username = $matches[1]
        $hostname = $matches[2]
    }
    if ($alias -eq $null) { $alias = $hostname }

    $config = "$ssh_home\config"
    if (!(test-path $config)) { out-file $config }

    $cfg = @(get-content $config)
    $found = $cfg | ? { $_ -match "Host $alias" }
    if ($found) {
        write-verbose "removing old config for host $alias"
        $newcfg = @()
        $startIdx = -1
        $endIdx = -1
        for($i = 0; $i -lt $cfg.Length; $i++) {
            $_ = $cfg[$i]
            if ($_ -match "Host $alias") {
                $startIdx = $i
                continue
            }
            if ($startIdx -ge 0 -and $_ -match "Host ") {
                $endIdx = $i-1
            }
            if ($startIdx -lt 0 -or $endIdx -gt 0) {
                $newcfg += $_
            }
        }
        $cfg = $newcfg
    }
    
    write-verbose "adding ssh config for host $alias"
    $cfg += "Host $alias"
    $cfg += "  HostName $hostname"
    $cfg += "  Port $port"
    if ($username -ne $null) {
        $cfg += "  User $username"
    }
    if ($idfile -ne $null) {
        $cfg += "   IdentityFile $idfile"
    }
    $cfg | Out-File $config -Encoding ascii

}

new-alias rdp enter-rdp -force
new-alias ssh-copy-id copy-sshid -forceew
new-alias init-ssh copy-sshid -force
new-alias new-sshhost copy-sshid -force