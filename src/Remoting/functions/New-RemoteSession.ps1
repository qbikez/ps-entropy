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
DynamicParam {    
    # try {
    #     $paramDictionary = new-object -Type System.Management.Automation.RuntimeDefinedParameterDictionary

    #     $paramname = "ComputerName"
    #     $paramType = [string]

    #     $attributes = new-object System.Management.Automation.ParameterAttribute
    #     $attributes.Mandatory = $true
    #     $attributes.Position = 0
    #     $attributeCollection = new-object -Type System.Collections.ObjectModel.Collection[System.Attribute]
    #     $attributeCollection.Add($attributes)

    #     $map = find-sessionmap -reload:$reloadSessionMap
    #     $validvalues = @()
    #     if ($map -ne $null) {
    #         $validvalues = $map.Keys
    #     }
    #     $validateset = new-object System.Management.Automation.ValidateSetAttribute -ArgumentList @($validvalues)
    #     $attributeCollection.Add($validateset)

    #     $dynParam1 = new-object -Type System.Management.Automation.RuntimeDefinedParameter($paramname, $paramType, $attributeCollection)
        
    #     $paramDictionary.Add($paramname, $dynParam1)

    #     return $paramDictionary
    # }
    # catch {
    #     write-host $_
    # }
}
process {
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
                        $NoSsl = $true
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

        if ($port -eq $null) {
            if ($NoSsl) { $port = 5985 }
            else { $port = 5986 }
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
            write-verbose "session options:"
            $opts | format-table -AutoSize | out-string -Stream | write-verbose
            $session = New-CimSession @hash -SessionOption $opts 
            if ($session -eq $null) { throw "failed to create remote CIM sesssion" }
        } else {
            $opts = New-PSSessionOption -SkipRevocationCheck -SkipCACheck -SkipCNCheck
            write-verbose "session options:"
            $opts | format-table -AutoSize | out-string -Stream | write-verbose
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

            if ($session -ne $null) {
                try {
                write-verbose "storing application private data"
                $session.ApplicationPrivateData.Port = $port
                $session.ApplicationPrivateData.Auth = $Authentication.ToString()
                $session.ApplicationPrivateData.Ssl = !$NoSsl
                } catch {
                    write-warning "failed to store custom properties in sesion.ApplicationPrivateData: $($_.Exception.Message)"
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
        $timeout = 1000,
        [System.Net.Sockets.AddressFamily] $AddressFamily = [System.Net.Sockets.AddressFamily]::Unspecified
        )

    $RemoteServer = If ([string]::IsNullOrEmpty($ComputerName)) {$IPAddress} Else {$ComputerName};

    $ip = $IPAddress
    if (!([string]::IsNullOrEmpty($ComputerName)) ) {
        $ipv4 = "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"
        $ipv6 = "([0-9a-fA-F]+:){7}[0-9a-fA-F]"
        if ($ComputerName -notmatch $ipv4 -and $ComputerName -notmatch $ipv6) {
            $ips = Resolve-DnsName $computername -ErrorAction Ignore 
            if ($ips -eq $null) { 
                throw "could not resolve host $computername"
            }
            $ips = $ips | select -ExpandProperty IPAddress | % {  [System.Net.IPAddress]::Parse($_) }
            if ($AddressFamily -ne [System.Net.Sockets.AddressFamily]::Unspecified) {
                $ip = $ips | ? { $_.AddressFamily -eq $AddressFamily }
                if ($ip -eq $null) {
                    throw "hostname $computername does not resolve to an address in family $AddressFamily"
                }
            }
            else {
                $ip = $ips | select -first 1               
            }

            write-verbose "hostname $computername resolved to IP: $ip"

        } else {
            write-verbose "treating $ComputerName as IP"
            $ip = [System.Net.IPAddress]::Parse($ComputerName)
        }
    }

    if ($ip -eq $null) {
        throw "ip not found"
    }
    if ($AddressFamily -eq [System.Net.Sockets.AddressFamily]::Unspecified) {
        write-verbose "auto-assigning address family: '$($ip.AddressFamily)'"
        $AddressFamily = $ip.AddressFamily
    }
    
    If ($Protocol -eq 'TCP')
    {
        $test = New-Object System.Net.Sockets.TcpClient $AddressFamily
        Try
        {            
            Write-verbose "Connecting to $RemoteServer [$ip] :$Port ($protocol $AddressFamily).."
            $r = $test.BeginConnect($ip, $Port, $null, $null)
            $s = $r.AsyncWaitHandle.WaitOne([timespan]::FromMilliseconds($timeout))
            if (!$s) {
                throw "connection timed out after $timeout"
            }
            $test.EndConnect($r)
            if ($test.Connected) {
                Write-verbose "Connection successful";
            }
            else {
                Write-Verbose "failed to connect";
            }
            
            return $test.Connected
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

function Add-WinRMTrustedHost {
    param($host)

    $trusted = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value
    if ($host -notin $trusted.Split(",") -and "*" -ne $trusted) {
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$host" -Concatenate -Force
    }
}

function get-rpsEntry {
    param($name)
    $map = find-sessionmap -reload:$true
    if ($name -eq $null) {
        return $map.Keys
    }
}

function add-rpsEntry {
    [CmdletBinding()] 
    param($host, $port, $alias, [switch][bool] $nossl, [switch][bool] $force, [switch][bool] $ClearCredentials)

    $trust = $true
    $map = find-sessionmap -reload:$true

    if ($alias -eq $null) { $alias = $host }

    if ($trust) {
       Add-WinRMTrustedHost $host
    }

    $cred = Cache\Get-CredentialsCached -Message "Enter credentials for $host" -container "$alias.cred" -reset:$ClearCredentials -verbose
    if ($cred -eq $null) {
        throw "credentials are required for remote connection to '$host', but there are no cached credentials in container '$alias.cred'!"
    }

    $session = New-RemoteSession -ComputerName $host -port $port -NoSsl:$nossl -credential:$cred
    if ($session -ne $null) {
        set-variable "$alias" -Scope global -Value $session
        $sessionPort = $session.ApplicationPrivateData.Port
        if ($sessionPort -ne $null) { $port = $sessionPort }
        $sessionSsl = $session.ApplicationPrivateData.Ssl
        if ($sessionSsl -ne $null) { $nossl = !$sessionSsl }

        if ($map[$alias] -eq $null -or $force) {
            $map[$alias] = @{
                ComputerName = $host
                UseSsl = !$nossl
            }
            if ($port -ne $null) {
                $map[$alias].Port = $port
            }
            if ($Global:psSessionsMapPath -ne $null -and [System.IO.Path]::GetExtension($Global:psSessionsMapPath) -eq ".json") {
                req newtonsoft.json
                write-verbose "saving session map at $Global:psSessionsMapPath"
                copy-item $Global:psSessionsMapPath "$Global:psSessionsMapPath.bak"
                $map | ConvertTo-JsonNewtonsoft | Out-File $Global:psSessionsMapPath
            }
        } else {
            write-warning "host $alias already exists in seessionmap. Use -Force to override"
        }
        $session | Enter-PSSession
    }
}

function get-sshEntry {
    param()
    
    $ssh_home = "$env:USERPROFILE\.ssh"
    if (!(test-path $ssh_home)) { $null = mkdir $ssh_home }
    
    $config = "$ssh_home\config"
    if (!(test-path $config)) { out-file $config }

    $cfg = @(get-content $config)
    $found = $cfg | ? { $_ -match "Host $alias" }
    $found
}

function copy-sshid { 
    [CmdletBinding()]
    param($host, $port = $null, $alias, $id)

    $org_port = $port
    if ($port -eq $null) { $port = 22 }
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
        write-verbose "id_rda.pub not found. generating"
        & ssh-keygen
    }
    write-verbose "using id file: '$id'"
    
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
            if ($startIdx -ge 0 -and $endIdx -lt 0) {
                # copy hostname and port from existing settings
                if ($_ -match "Hostname (.*)") {
                    $hostname = $matches[1]
                }
                if ($_ -match "Port (.*)" -and $org_port -eq $null) {
                    $port = $matches[1]
                }
                if ($_ -match "User (.*)" -and $username -eq $null) {
                    $port = $matches[1]
                }
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


#Register-TabExpansion 'Enter-RemoteSession' @{
#    'ComputerName' = { $map = find-sessionmap; if ($map -ne $null) { return $map.Keys } }
# }

new-alias rdp enter-rdp -force
new-alias ssh-copy-id copy-sshid -force
new-alias init-ssh copy-sshid -force
new-alias new-sshhost copy-sshid -force
new-alias init-rps add-rpsEntry

