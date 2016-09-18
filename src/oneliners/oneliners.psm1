
ipmo cache -ErrorAction Ignore
ipmo publishmap -ErrorAction Ignore

function invoke-giteach($cmd) {
    gci | ? { $_.psiscontainer } | % { pushd; cd $_; if (tp ".git") { write-host; log-info $_; git $cmd }; popd; }
}
function invoke-gitpull {
    git-each "pull"
}

function convertto-colorcode($color) {
    $light = $false
     if ($color -isnot [int]) {
        if ($color.startswith("light")) {
            $light = $true
            $color = $color -replace "light",""
        }
        $color = switch ($color) {
            "black" { 0 }
            "red" { 1 }
            "green" { 2 }
            "yellow" { 3 }
            "blue" {4 }
            "magenta" { 5 }
            "cyan" { 6 }
            "white" { 7 }
            default { 9 }
        }
    }
    
    return $color,$light
}

function set-bgcolor($n) {
    $base = 40
    $n,$light = convertto-colorcode $n    
    Write-Output  ([char](0x1b) + "[$($base+$n);m")
    if ($light)  { Write-Output ([char](0x1b) + "[1;m") }
}

function set-color($n) {
    $base = 30
    $n,$light = convertto-colorcode $n
    Write-Output  ([char](0x1b) + "[$($base+$n);m")
    if ($light)  { Write-Output ([char](0x1b) + "[1;m") }
}

function write-controlchar($c) {
    Write-Output  ([char](0x1b) + "[$c;m")
}


function set-windowtitle([string] $title) {
    $host.ui.RawUI.WindowTitle = $title
}
function update-windowtitle() {
    if ("$PWD" -match "\\([^\\]*).hg") {
        set-windowtitle $Matches[1]
    }
}

function split-output {
    [CmdletBinding()] 
    param([Parameter(ValueFromPipeline=$true)]$item, [ScriptBlock] $Filter, $filePath, [switch][bool] $append)
    process {
        $null = $_ | ? $filter | tee-object -filePath $filePath -Append:$append 
        $_
    }
}

<#
function pin-totaskbar {
    param($cmd, $arguments)
    $shell = new-object -com "Shell.Application"
    $cmd = (Get-Item $cmd).FullName
    $dir = split-path -Parent $cmd 
    $exe = Split-Path -Leaf $cmd 
    $folder = $shell.Namespace($dir)    
    $item = $folder.Parsename($cmd)
    $verb = $item.Verbs() | ? {$_.Name -eq 'Pin to Tas&kbar'}
    if ($verb) {$verb.DoIt()}
}#>

function Get-ComFolderItem {
    [CMDLetBinding()]
    param(
        [Parameter(Mandatory=$true)] $Path
    )

    $ShellApp = New-Object -ComObject 'Shell.Application'

    $Item = Get-Item $Path -ErrorAction Stop

    if ($Item -is [System.IO.FileInfo]) {
        $ComFolderItem = $ShellApp.Namespace($Item.Directory.FullName).ParseName($Item.Name)
    } elseif ($Item -is [System.IO.DirectoryInfo]) {
        $ComFolderItem = $ShellApp.Namespace($Item.Parent.FullName).ParseName($Item.Name)
    } else {
        throw "Path is not a file nor a directory"
    }

    return $ComFolderItem
}

function Install-TaskBarPinnedItem {
    [CMDLetBinding()]
    param(
        [Parameter(Mandatory=$true)] [System.IO.FileInfo] $Item
    )

    $Pinned = Get-ComFolderItem -Path $Item

    $Pinned.invokeverb('taskbarpin')
}

function Uninstall-TaskBarPinnedItem {
    [CMDLetBinding()]
    param(
        [Parameter(Mandatory=$true)] [System.IO.FileInfo] $Item
    )

    $Pinned = Get-ComFolderItem -Path $Item

    $Pinned.invokeverb('taskbarunpin')
}

<#  new-shortcut is defined in pscx also #>

function new-shortcut {
    param ( [Parameter(Mandatory=$true)][string]$Name, [Parameter(Mandatory=$true)][string]$target, [string]$Arguments = "" )
    
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($Name)
    $Shortcut.TargetPath = $target
    $Shortcut.Arguments = $Arguments
    $Shortcut.Save()
}

function stop-allprocesses ($name) {
    # or just:
    # stop-process -name $name
    cmd /C taskkill /IM "$name.exe" /F
    cmd /C taskkill /IM "$name" /F
}

function test-any() {
    begin { $ok = $true; $seen = $false } 
    process { $seen = $true; if(!$_) { $ok = $false }} 
    end { $ok -and $seen }
} 

function get-dotnetversions() {
    $def = get-content "$psscriptroot\dotnetver.cs" | out-string
    add-type -TypeDefinition $def

    return [DotNetVer]::GetVersionFromRegistry()
}

<#
function reload-module($module) {
    if (gmo $module) { rmo $module  }
    ipmo $module -Global
}
#>

function test-tcp {
    Param(
      [Parameter(Mandatory=$True,Position=1)]
       [string]$ip,

       [Parameter(Mandatory=$True,Position=2)]
       [int]$port
    )

    $connection = New-Object System.Net.Sockets.TcpClient($ip, $port)
    if ($connection.Connected) {
        Return "Connection Success"
    }
    else {
        Return "Connection Failed"
    }
}

function import-state([Parameter(Mandatory=$true)]$file) {
    if (!(test-path $file)) {
        return $null
    }
    $c = get-content $file | out-string
    $obj = convertfrom-json $c 
    if ($obj -eq $null) { throw "failed to read state from file $file" }
    return $obj
}

function export-state([Parameter(Mandatory=$true)]$state, [Parameter(Mandatory=$true)]$file) {
    $state | convertto-json | out-file $file -encoding utf8
}


function Add-DnsAlias {
    [CmdletBinding()]
    param ([Parameter(Mandatory=$true)] $from, [Parameter(Mandatory=$true)] $to)
     
    $hostlines = @(get-content "c:\Windows\System32\drivers\etc\hosts")
    $hosts = @{}
    
    write-verbose "resolving name '$to'"

    if ($to -match "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+") {
        $ip = $to
    }
    else {
        $r = Resolve-DnsName $to
        if ($r.Ip4address -ne $null) {
            $ip = $r.ip4address        
        } else {
            throw "could not resolve name '$to'"
        }
    }
    for($l = 0; $l -lt $hostlines.Length; $l++) {
        $_ = $hostlines[$l]
        if ($_.Trim().StartsWith("#") -or $_.Trim().length -eq 0) { continue }        
        $s = $_.Trim().Split(' ')
        $hosts[$s[1]] = new-object -type pscustomobject -Property @{ alias = $s[1]; ip = $s[0]; line = $l } 
    }
    
    if ($hosts.ContainsKey($from)) {
        $hosts[$from].ip = $ip
    } else {
        $hosts[$from] = new-object -type pscustomobject -Property @{ alias = $from; ip = $ip; line = $hostlines.Length }
        $hostlines += @("")
    }
    
    write-verbose "adding to etc\hosts: $ip $from"
    $hostlines[$hosts[$from].line] = "$ip $from"
    
    $guid = [guid]::NewGuid().ToString("n")
    write-verbose "backing up etc\hosts to $env:TEMP\hosts-$guid"
    copy-item "c:\Windows\System32\drivers\etc\hosts" "$env:TEMP\hosts-$guid"  
    
    $hostlines | Out-File "c:\Windows\System32\drivers\etc\hosts" 
}

function remove-dnsalias([Parameter(Mandatory=$true)] $from) {
    $hostlines = @(get-content "c:\Windows\System32\drivers\etc\hosts")
    $hosts = @{}
    
    $newlines = @()
    $found = $false
    for($l = 0; $l -lt $hostlines.Length; $l++) {
        $_ = $hostlines[$l]
        if ($_.Trim().StartsWith("#") -or $_.Trim().length -eq 0) { 
            $newlines += @($_); 
            continue 
        }        
        $s = $_.Trim().Split(' ')
        if ($s[1] -ne $from) {
            $newlines += @($_)            
        } else {
            $found = $true
        }
    }
    
    if (!$found) {
        write-warning "alias '$from' not found!"
        return
    } 
    
    $guid = [guid]::NewGuid().ToString("n")
    write-host "backing up etc\hosts to $env:TEMP\hosts-$guid"
    copy-item "c:\Windows\System32\drivers\etc\hosts" "$env:TEMP\hosts-$guid"  
    
    $newlines | Out-File "c:\Windows\System32\drivers\etc\hosts" 
    
}

function test-isadmin() {
# Get the ID and security principal of the current user account
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)

# Get the security principal for the Administrator role
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator

# Check to see if we are currently running "as Administrator"
return $myWindowsPrincipal.IsInRole($adminRole)
}

function Send-Slack {
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]$Text,
    [Parameter(Mandatory=$false)]$Channel,
    [Parameter(Mandatory=$false)]$AsUser
)
process {
	ipmo psslack

	$cred = get-credentialscached -message "slack username and token" -container "slack"
	$username = $cred.UserName
	$token = $cred.GetNetworkCredential().password

	$sendasuser = $AsUser
	if ($AsUser -eq $null) {
		$sendasuser = $true
	}

	if ($Channel -eq $null) {
		$Channel = "@$env:slackuser"
		write-verbose "setting channel to $channel"
		if ($AsUser -eq $null) { $sendasuser = $false }
	}
	if ($Channel -eq $null) {
		$Channel = "@$username"
		if ($AsUser -eq $null) { $sendasuser = $false }
	}


	Send-SlackMessage -Token $token -Username $username -Text $text -Channel $channel -AsUser:$sendasuser
}
}

function disable-hyperv {
    bcdedit /set hypervisorlaunchtype off
    write-host "hypervisorlaunchtype=off. Reboot to apply:"
    write-host "shutdown /r /t 0 /f"
}
function enable-hyperv {
    bcdedit /set hypervisorlaunchtype auto
    write-host "hypervisorlaunchtype=auto. Reboot to apply:"
    write-host "shutdown /r /t 0 /f"
}


function get-syncdir() {
    if (test-path "HKCU:\Software\Microsoft\OneDrive") 
    {
        $prop = get-itemproperty "HKCU:\Software\Microsoft\OneDrive\" "UserFolder"
        if ($prop -ne $null) {
            $dir = $prop.userfolder
        }        
    }

    if ($dir -ne $null) {
        $syncdir = join-path $dir ".powershell-data"
        if (!(test-path $syncdir)) {
            $null = mkdir $syncdir
        }
        return $syncdir
    }
}

function _get-enckey { 
    [CmdletBinding()]
    param() 
    $pass = get-passwordcached -message "Global settings password" -container "global-key" -allowuserui
    $rfc = new-object System.Security.Cryptography.Rfc2898DeriveBytes $pass,@(1,2,3,4,5,6,7,8),1000            
    $enckey = $rfc.GetBytes(256/8);
    #write-verbose "key=$($enckey | convertto-base64) length=$($enckey.length)"
    return $enckey
} 

function import-settings {
    [CmdletBinding()]
    param ()
    $syncdir = get-syncdir
    if ($syncdir -eq $null) {
        write-warning "couldn't find OneDrive synced folder"
        return
    }
    $settings = import-cache -container "user-settings" -dir $syncdir | convertto-hashtable 
    
    
    if ($settings -eq $null) {
        $settings = @{}
    }

    $decrypted = @{}
    foreach($kvp in $settings.GetEnumerator()) {
        if ($kvp.value.startswith("enc:")) {
            try {
             $enckey = _get-enckey
             $encvalue = $kvp.value.substring("enc:".length)
             $secvalue = convertto-securestring $encvalue -Key $enckey -ErrorAction stop
             $decrypted[$kvp.key] = $secvalue
             #$creds = new-object system.management.automation.pscredential ("dummy",$secvalue)
             #$pass = $creds.getnetworkcredential().password 
            } catch {
                write-warning "failed to decode key $($kvp.key): $_"
                $decrypted[$kvp.key] = $kvp.value
            }
        }
        else {
            $decrypted[$kvp.key] = $kvp.value
        }
    }

    $settings = $decrypted
    write-verbose "imported $($settings.Count) settings from '$syncdir'"

    $global:settings = $settings

    return $settings
}

function export-setting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] $key, 
        [Parameter(Mandatory=$true)] $value, 
        [Switch][bool]$force,
        [Alias("secure")][Switch][bool]$encrypt
        ) 
    $syncdir = get-syncdir
    if ($syncdir -eq $null) {
        write-warning "couldn't find OneDrive synced folder"
        return
    }
    $settings = import-cache -container "user-settings" -dir $syncdir | convertto-hashtable
    if ($settings -eq $null) { $settings = @{} }
    if ($settings[$key] -ne $null) {
        if (!$force) {
            write-warning "a setting with key $key already exists. Use -Force to override"
            return
        }
    }
    write-verbose "storing setting $key=$value at '$syncdir'"
    if ($encrypt) {
        $enckey = _get-enckey
        $secvalue = convertto-securestring $value -asplaintext -force
        $encvalue = convertfrom-securestring $secvalue -key $enckey
        $settings[$key] = "enc:$encvalue"
    } else {
        $settings[$key] = "$value"
    }
    export-cache -data $settings -container "user-settings" -dir $syncdir
 
    import-settings
}

function push {
    param([Parameter(Mandatory=$true,ValueFromPipeline=$true)] $what, $stackname = "default") 

    $stack = import-cache -container "stack.$stackname" -dir (get-syncdir)
    
    if ($stack -eq $null) { $stack = @(); $no = 1 }
    else { $stack = @($stack); $no = $stack.Length + 1 }

    $props = [ordered]@{
        no = $no
        value = $what
        ts = get-date -Format "yyyy-MM-dd HH:mm:ss"
    }
    $item = new-object -type pscustomobject -Property $props
    $stack += @($item)
    export-cache -data $stack -container "stack.$stackname"  -dir (get-syncdir)
    peek -stackname $stackname
}

function pop {
    param($stackname = "default") 
    
    $stack = import-cache -container "stack.$stackname" -dir (get-syncdir)
    if ($stack -eq $null -or $stack.length -eq 0) { return $null }
    else { $stack = @($stack) }
    $item = $stack[$stack.length-1]
    $stack = $stack | select -First ($stack.Length-1)
    if ($stack -eq $null) {
        remove-stack -container "stack.$stackname" -dir (get-syncdir)
    } else {
        export-cache -data $stack -container "stack.$stackname" -dir (get-syncdir)
    }
    return $item
}

function peek {
    param($stackname = "default") 

    $stack = @(import-cache -container "stack.$stackname" -dir (get-syncdir))
    if ($stack -eq $null -or $stack.length -eq 0) { return $null }
    $item = $stack[$stack.length-1]
    return $item
}

function get-stack {
    param($stackname = "default") 

    $stack = import-cache -container "stack.$stackname" -dir (get-syncdir)
    return $stack
}


function remove-stack {
    param($stackname = "default") 

    remove-cache -container "stack.$stackname" -dir (get-syncdir)    
}

function idea {
    [Cmdletbinding(DefaultParameterSetName="list")]
    param(
        [Parameter(mandatory=$true,ParameterSetName="add",Position=1)]
        $idea,                 
        [Parameter(mandatory=$true,ParameterSetName="search")]
        $search,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$go,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [Parameter(mandatory=$false,ParameterSetName="list")]
        [switch][bool]$done,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$remove,
        [Parameter(mandatory=$false)]$stackname = "ideas"
    ) 
    switch($PSCmdlet.ParameterSetName) {
        { $_ -eq "add" -and !$done -and !$remove } {             
            if ($go) {
                if ($idea.gettype() -eq [int]) {
                    $found = idea -search $idea
                    if ($found -eq $null) { return }
                    $idea = $found
                }                 
                else {
                    push $idea -stackname $stackname
                    $idea = peek -stackname $stackname
                }
                push "idea: $($idea.value)"
            } else {
                push $idea -stackname $stackname
            }
        }
        "list" {
            if ($done) {
                stack -stackname "$stackname.done"    
            } else {
                stack -stackname $stackname    
            }
        }
        { $_ -eq "search" `
            -or ($_ -eq "add" -and ($done -or $remove)) } {
            $ideas = stack -stackname $stackname  
            if ($search -eq $null) { $search = $idea } 
            $found = $ideas | ? { (($search.gettype() -eq [int]) -and $_.no -eq $search) -or $_.value -match "$search" }
            if ($found -eq $null) {
                if ($search.gettype() -eq [int]) { write-warning "no idea with id $search found" }
                else { write-warning "no idea matching '$search' found" }
                return
            }
            $found = @($found) 

            if ($_ -eq "search") {
                return $found
            }

            if ($found.Length -gt 1) {
                write-warning "more than one idea matching '$search' found:"
                $found | format-table | out-string | write-host
                return
            }                        
            write-verbose "found matching idea: $found" 
            
            if ($done) {
                push $found[0] -stackname "$stackname.done"
            }
            if ($done -or $remove) {
                $newstack = $ideas | ? { $_.no -ne $found[0].no }
                export-cache -data $newstack -container "stack.$stackname" -dir (get-syncdir)            
            }
        }
    }    
}

function pop-idea {
     pop -stackname "ideas"
}


function todo {
    param(
        [Parameter(mandatory=$true,ParameterSetName="add",Position=1)]
        $idea,                 
        [Parameter(mandatory=$true,ParameterSetName="search")]
        $search,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$go,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [Parameter(mandatory=$false,ParameterSetName="list")]
        [switch][bool]$done,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$remove
        )

    idea @PSBoundParameters -stackname "todo"
}

new-alias stack get-stack
new-alias tp test-path
new-alias git-each invoke-giteach
new-alias gitr git-each
new-alias x1b write-controlchar
new-alias swt set-windowtitle
new-alias pin-totaskbar Install-TaskBarPinnedItem
new-alias killall stop-allprocesses
new-alias tee-filter split-output
new-alias any test-any
new-alias relmo reload-module
new-alias tcpping test-tcp
new-alias is-admin test-isadmin

Export-ModuleMember -Function * -Cmdlet * -Alias *

