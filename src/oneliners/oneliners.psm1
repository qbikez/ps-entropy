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

new-alias tp test-path
new-alias git-each invoke-giteach
new-alias gitr git-each
new-alias x1b write-controlchar
new-alias swt set-windowtitle
new-alias pin-totaskbar Install-TaskBarPinnedItem
new-alias killall stop-allprocesses
new-alias tee-filter split-output
new-alias any test-any

Export-ModuleMember -Function * -Cmdlet * -Alias *