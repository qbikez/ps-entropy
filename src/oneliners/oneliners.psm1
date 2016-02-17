function git-each($cmd) {
    gci | ? { $_.psiscontainer } | % { pushd; cd $_; if (tp ".git") { write-host; log-info $_; git $cmd }; popd; }
}
function git-pull {
    git-each "pull"
}

function parse-colorcode($color) {
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
    $n,$light = parse-colorcode $n    
    Write-Output  ([char](0x1b) + "[$($base+$n);m")
    if ($light)  { Write-Output ([char](0x1b) + "[1;m") }
}

function set-color($n) {
    $base = 30
    $n,$light = parse-colorcode $n
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

function tee-filter {
    [CmdletBinding()] 
    param([Parameter(ValueFromPipeline=$true)]$item, [ScriptBlock] $Filter, $filePath, [switch][bool] $append)
    process {
        $null = $_ | ? $filter | tee-object -filePath $filePath -Append:$append 
        $_
    }
}

function killall ($name) {
    cmd /C taskkill /IM "$name.exe" /F
    cmd /C taskkill /IM "$name" /F
}

new-alias tp test-path
new-alias gitr git-each
new-alias x1b write-controlchar
new-alias swt set-windowtitle

Export-ModuleMember -Function * -Cmdlet * -Alias *