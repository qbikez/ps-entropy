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