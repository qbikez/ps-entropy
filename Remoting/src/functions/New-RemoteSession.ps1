function New-RemoteSession { 
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)] $ComputerName,
        [switch][bool] $NoSsl,
        [switch][bool] $Ssl,
        [switch][bool] $Reuse = $true,
        $ServerInfo = $null,
        [switch][bool] $ClearCredentials,
        $port,
        [switch][bool] $cim,
        [parameter(Mandatory = $false)] 
        [pscredential]
        #[System.Management.Automation.Credential()]
        $credential = [pscredential]::Empty,
        [System.Management.Automation.Runspaces.AuthenticationMechanism] $Authentication = [System.Management.Automation.Runspaces.AuthenticationMechanism]::negotiate,
        [switch][bool] $reloadSessionMap = $false,
        [System.Net.Sockets.AddressFamily] $AddressFamily = [System.Net.Sockets.AddressFamily]::Unspecified
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
        if ($bound.reloadSessionMap -ne $null) { $null = $bound.Remove("reloadSessionMap") }
        if ($bound.ErrorAction -ne $null) { $null = $bound.Remove("ErrorAction") }
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
            $bound["Authentication"] = [System.Management.Automation.Runspaces.AuthenticationMechanism]::Basic
            try {
                $s = _new-remotesession @bound -ErrorAction:Continue 
            }
            catch {
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
        [parameter(Mandatory = $true)] $ComputerName,
        [switch][bool] $NoSsl,
        [switch][bool] $Ssl,
        [switch][bool] $Reuse = $true,
        $ServerInfo = $null,
        [switch][bool] $ClearCredentials,
        [System.Management.Automation.Runspaces.AuthenticationMechanism] $Authentication = [System.Management.Automation.Runspaces.AuthenticationMechanism]::Negotiate,
        $port,
        [switch][bool] $cim,
        [Parameter(Mandatory = $false)]
        [pscredential]
        $credential = [pscredential]::Empty,
        [System.Net.Sockets.AddressFamily] $AddressFamily = [System.Net.Sockets.AddressFamily]::Unspecified
    ) 
    # ssl is the default
    $use_ssl_by_default = $true
    $usessl = $null
    $usesslSource = ""
    if ($Ssl.IsPresent) {
        $usessl = $true
        $usesslSource = "-SSL"
    }
    elseif ($NoSsl.IsPresent) {
        $usessl = $false
        $usesslSource = "-noSSL"
    }
    elseif (!$NoSsl.IsPresent) {
        if ($port -eq 5985) { $usessl = $true; $usesslSource = "-port $port" }
        if ($port -eq 5986) { $usessl = $false; $usesslSource = "-port $port" }
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
            
    }
    elseif ($ServerInfo -ne $null) {
        if ($global:psSessionsMap -eq $null) {
            $global:psSessionsMap = @{ }
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
            }
            elseif (!$_.StartsWith("_") -and $_ -ne "vars") {
                write-verbose "   -$_ = $($ServerInfo[$_]) [from sessionmap]"
                $hash["-$_"] = $ServerInfo[$_]
            }
        }

            
        if ($ServerInfo.UseSSL -ne $null -and $usessl -eq $null) { $usessl = $ServerInfo.UseSSL; ; $usesslSource = "[from sessionmap]" }
        if ($ServerInfo.Port -ne $null -and $port -eq $null) { $port = $ServerInfo.Port }

        if ($port -eq $null) {
            if ($usessl) {
                $port = 5986                    
            }
            else {
                $port = 5985
            }
        }

        $hash["-UseSSL"] = $usessl
    }
    else {             

        if ($port -eq $null) {
            $hasSsl = test-port $ComputerName 5986 -AddressFamily:$addressFamily
            if ($hasSsl -and $usessl) {
                $hash["-UseSSL"] = $usessl
                $usesslSource = "port 5986 is available"
                write-verbose "   -UseSSL = $true [port 5986 is available and nossl=false]"                    
                $port = 5986
            }
            else {
                $hasPlain = test-port $ComputerName 5985 -AddressFamily:$addressFamily
                if ($hasPlain) {
                    $usessl = $false
                    $usesslSource = "port 5985 is available"
                    $hash["-UseSSL"] = $usessl
                    write-verbose "   -UseSSL = $false [port 5985 is available and/or nossl=false]"                    
                    $port = 5985
                }
                else {
                    throw "no entry in sessionmap for '$computername'. some Default ports are not available (5986[ssl]=$hasSsl and 5985[nossl]=$hasplain)"
                }
            }                    
        }
        else {
            if ($usessl -eq $null) {
                $usessl = $use_ssl_by_default
                $usesslSource = "default SSL: $use_ssl_by_default"
            }
            write-verbose "   -UseSSL = $usessl [$usesslSource]"
            $hash["-UseSSL"] = $usessl
        }        
    }

    if ($port -eq $null) {
        if ($usessl) { $port = 5986 }
        else { $port = 5985 }
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
    }
    else {
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
        $opts = New-CimSessionOption -SkipRevocationCheck -SkipCACheck -SkipCNCheck -UseSsl:$usessl
        write-verbose "session options:"
        $opts | format-table -AutoSize | out-string -Stream | write-verbose
        $session = New-CimSession @hash -SessionOption $opts 
        if ($session -eq $null) { throw "failed to create remote CIM sesssion" }
    }
    else {
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
                $session.ApplicationPrivateData.Ssl = $usessl
            }
            catch {
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

function Test-Port {
    [cmdletbinding()]
    Param(
        [parameter(ParameterSetName = 'ComputerName', Position = 0)]
        [string]
        $ComputerName,

        [parameter(ParameterSetName = 'IP', Position = 0)]
        [System.Net.IPAddress]
        $IPAddress,

        [parameter(Mandatory = $true , Position = 1)]
        [int]
        $Port,

        [parameter(Mandatory = $false, Position = 2)]
        [ValidateSet("TCP", "UDP")]
        [string]
        $Protocol = "TCP",
        $timeout = 1000,
        [System.Net.Sockets.AddressFamily] $AddressFamily = [System.Net.Sockets.AddressFamily]::Unspecified
    )

    $RemoteServer = If ([string]::IsNullOrEmpty($ComputerName)) { $IPAddress } Else { $ComputerName };

    $ip = $IPAddress
    if (!([string]::IsNullOrEmpty($ComputerName)) ) {
        $ipv4 = "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"
        $ipv6 = "([0-9a-fA-F]+:){7}[0-9a-fA-F]"
        if ($ComputerName -notmatch $ipv4 -and $ComputerName -notmatch $ipv6) {
            $ips = Resolve-DnsName $computername -ErrorAction Ignore 
            if ($ips -eq $null) { 
                throw "could not resolve host $computername"
            }
            $ips = $ips | select -ExpandProperty IPAddress | % { [System.Net.IPAddress]::Parse($_) }
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

        }
        else {
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
    
    If ($Protocol -eq 'TCP') {
        $test = New-Object System.Net.Sockets.TcpClient $AddressFamily
        Try {            
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
        Catch {
            Write-verbose "Connection failed: $_";
            return $false
        }
        Finally {
            $test.Dispose();
        }
    }

    If ($Protocol -eq 'UDP') {
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
    [CmdletBinding(DefaultParameterSetName = "default")]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "default", Position = 0)] 
        [Parameter(Mandatory = $false, ParameterSetName = "list", Position = 0)] 
        $ComputerName,
        [switch][bool] $NoSsl,
        [switch][bool] $Ssl,
        [switch][bool] $ClearCredentials,
        $port,
        [switch][bool] $Reuse = $true,
        [switch][bool] $reloadSessionMap = $true,
        [switch][bool] $NoEnter = $false,
        [switch][bool] $cim,
        [Parameter(ParameterSetName = "list")]
        [switch][bool] $list,
        [pscredential]
        [System.Management.Automation.Credential()]
        $credential = [PSCredential]::Empty,
        [System.Management.Automation.Runspaces.AuthenticationMechanism] $Authentication = [System.Management.Automation.Runspaces.AuthenticationMechanism]::negotiate,
        [System.Net.Sockets.AddressFamily] $AddressFamily = [System.Net.Sockets.AddressFamily]::Unspecified
    )
    $bound = $PSBoundParameters

    if ($list) {
        $map = Find-SessionMap
        if ($ComputerName -ne $null) {
            return $map[$computername]
        }
        else {
            return $map`
        
        }
    }

    $null = $bound.Remove("NoEnter")

    $s = new-remotesession @bound
    if ($s -eq $null) {
        throw "failed to connect to '$computername'"
    }
    if (!$NoEnter -and !$cim) {
        $s | Enter-PSSession
    }
    else {
        return $s
    }
}

set-alias rps Enter-RemoteSession

function _get-syncdir() {
    if (test-path "HKCU:\Software\Microsoft\OneDrive") {
        try {
            $prop = get-itemproperty "HKCU:\Software\Microsoft\OneDrive\" "UserFolder" -ErrorAction Ignore
            if ($prop -ne $null) {
                $dir = $prop.userfolder
            }        
        }
        catch {
            write-warning $_
        }
    }

    return $dir
}





function enter-rdp ($name, [switch][bool]$wait) {
    $file = find-rdp $name
    $p = $null
    if ($file -eq $null -and $name.contains(".")) {
        write-host "running mstsc /v:$name"
        $p = Start-Process mstsc /v:$name -PassThru
    }
    else {
    
        if ($file -eq $null) { throw "rdp profile '$name' not found" }

        write-host "running mstsc '$file'..."
        $p = Start-Process mstsc $file -PassThru
    }

    if ($wait) {
        $p.WaitForExit()
    }
}

function Add-WinRMTrustedHost {
    param([Alias("host")] $hostname)

    $trustedHostsFile = "WSMan:\localhost\Client\TrustedHosts"
    $trusted = ""
    if (test-path $trustedHostsFile) {
        $trusted = (Get-Item $trustedHostsFile).Value
    }
    if ($hostname -notin $trusted.Split(",") -and "*" -ne $trusted) {
        Set-Item $trustedHostsFile -Value $hostname -Concatenate -Force
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
    param(
        [Alias("host")]
        $hostname,
        $port,
        $alias,
        [switch][bool] $nossl,
        [switch][bool] $force,
        [System.Management.Automation.Runspaces.AuthenticationMechanism] $Authentication = [System.Management.Automation.Runspaces.AuthenticationMechanism]::negotiate,
        [switch][bool] $ClearCredentials,
        [pscredential] $credential,
        [switch][bool] $noEnter,
        [System.Net.Sockets.AddressFamily] $AddressFamily = [System.Net.Sockets.AddressFamily]::Unspecified
    )

    $trust = $true
    $map = find-sessionmap -reload:$true
    $cred = $credential

    if ($alias -eq $null) { $alias = $hostname }

    if ($trust) {
        Add-WinRMTrustedHost $hostname
    }

    if ($cred -eq $null) {
        $cred = Cache\Get-CredentialsCached -Message "Enter credentials for $hostname" -container "$alias.cred" -reset:$ClearCredentials -verbose
        if ($cred -eq $null) {
            throw "credentials are required for remote connection to '$hostname', but there are no cached credentials in container '$alias.cred'!"
        }
    }
    else {
        Cache\Export-Credentials -container "$alias.cred" -cred $cred
    }

    if (!$noenter) {
        $session = New-RemoteSession `
            -ComputerName $hostname `
            -port $port `
            -NoSsl:$nossl `
            -credential:$cred `
            -Authentication:$Authentication `
            -Reuse:(!$force) `
            -AddressFamily:$AddressFamily
            
        if ($session -ne $null) {
            set-variable "$alias" -Scope global -Value $session
            $sessionPort = $session.ApplicationPrivateData.Port
            if ($sessionPort -ne $null) { $port = $sessionPort }
            $sessionSsl = $session.ApplicationPrivateData.Ssl
            if ($sessionSsl -ne $null) { $nossl = !$sessionSsl }
        }
    }

    if ($map[$alias] -eq $null -or $force) {
        $map[$alias] = @{
            ComputerName = $hostname
            UseSsl       = !$nossl
            Auth         = $Authentication.ToString()
        }
        if ($port -ne $null) {
            $map[$alias].Port = $port
        }
        if ($Global:psSessionsMapPath -ne $null -and [System.IO.Path]::GetExtension($Global:psSessionsMapPath) -eq ".json") {
            req newtonsoft.json
            write-verbose "saving session map at $Global:psSessionsMapPath"
            try {
                copy-item $Global:psSessionsMapPath "$Global:psSessionsMapPath.bak"
                $map | ConvertTo-JsonNewtonsoft | Out-File $Global:psSessionsMapPath
            }
            catch {
                write-warning "failed to save session map at $Global:psSessionsMapPath: $($_.Exception.Message)"
            }
            $map[$alias] | format-table | out-string | write-verbose
            $Global:psSessionsMap = $map
        }
    }
    else {
        write-warning "host $alias already exists in seessionmap. Use -Force to override"
    }

    if (!$noEnter) {
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
    param(
        $hostname,
        $alias,
        $port = $null,
        $username,
        $id
    )

    $org_port = $port
    $org_hostname = $hostname
    if ($port -eq $null) { $port = 22 }
    if ($alias -eq $null) { $alias = $hostname }
    if ($hostname -eq $null) { $hostname = $alias }
    
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
        $newId = read-host "Enter file in which to save the key ($id):"
        if (![System.IO.Path]::IsPathRooted($newId)) {
            $newId = "$ssh_home\$newId"
        }
        $id = $newId
        & ssh-keygen -f $id
    }
    write-verbose "using id file: '$id'"
    
    $idstring = get-content $id | out-string

    $configFile = "$ssh_home\config"
    if (!(test-path $configFile)) { out-file $configFile }
    $cfg = parse-sshconfig $configFile
    
    $cfgEntry = $cfg | ? { $_.name -eq $alias }
    if ($cfgEntry -eq $null) {
        $cfgEntry = @{
            name    = $alias
            content = @()
        }
        $cfg = @($cfg) + $cfgEntry
    }
    else {
        write-verbose "found existing config for $alias : `r`n$($cfgentry.content)"
        if ($org_port -eq $null -and $cfgEntry.port -ne $null) {
            $port = $cfgEntry.port
            write-verbose "using port from config: $port"
        }
        if ($org_hostname -eq $null -and $cfgEntry.hostname -ne $null) {
            $hostname = $cfgEntry.hostname
            write-verbose "using hostname from config: $hostname"
        }
    }

    if ($hostname -match "(.*)@(.*)") {
        $username = $matches[1]
        $hostname = $matches[2]
    }

    if ($hostname -match "(.*):([0-9]+)") {
        $hostname = $matches[1]
        $port = $matches[2]
    }
    $a = @()
    if ($username -ne $null) {
        $a += @("-l", $username)
    }
    #write-verbose "executing: cmd /c `"ssh $hostname -p $port $a `"$cmd`" < $id`""
    # $r = invoke "ssh" "$hostname" "-p" "$port" $a $cmd -in $idstring -passthru -showoutput -Verbose
    $cmd = "umask 077; test -d .ssh || mkdir .ssh ; cat >> .ssh/authorized_keys"
    & cmd /c "ssh $hostname -p $port $a `"$cmd`" < $id"
    if ($alias -eq $null) { $alias = $hostname }

    write-verbose "adding ssh config for host '$alias' to file '$configFile'"
    $cfgEntry.Content += "Host $alias"
    $cfgEntry.Content += "  HostName $hostname"
    $cfgEntry.Content += "  Port $port"

    if ($username -ne $null) {
        $cfgEntry.Content += "  User $username"
    }
    if ($idfile -ne $null) {
        $cfgEntry.Content += "   IdentityFile $idfile"
    }
    save-sshConfig -config $cfg -configFile $configFile
}

function parse-sshconfig($configFile) {
    $entries = @()
    $cfg = get-content $configFile

    for ($i = 0; $i -lt $cfg.Length; $i++) {
        $_ = $cfg[$i]
        if ($_ -match "Host\s+(.*)") {
            if ($current -ne $null) {
                $current.endidx = $i - 1
                $entries += $current
            }

            $current = @{
                name     = $Matches[1]
                startIdx = $i
                endIdx   = -1
                content = @()
            }
        }

        if ($current -ne $null) {
            if ($_ -match "([a-z0-9]+)\s+(.*)") {
                $key = $Matches[1]
                $value = $Matches[2]
                $current[$key] = $value
            }
            $current.content += $_
        }
    }
    if ($current -ne $null) {
        $entries += $current
    }

    return $entries
}

function save-sshConfig($config, $configFile) {
    $newContent = @()
    foreach ($entry in $config) {
        if ($entry.content -ne $null) {
            $newContent += $entry.content
        }
    }

    $newContent | Out-File $configFile -Encoding ascii
}

#Register-TabExpansion 'Enter-RemoteSession' @{
#    'ComputerName' = { $map = find-sessionmap; if ($map -ne $null) { return $map.Keys } }
# }

new-alias rdp enter-rdp -force
new-alias ssh-copy-id copy-sshid -force
new-alias init-ssh copy-sshid -force
new-alias new-sshhost copy-sshid -force
new-alias init-rps add-rpsEntry -Force
