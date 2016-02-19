#[cmdletbinding()]
param ($command, [Alias("p")][switch][bool]$persistent, [switch][bool]$verbose) 

write-host "pyvm - python version manager"
#write-host "command=$command args=$args"

import-module pathutils
Import-Module oneliners

$vp = $VerbosePreference
try {
if ($verbose) { $VerbosePreference = "Continue" }


$paths = @{
 python3 =   "c:\tools\python3","C:\tools\python3\scripts"
 python2 =   "c:\tools\python2","C:\tools\python2\scripts"
}



switch($command) {
    "list" {
        write-host "Available python versions"
        $paths.GetEnumerator() | % {
            $active = contains-path $_.Value
            $msg = ""
            if ($active) { $msg += " * " }
            else { $msg += "   " }
            $msg += $_.Key 
            $msg += "  " + $_.Value
            write-host $msg
        }
    }
    "use" {
        if ($args.Length -eq 0) {
            throw "must specify a version"`
        }
        $ver = $args[0]
        switch($ver) {
            { @("3", "python3") -contains $_ } { 
                write-host "using $($paths.python3)"
                $paths.values | % { 
                    write-verbose "removing $_ from path"
                    remove-frompath $_
                    }
                if (!(test-path $paths.python3| test-any)) {
                    throw "path '$($paths.python3)' not found!"
                }
                add-topath $paths.python3 -persistent:$persistent
                }
            { @("2", "python2") -contains $_ } { 
                write-host "using  $($paths.python2)"
                $paths.values | % { 
                    write-verbose "removing $_ from path"
                    remove-frompath $_
                }
                if (!(test-path $paths.python2 | test-any)) {
                    throw "path '$($paths.python2)' not found!"
                }
                add-topath $paths.python2 -persistent:$persistent
            }
            { @("none", "no") -contains $_ } {
                 write-host "disabling python"
                $paths.values | % { 
                    write-verbose "removing $_ from path"
                    remove-frompath $_ -persistent:$persistent
                }
            }
            default {
                throw "unrecognized version"
            }
        }
    }
    default {
        write-verbose "usage: "
        write-verbose " pyvm list"
        write-verbose " pyvm use"
    }
    
}

    write-verbose "PATH="
    write-verbose "`r`n$env:path"
    
} finally {
    $VerbosePreference = $vp
}

#write to _Env.cmd for cmd wrapper
"set PATH=$env:PATH" | out-file "$env:TEMP\_env.cmd" -Encoding ascii